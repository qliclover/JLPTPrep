#!/usr/bin/env python3
"""把《无敌绿宝书》的 OCR 结果解析成词条，并用 JMdict 校验。

为什么需要校验：Vision OCR 的**日语**识别得很干净，但**中文**大约两成字符是错的
（"回想起来" → "同想起来"）。而且 OCR 再好也会有错，直接信它等于把错误当权威教给用户。

所以策略是：
  - 读音和表记 —— 必须能在 JMdict 里对上，对不上就整条丢掉
  - 中文释义 —— 只有在日语侧校验通过时才采信，并且标记出可疑的
  - 例句 —— 日语侧保留，中文翻译标记为待核

用法: python3 Tools/parse_lvbaoshu.py <ocr.jsonl> <jmdict.sqlite> <输出.json>
"""
import json
import re
import sqlite3
import sys
from pathlib import Path

OCR, JMDICT, OUT = (Path(p) for p in sys.argv[1:4])

# 版式：  よみ + 声调数字 + 【漢字】 +（词性）+ 中文
# 例：    りょこう◎【旅行】（名・自サ）旅行
ENTRY = re.compile(
    r"^(?P<reading>[ぁ-ゖー]+)\s*"
    # 声调标记：带圈数字（⓪ 是 U+24EA，① 起是 U+2460，不连续，只能逐个列）
    r"[⓪①-⑳㉑-㉟0-9０-９◎○●\s]*"
    r"[【\[［](?P<expr>[^】\]］]{1,14})[】\]］]\s*"
    r"[（(](?P<pos>[^）)]{0,12})[）)]\s*"
    r"(?P<zh>.*)$"
)
EXAMPLE = re.compile(r"^例\s*(?P<ja>.+)$")

KANA = re.compile(r"[ぁ-ゖ]")
# 中文释义里出现这些字符基本可以断定是 OCR 噪声
ZH_NOISE = re.compile(r"[A-Za-z0-9<>&;#\\/|^~`=+\[\]{}$@*_ぁ-ゖァ-ヺ]")


def normalize(text: str) -> str:
    return (text.replace("：", "；").replace(":", "；")
                .replace("，", "，").strip(" .。，、；:·　"))


def main():
    db = sqlite3.connect(JMDICT)
    entries, stats = [], {
        "lines": 0, "parsed": 0, "jmdict_ok": 0, "reading_ok": 0,
        "zh_clean": 0, "examples": 0,
    }

    pending = None   # 上一条词条，等它的例句
    for raw in OCR.open(encoding="utf-8"):
        page = json.loads(raw)
        for item in page["lines"]:
            text = item["text"].strip()
            stats["lines"] += 1

            if example := EXAMPLE.match(text):
                # 例句里日中用 ／ 或 / 分隔
                ja = re.split(r"[／/]", example.group("ja"))[0].strip()
                if pending is not None and KANA.search(ja) and len(ja) > 6:
                    pending.setdefault("examples", []).append({"ja": ja})
                    stats["examples"] += 1
                continue

            match = ENTRY.match(text)
            if not match:
                continue
            stats["parsed"] += 1

            reading = match.group("reading")
            expression = match.group("expr").strip()
            zh = normalize(match.group("zh"))

            # ── 日语侧必须能被 JMdict 印证，否则整条丢掉
            rows = db.execute(
                """SELECT e.reading FROM entry e JOIN lookup l ON e.id = l.entry_id
                   WHERE l.key = ? LIMIT 20""", (expression,)
            ).fetchall()
            if not rows:
                continue
            stats["jmdict_ok"] += 1
            if reading not in {r[0] for r in rows}:
                # OCR 把读音认错了。表记还在，但读音是这类 App 最不能错的东西，丢掉。
                continue
            stats["reading_ok"] += 1

            suspicious = bool(ZH_NOISE.search(zh)) or not zh
            if not suspicious:
                stats["zh_clean"] += 1

            pending = {
                "expression": expression,
                "reading": reading,
                "posRaw": match.group("pos"),
                "meaningZh": "" if suspicious else zh,
                "meaningZhRaw": zh,
                "needsReview": suspicious,
                "page": page["page"],
            }
            entries.append(pending)

    # 同一个词可能在书里出现多次，保留信息最全的那条
    best = {}
    for entry in entries:
        key = (entry["expression"], entry["reading"])
        current = best.get(key)
        score = (len(entry["meaningZh"]), len(entry.get("examples", [])))
        if current is None or score > (len(current["meaningZh"]), len(current.get("examples", []))):
            best[key] = entry

    result = sorted(best.values(), key=lambda e: e["page"])
    OUT.write_text(json.dumps(result, ensure_ascii=False, indent=1), encoding="utf-8")

    print(f"OCR 行数            {stats['lines']}")
    print(f"匹配词条版式        {stats['parsed']}")
    print(f"表记在 JMdict 里    {stats['jmdict_ok']}")
    print(f"读音也对得上        {stats['reading_ok']}   ← 只有这些进入结果")
    print(f"中文释义看着干净    {stats['zh_clean']}")
    print(f"抓到例句            {stats['examples']}")
    print(f"去重后              {len(result)} 条 → {OUT}")


main()
