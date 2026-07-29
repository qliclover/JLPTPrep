#!/usr/bin/env python3
"""把 JMdict XML 编译成随包的 SQLite 索引。

在构建期做这件事，而不是运行时 —— 60MB XML 在手机上解析要好几秒且吃内存。
输出的库是只读的，App 只查不写。
"""
import re
import sqlite3
import sys
import xml.etree.ElementTree as ET

SRC, DST = sys.argv[1], sys.argv[2]

# JMdict 用自定义实体表示词性（<pos>&v5k;</pos>）。DTD 不随文件走，
# 直接解析会报未定义实体，所以先把它们换成纯文本。
# 注意保留 XML 标准的五个实体。
STANDARD = {"amp", "lt", "gt", "quot", "apos"}
raw = open(SRC, encoding="utf-8").read()
raw = re.sub(
    r"&([a-zA-Z0-9-]+);",
    lambda m: m.group(0) if m.group(1) in STANDARD else m.group(1),
    raw,
)

root = ET.fromstring(raw)

db = sqlite3.connect(DST)
db.executescript("""
DROP TABLE IF EXISTS entry;
DROP TABLE IF EXISTS lookup;
CREATE TABLE entry (
    id       INTEGER PRIMARY KEY,
    kanji    TEXT,           -- 主表记，可为空（纯假名词）
    reading  TEXT NOT NULL,  -- 主读音
    pos      TEXT,           -- 词性代码，逗号分隔
    glosses  TEXT NOT NULL,  -- 英文释义，义项间用 ' / '，同义项内用 '; '
    common   INTEGER NOT NULL DEFAULT 0
);
-- 所有可查形（全部表记 + 全部读音）都映射到词条，
-- 这样「食べる」和「たべる」都能查到同一条。
CREATE TABLE lookup (
    key      TEXT NOT NULL,
    entry_id INTEGER NOT NULL
);
""")

MAX_SENSES = 3
MAX_GLOSSES = 3

entries = []
lookups = []

for entry in root.iter("entry"):
    seq = int(entry.findtext("ent_seq"))

    kanji_forms, readings, common = [], [], False

    for k in entry.findall("k_ele"):
        text = k.findtext("keb")
        if text:
            kanji_forms.append(text)
            if k.find("ke_pri") is not None:
                common = True

    for r in entry.findall("r_ele"):
        text = r.findtext("reb")
        if text:
            readings.append(text)
            if r.find("re_pri") is not None:
                common = True

    if not readings:
        continue

    pos_codes, sense_texts = [], []
    for sense in entry.findall("sense")[:MAX_SENSES]:
        for p in sense.findall("pos"):
            if p.text and p.text not in pos_codes:
                pos_codes.append(p.text)
        glosses = [g.text for g in sense.findall("gloss")[:MAX_GLOSSES] if g.text]
        if glosses:
            sense_texts.append("; ".join(glosses))

    if not sense_texts:
        continue

    entries.append((
        seq,
        kanji_forms[0] if kanji_forms else None,
        readings[0],
        ",".join(pos_codes),
        " / ".join(sense_texts),
        1 if common else 0,
    ))
    for key in set(kanji_forms + readings):
        lookups.append((key, seq))

db.executemany("INSERT INTO entry VALUES (?,?,?,?,?,?)", entries)
db.executemany("INSERT INTO lookup VALUES (?,?)", lookups)
db.executescript("""
CREATE INDEX idx_lookup_key ON lookup(key);
VACUUM;
ANALYZE;
""")
db.commit()

print(f"词条 {len(entries)}  可查形 {len(lookups)}  常用词 {sum(e[5] for e in entries)}")
db.close()
