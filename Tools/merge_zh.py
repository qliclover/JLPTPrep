#!/usr/bin/env python3
"""把手写的中文释义合并进内容包。

释义文件是 `序号<TAB>中文`，序号对应 `<待写清单>` 里的行号 ——
用序号而不是表记做键，是因为同一个表记可能有多条（不同读音），按表记会串行。

用法: python3 Tools/merge_zh.py <pack.json> <todo.tsv> <zh目录>
"""
import json
import sys
from pathlib import Path

PACK, TODO, ZH_DIR = (Path(p) for p in sys.argv[1:4])

# 待写清单：序号 → 表记（用来交叉验证，防止序号错位）
expected = {}
for line in TODO.read_text(encoding="utf-8").splitlines()[1:]:
    parts = line.split("\t")
    if len(parts) >= 2:
        expected[int(parts[0])] = parts[1]

translations = {}
for path in sorted(ZH_DIR.glob("*.tsv")):
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        index, _, zh = line.partition("\t")
        zh = zh.strip()
        if zh:
            translations[int(index)] = zh

missing = sorted(set(expected) - set(translations))
extra = sorted(set(translations) - set(expected))
if missing:
    print(f"⚠️  {len(missing)} 条没写: {missing[:10]}")
if extra:
    print(f"⚠️  {len(extra)} 条序号不在清单里: {extra[:10]}")

pack = json.loads(PACK.read_text(encoding="utf-8"))
todo_words = [w for w in pack["vocab"] if not w["meaningZh"]]
if len(todo_words) != len(expected):
    print(f"❌ 清单 {len(expected)} 条，内容包里待写的有 {len(todo_words)} 条 —— 对不上，中止")
    sys.exit(1)

applied = 0
for index, word in enumerate(todo_words):
    # 表记必须和清单对得上，否则说明顺序变了，宁可中止也不能写错
    if word["expression"] != expected[index]:
        print(f"❌ 序号 {index} 表记不符：包里是 {word['expression']}，清单是 {expected[index]}")
        sys.exit(1)
    if zh := translations.get(index):
        word["meaningZh"] = zh
        applied += 1

PACK.write_text(json.dumps(pack, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
total = sum(1 for w in pack["vocab"] if w["meaningZh"])
print(f"写入 {applied} 条 · 该包中文覆盖 {total}/{len(pack['vocab'])}")
