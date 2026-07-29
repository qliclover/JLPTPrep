#!/usr/bin/env python3
"""把 SplitAudio 算出的音频片段合并进 ParseExam 的题库文件。

两侧都按「大题 + 题号」标识听力题，直接配对。

音频那边的题号是**听出来的**（录音里念「にばん」），试卷那边是**看出来的**
（OCR 读页面）。两个完全独立的来源指向同一道题 —— 能对上本身就是一重验证，
对不上就说明至少有一边错了，宁可不给音频也不能给错的。

用法：
    python3 Tools/merge_audio_segments.py <题库.json> <片段.json>
"""

import json
import sys
from pathlib import Path

BANK = Path(sys.argv[1])
SEGMENTS = Path(sys.argv[2])

bank = json.loads(BANK.read_text(encoding="utf-8"))
segments = json.loads(SEGMENTS.read_text(encoding="utf-8"))

by_key = {(s["section"], s["number"]): s for s in segments}

matched = missing = 0
for q in bank["questions"]:
    if "聴解" not in q["subject"]:
        continue
    seg = by_key.get((q["section"], q["number"]))
    if seg is None:
        missing += 1
        continue
    q["audioStart"] = round(seg["start"], 2)
    q["audioEnd"] = round(seg["end"], 2)
    matched += 1

listening = sum(1 for q in bank["questions"] if "聴解" in q["subject"])
BANK.write_text(
    json.dumps(bank, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8"
)

print(f"  听力题 {listening} 道 · 配上音频 {matched} 道 · 没配上 {missing} 道")
if missing:
    print("  没配上的多半是试卷侧的大题号解析错了 —— 音频那边是听出来的，更可靠。")
