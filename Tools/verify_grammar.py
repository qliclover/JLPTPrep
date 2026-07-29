#!/usr/bin/env python3
"""检查语法内容包的自洽性与覆盖度。

写语法解释和写词典释义不一样：一条错的语法说明会被背下来带进考场，
比没有这一条更糟。所以能机器查的部分必须先兜住，剩下的才轮到人工抽查。

这里查五件事：

1. **结构完整** —— slug 唯一、必填字段非空、等级合法
2. **例句里真的出现了这个句型** —— 写了「〜たことがある」却给一句不含它的
   例句，是最容易犯也最难自查的错
3. **易混跳转指向真实存在的条目** —— contrastSlugs 悬空说明写的时候记错了
4. **例句用词不超纲** —— 拿词库对一遍，N5 的语法例句里塞 N2 词毫无意义
5. **真题覆盖度** —— 用解析出来的真实语法题反查：这些题考的句型，
   我的表里收了没有。这是唯一有外部基准的一项。

用法：
    python3 Tools/verify_grammar.py <grammar_n5.json> [grammar_n4.json ...]
"""

import json
import re
import sys
import glob
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEVELS = {"N1", "N2", "N3", "N4", "N5"}

packs = []
for arg in sys.argv[1:]:
    packs.append(json.loads(Path(arg).read_text(encoding="utf-8")))

entries = [e for p in packs for e in p["grammar"]]
by_slug = {e["slug"]: e for e in entries}
problems = []

# ── 1. 结构 ───────────────────────────────────────────────
seen = set()
for e in entries:
    slug = e.get("slug", "")
    if not slug:
        problems.append("有条目缺 slug")
    elif slug in seen:
        problems.append(f"{slug}: slug 重复")
    seen.add(slug)
    for field in ("pattern", "connectionRule", "meaningZh"):
        if not e.get(field):
            problems.append(f"{slug}: {field} 为空")
    if e.get("level") not in LEVELS:
        problems.append(f"{slug}: 等级 {e.get('level')} 不合法")
    if not e.get("examples"):
        problems.append(f"{slug}: 没有例句")

# ── 2. 例句里必须出现这个句型 ──────────────────────────────
def core(pattern: str) -> list[str]:
    """从句型里取出可检索的片段。

    要处理三件事，少一件就会误报：

    1. **「〜」是占位符，也是分隔符。**「〜は〜です」不能整体去掉波浪线
       变成「はです」——那在任何句子里都找不到。要拆成「は」「です」。
    2. **「／」分隔变体**，各算一个片段。
    3. **活用会改变词尾。**「〜たことがあります」的例句可能是否定形
       「〜たことがありません」。所以对以礼貌体结尾的片段，额外生成一个
       去掉词尾的词干变体。

    单字片段（「が」「は」）保留 —— 它们确实没有区分力，但对那些
    **本身就是单个助词**的条目，这是唯一能匹配的东西。宁可放过，
    不可误杀。
    """
    # 括号里是注解（「（様態）」「（かた）」），整块去掉 ——
    # 只去括号会留下「そうです様態」这种任何句子里都没有的串。
    pattern = re.sub(r"[（(][^）)]*[）)]", "", pattern)
    parts = re.split(r"[／/、|〜～]", pattern)
    out = []
    for part in parts:
        cleaned = part.strip()
        if not cleaned:
            continue
        out.append(cleaned)
        # 活用变体：去掉礼貌体词尾，留下能匹配否定/过去形的词干
        for tail in ("ます", "ません", "です", "ください", "いいです"):
            if cleaned.endswith(tail) and len(cleaned) > len(tail) + 1:
                cleaned = cleaned[: -len(tail)]
                out.append(cleaned)
                break
        # 再砍掉一个字符：活用会改末尾那个假名
        # （「ておきます」→「ておき」，而例句里是「ておいて」，共同前缀是「てお」）
        if len(cleaned) >= 3:
            out.append(cleaned[:-1])
    # て形接在ん・ん段之后会浊化成で（「読んでしまう」而不是「読んてしまう」）。
    # 这是音变不是错别字，两种都得认。
    out += [f.replace("て", "で", 1) for f in out if f.startswith("て")]
    return out


# 动词变形类条目（可能形・受身形・使役形・意志形）没法用子串查 ——
# 「話せます」里不含「可能形」三个字。这类条目的正确性只能靠人工看，
# 所以显式豁免并**在报告里说清楚豁免了几条**，而不是悄悄跳过。
CONJUGATION_FORMS = ("可能形", "受身形", "使役形", "意志形", "ば形")

def is_conjugation_entry(e: dict) -> bool:
    return any(f in e.get("pattern", "") for f in CONJUGATION_FORMS)

exempted = []
for e in entries:
    if is_conjugation_entry(e):
        exempted.append(e["slug"])
        continue
    fragments = core(e.get("pattern", ""))
    if not fragments:
        continue
    for ex in e.get("examples", []):
        ja = ex.get("ja", "")
        # 活用会改变形态（「食べた」vs「食べる」），所以只要任一变体片段
        # 出现就算通过；全都不出现才是真问题。
        if not any(f in ja for f in fragments):
            problems.append(
                f"{e['slug']}: 例句里找不到句型「{e['pattern']}」 → {ja}"
            )

# ── 3. 易混跳转必须落到真实条目 ────────────────────────────
for e in entries:
    for target in e.get("contrastSlugs", []):
        if target not in by_slug:
            problems.append(f"{e['slug']}: 易混跳转指向不存在的 {target}")
        if target == e["slug"]:
            problems.append(f"{e['slug']}: 易混跳转指向自己")

# ── 4. 例句用词不超纲 ─────────────────────────────────────
vocab_by_level = {}
for path in glob.glob(str(ROOT / "App/Resources/vocab_n*.json")):
    pack = json.loads(Path(path).read_text(encoding="utf-8"))
    vocab_by_level[pack["level"]] = {v["expression"] for v in pack["vocab"]}

# 累积范围：N4 的例句可以用 N5 和 N4 的词
order = ["N5", "N4", "N3", "N2", "N1"]
def allowed(level: str) -> set[str]:
    result = set()
    for lv in order[: order.index(level) + 1]:
        result |= vocab_by_level.get(lv, set())
    return result

# 只查明显超纲的：出现在 N2/N1 词表、且不在允许范围内的词
hard = (vocab_by_level.get("N2", set()) | vocab_by_level.get("N1", set()))
for e in entries:
    ok = allowed(e.get("level", "N5"))
    # 敬语句型跳过用词检查：「お〜になります」会把普通动词变成
    # 「お帰り」「お読み」这种形式，它们出现在高阶词表里，
    # 但那是句型造出来的，不是例句用了超纲词。
    if "敬语" in e.get("tags", []):
        continue
    for ex in e.get("examples", []):
        for word in hard:
            # 只查三字以上的词。两字词在日语里子串巧合太多 ——
            # 「毎日日本語」里能"找到"「日日」，那不是用词超纲，是检查器的错。
            # 句型本身用到的词不算超纲 ——「お帰りになる」是敬语句型，
            # 「お帰り」出现在 N2 词表里不代表这个例句超纲。
            if word in e.get("pattern", "") + e.get("connectionRule", ""):
                continue
            # 片假名词要求整词匹配 —— 「メニュー」里含「ニュー」，
            # 那是子串巧合不是用词超纲。前后不能再接片假名。
            ja = ex.get("ja", "")
            if len(word) >= 3 and word in ja and word not in ok:
                at = ja.index(word)
                before = ja[at - 1] if at > 0 else ""
                after = ja[at + len(word)] if at + len(word) < len(ja) else ""
                katakana = lambda c: "\u30a0" <= c <= "\u30ff"
                if katakana(word[0]) and (katakana(before) or katakana(after)):
                    continue
                problems.append(
                    f"{e['slug']}: 例句用了超纲词「{word}」 → {ex['ja']}"
                )
                break

# ── 5. 真题覆盖度 ─────────────────────────────────────────
exam_dir = ROOT / "Docs/exams"
grammar_questions = []
if exam_dir.exists():
    for path in sorted(exam_dir.glob("N4-*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        for q in data.get("questions", []):
            if "文法" in q.get("subject", ""):
                grammar_questions.append(q)

covered = 0
uncovered = []
# **只用两字以上的片段算覆盖。**
# 单字片段（「が」「は」「を」）在任何日语句子里都能命中，
# 拿它们统计出来的「覆盖率 100%」毫无意义 —— 那测的是「这是日语吗」，
# 不是「这个句型收了吗」。
all_fragments = [(f, e["slug"]) for e in entries
                 for f in core(e.get("pattern", "")) if len(f) >= 2]
for q in grammar_questions:
    text = q.get("stem", "") + "".join(q.get("options", []))
    if any(f in text for f, _ in all_fragments):
        covered += 1
    else:
        uncovered.append(q)

# ── 报告 ─────────────────────────────────────────────────
print(f"  条目 {len(entries)} 条", end="")
counts = {}
for e in entries:
    counts[e.get("level")] = counts.get(e.get("level"), 0) + 1
print("（" + " · ".join(f"{k} {v}" for k, v in sorted(counts.items(), reverse=True)) + "）")
print(f"  例句 {sum(len(e.get('examples', [])) for e in entries)} 句")
if exempted:
    print(f"  例句检查豁免 {len(exempted)} 条（动词变形类，只能人工核）：{', '.join(exempted)}")
print()

if grammar_questions:
    rate = covered * 100 // max(len(grammar_questions), 1)
    print(f"  真题语法题 {len(grammar_questions)} 道 · 句型已收录 {covered} 道（{rate}%）")
    if uncovered:
        print(f"  没覆盖到的 {len(uncovered)} 道，前几道：")
        for q in uncovered[:5]:
            print(f"    {q.get('stem', '')[:44]}")
    print()

if problems:
    print(f"  ✗ {len(problems)} 处问题：")
    for p in problems[:25]:
        print(f"    {p}")
    if len(problems) > 25:
        print(f"    …还有 {len(problems) - 25} 处")
    sys.exit(1)
else:
    print("  ✓ 结构、例句、跳转、用词四项检查全过")
