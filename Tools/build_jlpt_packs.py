#!/usr/bin/env python3
"""把社区 JLPT 词表编译成 App 的内容包（每个等级一个）。

数据来源
  jamsinclair/open-anki-jlpt-decks（MIT）— 提供 N5–N1 的表记、读音、英文释义。
  JMdict（CC BY-SA 4.0）— 用来校验读音、补出词性。
  Content/seed/vocab_n5_sample.json — 手工写的中文释义和例句，合并进 N5 包。

**JLPT 官方从 2010 年起不再公布词表**，所有流通的 N5–N1 词表都是社区根据真题
反推的，彼此有出入。这里编译出来的是「某个社区版本」，不是官方数据。

用法：
  python3 Tools/build_jlpt_packs.py <csv目录> <jmdict.sqlite> <输出目录>
"""
import csv
import json
import re
import sqlite3
import sys
from pathlib import Path

CSV_DIR, JMDICT, OUT_DIR = (Path(p) for p in sys.argv[1:4])
OUT_DIR.mkdir(parents=True, exist_ok=True)

REPO_ROOT = Path(__file__).resolve().parent.parent
HAND_WRITTEN = REPO_ROOT / "Content" / "seed" / "vocab_n5_sample.json"

# JMdict 词性代码 → 中文。和 JMDictionary.posLabelZh 保持一致：
# 出题时靠这个字符串给干扰项分组，两边对不上会让分组失效。
POS_ZH = {
    "n": "名词", "n-adv": "名词·副词", "n-t": "时间名词", "n-suf": "名词后缀", "n-pref": "名词前缀",
    "pn": "代词", "adj-i": "い形容词", "adj-ix": "い形容词", "adj-na": "な形容词",
    "adj-no": "の形容词", "adj-pn": "连体词", "adj-t": "たる形容词",
    "adv": "副词", "adv-to": "と副词",
    "v1": "动词·二类", "v1-s": "动词·二类",
    "v5u": "动词·一类", "v5k": "动词·一类", "v5g": "动词·一类", "v5s": "动词·一类",
    "v5t": "动词·一类", "v5n": "动词·一类", "v5b": "动词·一类", "v5m": "动词·一类",
    "v5r": "动词·一类", "v5r-i": "动词·一类", "v5aru": "动词·一类",
    "v5k-s": "动词·一类", "v5u-s": "动词·一类",
    "vk": "动词·三类", "vs": "サ变名词", "vs-i": "动词·三类", "vs-s": "动词·三类",
    "aux": "助动词", "aux-v": "助动词", "aux-adj": "助动词",
    "prt": "助词", "conj": "接续词", "int": "感叹词", "exp": "惯用表达",
    "ctr": "量词", "suf": "后缀", "pref": "前缀", "num": "数词", "cop": "系动词",
}
# 自他动词是修饰性的，单独出现时不足以给词分组
MODIFIER_POS = {"vt", "vi", "unc"}


def clean_reading(raw: str) -> str:
    """源数据的读音字段有几种脏格式。

    `けっこん (する)` —— サ变标注；`いく; ゆく` —— 多个读音。
    取第一个、去掉括注即可，这是词条的主读音。
    """
    reading = re.split(r"[;；]", raw)[0]
    reading = re.sub(r"[（(].*?[）)]", "", reading)
    return reading.strip()


def clean_expression(raw: str) -> str:
    return re.split(r"[;；]", raw)[0].strip()


def load_hand_written():
    """手工写的中文释义 + 例句，按表记索引。"""
    if not HAND_WRITTEN.exists():
        return {}
    data = json.loads(HAND_WRITTEN.read_text(encoding="utf-8"))
    return {w["expression"]: w for w in data["vocab"]}


def main():
    db = sqlite3.connect(JMDICT)
    hand = load_hand_written()

    seen = set()          # (表记, 读音) —— 跨等级去重，保留最简单的那一级
    stats = {"total": 0, "zh": 0, "pos_from_jmdict": 0, "examples": 0, "reading_fixed": 0}

    # 从 N5 往上走，先出现的等级为准
    for level_num in [5, 4, 3, 2, 1]:
        level = f"N{level_num}"
        rows = list(csv.DictReader((CSV_DIR / f"n{level_num}.csv").open(encoding="utf-8")))
        vocab = []
        used_slugs = set()

        for row in rows:
            expression = clean_expression(row["expression"])
            reading = clean_reading(row["reading"])
            if not expression or not reading:
                continue
            key = (expression, reading)
            if key in seen:
                continue
            seen.add(key)

            # 用 JMdict 补词性，顺带校验读音
            pos = ""
            entries = db.execute(
                """SELECT e.reading, e.pos FROM entry e JOIN lookup l ON e.id = l.entry_id
                   WHERE l.key = ? ORDER BY e.common DESC LIMIT 5""",
                (expression,),
            ).fetchall()
            for jm_reading, jm_pos in entries:
                if not jm_pos:
                    continue
                codes = [c for c in jm_pos.split(",") if c not in MODIFIER_POS]
                label = next((POS_ZH[c] for c in codes if c in POS_ZH), None)
                if label:
                    pos = label
                    stats["pos_from_jmdict"] += 1
                    break
            # 源词表的读音和 JMdict 都对不上时，采信 JMdict 的常用读音
            if entries and reading not in [r for r, _ in entries]:
                jm_main = entries[0][0]
                if jm_main and expression != reading:
                    reading = jm_main
                    stats["reading_fixed"] += 1

            # 同一等级里同一个表记可能有多个读音（行く いく / ゆく），
            # slug 只用表记会撞车，导入时整包会被 duplicateSlugs 拦下。
            slug = f"jlpt-{level.lower()}-{expression}"
            if slug in used_slugs:
                slug = f"{slug}-{reading}"
            used_slugs.add(slug)

            entry = {
                "slug": slug,
                "expression": expression,
                "reading": reading,
                "meaningZh": "",
                "meaningEn": row["meaning"].strip(),
                "partOfSpeech": pos or "未分类",
            }

            # 手写的中文释义和例句优先，覆盖掉英文
            if extra := hand.get(expression):
                entry["meaningZh"] = extra["meaningZh"]
                entry["partOfSpeech"] = extra["partOfSpeech"]
                if extra.get("furigana"):
                    entry["furigana"] = extra["furigana"]
                if extra.get("examples"):
                    entry["examples"] = extra["examples"]
                    stats["examples"] += 1
                if extra.get("tags"):
                    entry["tags"] = extra["tags"]
                stats["zh"] += 1

            vocab.append(entry)
            stats["total"] += 1

        pack = {
            "schemaVersion": 2,
            "packID": f"jlpt-{level.lower()}",
            "level": level,
            "vocab": vocab,
        }
        path = OUT_DIR / f"vocab_{level.lower()}.json"
        path.write_text(json.dumps(pack, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        print(f"{level}: {len(vocab):>5} 词  {path.stat().st_size / 1024:>6.0f} KB")

    print(
        f"\n合计 {stats['total']} 词 · 中文释义 {stats['zh']} · 例句 {stats['examples']}"
        f" · 词性来自 JMdict {stats['pos_from_jmdict']} · 读音订正 {stats['reading_fixed']}"
    )


main()
