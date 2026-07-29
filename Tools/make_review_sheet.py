#!/usr/bin/env python3
"""把 ParseExam 的输出做成一张可以人工核对的网页。

为什么需要这一步：自动解析能可靠地拿到「90 道题」和「93 个答案」两侧数据，
但把它们对应起来这一层，六轮迭代下来仍然做不对 —— 版面信号被 OCR 噪声污染，
而且没有任何基准能验证对错。

与其继续调解析器，不如把两侧摊开让人过一遍。核对的工作量是「确认序号对得上」，
不是逐字校对；一份卷子大约二十分钟。核完的题库是**可信的**，
而可信对备考材料是底线 —— 一个答案错了的练习题，比没有这道题有害。

用法：
    python3 Tools/make_review_sheet.py <ParseExam输出.json> [输出.html]
"""

import json
import sys
import html
from pathlib import Path

SRC = Path(sys.argv[1])
DST = Path(sys.argv[2]) if len(sys.argv) > 2 else SRC.with_suffix(".html")

exam = json.loads(SRC.read_text(encoding="utf-8"))
questions = exam["questions"]
raw = exam.get("rawAnswers", [])

# 答案按题号分段：题号回到 1（或变小）就是新科目开始
runs, previous = [], 10**9
for item in raw:
    if item["number"] <= previous:
        runs.append([])
    runs[-1].append(item)
    previous = item["number"]

rows = []
for index, q in enumerate(questions):
    # 给一个「猜测」：在同科目段里找相同题号的答案。猜错了人工改，猜对了省事。
    guess = ""
    for run in runs:
        for item in run:
            if item["number"] == q["number"]:
                guess = item["answer"]
                break
        if guess:
            break
    rows.append((index, q, guess))

def esc(s):
    return html.escape(s or "")

option_html = []
for index, q, guess in rows:
    opts = "".join(
        f'<label class="opt"><input type="radio" name="q{index}" value="{i+1}"'
        f'{" checked" if guess == i + 1 else ""}>'
        f'<span class="num">{i+1}</span><span class="txt">{esc(o)}</span></label>'
        for i, o in enumerate(q["options"])
    )
    warn = ""
    if q["warnings"]:
        warn = f'<div class="warn">{esc(" · ".join(q["warnings"]))}</div>'
    stem = esc(q["stem"]) or '<span class="muted">（听力题，题干在音频里）</span>'
    option_html.append(f"""
    <article class="q" data-index="{index}">
      <div class="meta">
        <span class="subject">{esc(q['subject'])}</span>
        <span class="no">第 {q['number']} 题</span>
      </div>
      <div class="stem">{stem}</div>
      <div class="opts">{opts}</div>
      {warn}
    </article>""")

answer_list = " ".join(
    f'<span class="chip"><b>{a["number"]}</b>{a["answer"]}</span>' for a in raw
)

DST.write_text(f"""<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>核对 · {esc(exam['level'])} {esc(exam['session'])}</title>
<style>
  :root {{ --bg:#f3f2f2; --text:#201f1d; --accent:#b68235; --accent7:#7d5411;
           --muted:#7d7979; --line:rgba(32,31,29,.16); }}
  @media (prefers-color-scheme:dark) {{
    :root {{ --bg:#1b1a18; --text:#ece9e4; --accent:#e1ad66; --accent7:#e1ad66;
             --muted:#a29d98; --line:rgba(236,233,228,.18); }}
  }}
  *{{box-sizing:border-box}}
  body{{margin:0;background:var(--bg);color:var(--text);line-height:1.7;
       font-family:-apple-system,"PingFang SC",sans-serif}}
  .wrap{{max-width:760px;margin:0 auto;padding:32px 20px 120px}}
  h1{{font-family:"Songti SC",serif;font-size:26px;margin:0 0 4px}}
  .sub{{color:var(--muted);font-size:13px;margin-bottom:20px}}
  .panel{{border:1px solid var(--line);border-radius:4px;padding:14px;margin-bottom:24px}}
  .panel h2{{font-size:13px;margin:0 0 8px;color:var(--accent7);
            letter-spacing:.1em;text-transform:uppercase}}
  .chip{{display:inline-block;font-size:12px;margin:2px 5px 2px 0;
        font-variant-numeric:tabular-nums}}
  .chip b{{color:var(--accent7);margin-right:3px}}
  .q{{border-top:1px solid var(--line);padding:16px 0}}
  .meta{{font-size:11px;color:var(--muted);letter-spacing:.08em;margin-bottom:6px}}
  .meta .no{{margin-left:10px;font-variant-numeric:tabular-nums}}
  .stem{{font-size:17px;margin-bottom:10px}}
  .muted{{color:var(--muted)}}
  .opt{{display:flex;align-items:flex-start;gap:8px;padding:5px 0;cursor:pointer}}
  .opt input{{margin-top:7px;accent-color:var(--accent)}}
  .opt .num{{color:var(--muted);font-size:13px;min-width:14px}}
  .opt .txt{{font-size:15px}}
  .opt:has(input:checked) .txt{{color:var(--accent7);font-weight:600}}
  .warn{{font-size:12px;color:var(--accent7);margin-top:6px}}
  .bar{{position:fixed;left:0;right:0;bottom:0;background:var(--bg);
       border-top:1px solid var(--line);padding:12px 20px;display:flex;
       gap:12px;align-items:center;justify-content:center}}
  button{{font:inherit;font-size:14px;padding:9px 20px;border-radius:4px;
         background:transparent;color:var(--accent7);
         border:1px solid var(--accent);cursor:pointer}}
  #count{{font-size:13px;color:var(--muted);font-variant-numeric:tabular-nums}}
</style></head><body><div class="wrap">

<h1>{esc(exam['level'])} · {esc(exam['session'])}</h1>
<p class="sub">
  解析出 {len(questions)} 道题、{len(raw)} 个答案。已按题号猜了一版，
  <b>请对照 PDF 核实</b>，改正后点底部导出。
</p>

<div class="panel">
  <h2>答案页原始序列（题号·答案）</h2>
  <div>{answer_list}</div>
</div>

{''.join(option_html)}

</div>
<div class="bar">
  <span id="count"></span>
  <button onclick="exportJSON()">导出核对结果</button>
</div>
<script>
const QUESTIONS = {json.dumps(questions, ensure_ascii=False)};
function update() {{
  const n = document.querySelectorAll('.q input:checked').length;
  document.getElementById('count').textContent = n + ' / ' + QUESTIONS.length + ' 已确认';
}}
document.addEventListener('change', update); update();
function exportJSON() {{
  QUESTIONS.forEach((q, i) => {{
    const picked = document.querySelector(`input[name=q${{i}}]:checked`);
    q.answer = picked ? Number(picked.value) : null;
    q.warnings = [];
  }});
  const out = {{ level: {json.dumps(exam['level'], ensure_ascii=False)},
                session: {json.dumps(exam['session'], ensure_ascii=False)},
                verified: true, questions: QUESTIONS }};
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([JSON.stringify(out, null, 2)],
           {{type:'application/json'}}));
  a.download = {json.dumps(exam['level'] + '-' + exam['session'] + '-verified.json', ensure_ascii=False)};
  a.click();
}}
</script></body></html>
""", encoding="utf-8")

print(f"  {DST}")
print(f"  {len(questions)} 道题 · {len(raw)} 个答案 · 已预填猜测，待核对")
