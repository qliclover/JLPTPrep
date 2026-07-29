# Handoff: JLPTPrep 界面改版 + N5–N1 等级词库

## Overview

给 JLPTPrep（SwiftUI / SwiftData 的 JLPT 备考 App）做的一整套界面设计，外加一个新功能：**N5–N1 等级词库管理**（选备考目标、导入词库包、启用/停用，队列随之变化）。

覆盖的界面：学习首页、复习卡片（正面/背面）、复习完成、书架、阅读器（横排 + 竖排）、点词详情、设置、**等级词库（新增）**，以及空状态和错误态、浅色与深色。

视觉方向：**Classical** —— 一套书本气质的编辑式系统。Cormorant Garamond 标题 + Lora 正文，日文用 Noto Serif JP 接续同一种明朝气质；金色 `#b68235` 只作描边和细线，按钮是描边不填色，卡片靠 1px hairline 分区，阴影极轻。

## About the Design Files

这个包里的 HTML 文件是**设计稿**，不是可以直接搬进项目的产品代码。它们用 HTML/CSS 画出预期的外观和行为，供你在**目标工程里用其原生技术栈重建**。

目标工程是 **SwiftUI + SwiftData**（`JLPTPrep.xcodeproj`，Core 为本地 SPM 包 `JLPTCore` / `JLPTContent` / `JLPTJapanese`）。请用 SwiftUI 的既有写法实现，不要引入 WebView 套 HTML。

文件清单：

| 文件 | 是什么 |
| --- | --- |
| `prototype/JLPT-App-Prototype.dc.html` | **可操作原型**（最重要）。在浏览器里直接打开就能点：Tab 切换、翻卡、评分推进、点词浮层、滑杆、振假名开关、横竖排切换、等级词库全流程。交互与动效以此为准。 |
| `static-screens/JLPT-App-Classical.dc.html` | 静态全屏集（11 屏）。排版、间距、字号以此为准，含深色两屏、空状态、错误态、完成页。 |
| `explorations/JLPT-App-Redesign.dc.html` | 早期两个自选视觉方向（「和紙」「夜灯」），**未被采用**，仅作参考，不要照它实现。 |
| `design-system/styles.css` | Classical 系统的唯一样式源：`:root` 里的全部 token + 组件类。所有颜色/间距/圆角的权威数值在这里。 |
| `design-system/readme.md` | Classical 的书面规范（该做什么、不该做什么）。 |

在浏览器里打开 HTML 时，`<link rel="stylesheet" href="_ds/classical-…/styles.css">` 的相对路径会失效 —— 把它改成 `../design-system/styles.css` 即可正常显示。

## Fidelity

**High-fidelity。** 颜色、字体、字号、间距、圆角、动效时长都是最终值，请按数值还原。唯一需要你判断的是 SwiftUI 与 Web 的固有差异（安全区、系统控件的最小点击区域、动态字体）。

原型里的数据是示例：N5 的 8 条词条取自仓库的 `Content/seed/vocab_n5_sample.json`；N4 以上的 8 条（練習・説明・提出・我慢・傾向・曖昧・顕著・逸脱）是我按同一 JSON schema 编的演示数据，**上线要换成真包**。

## Design Tokens

全部取自 `design-system/styles.css` 的 `:root`。在 Swift 侧建议做成一个 `Theme` 结构（`Color` 扩展 + `Font` 扩展），不要在 View 里散写 hex。

### 颜色 · 浅色

| 角色 | 值 | 用途 |
| --- | --- | --- |
| `--color-bg` | `#f3f2f2` | 页面底色（所有屏的背景） |
| `--color-surface` | `#eae9e9` | 次级面 |
| `--color-text` | `#201f1d` | 正文 |
| `--color-accent` | `#b68235` | 金 —— 只作描边、细线、下划线、小标签 |
| `--color-divider` | `#201f1d` 16% 透明 | 所有 1px hairline |
| neutral 100→900 | `#f8f4f4` `#eae7e7` `#d7d3d3` `#bab6b6` `#9b9797` `#7d7979` `#605d5d` `#444141` `#2d2b2b` | 灰阶。次要文字用 600/700，弱化文字 500 |
| accent 100→900 | `#fff3e4` `#ffe3bf` `#facb8d` `#e1ad66` `#c28d41` `#a06f24` `#7d5411` `#5a3b0a` `#3a270d` | 金阶。100/200 作淡填，700 作正文级金字（对比度够） |

规则：**金色不做大面积填充**。正文尺寸的金字用 `accent-700`，不要用 `accent` 本体（对比只有 3:1，够图标和大字，不够正文）。

### 颜色 · 深色（我在设计里的覆盖值，systems 里没有预置深色）

```
bg #1b1a18 · text #ece9e4 · accent #e1ad66（= accent-400，深底上金色要提亮一档）
divider = text 18% 透明 · neutral-600 #a29d98 · neutral-700 #c2bdb7
```

### 间距（密度 1.15×，务必用变量而非随手取整）

`--space-1` 4.6 · `--space-2` 9.2 · `--space-3` 13.8 · `--space-4` 18.4 · `--space-6` 27.6 · `--space-8` 36.8（px）

屏幕左右边距统一 `space-4` = 18.4pt。

### 圆角

`--radius-sm` 2 · `--radius-md` 4 · `--radius-lg` 7（px）。卡片和按钮 4，底部弹层顶角 7。**不要用大圆角**。

### 阴影

`--shadow-sm` `0 1px 2px rgba(45,43,43,.14)` · `--shadow-md` `0 3px 10px rgba(45,43,43,.16)` · `--shadow-lg` `0 12px 32px rgba(45,43,43,.22)`。只有底部弹层用 lg，其余几乎不用阴影。

### 字体

| 变量 | 字体 | 用在哪 |
| --- | --- | --- |
| `--font-heading` | **Cormorant Garamond**，semibold 600 为界面标题上限；越大越轻，展示级数字用 regular 400 | 页面标题、大数字、Tab 文字、统计数字 |
| `--font-body` | **Lora** 400/600 | 中文正文、说明文字、按钮文字 |
| （新增）`--font-jp` | **Noto Serif JP** 400/500 | 所有日文：词条、例句、书名、正文 |

字号（px = pt）：页面标题 26；卡片大数字 58；统计数字 21–22；词条 62（复习卡）/ 38（点词浮层）；日文正文 19，行高 2.2；正文 15；次要 13；说明 12；kicker 11 大写 + `letter-spacing .1em`。

**数字全部用 tabular figures**（CSS `font-feature-settings:'tnum'`；SwiftUI：`.monospacedDigit()`）—— 计数、间隔预览、百分比、词条数都要，避免跳动。中文/日文正文不要开 tnum。

不要用无衬线做强调，用字重和斜体。

## Screens / Views

以下按「屏 → 布局 → 组件」写。所有屏都是 390×844（iPhone 逻辑分辨率），顶部 50pt 状态栏区，底部 74pt 自定义导航栏（含 14pt 安全区留白）。

### 通用外壳

- **底部导航**：3 项 —— 学习 / 书架 / 设置。等宽 flex。文字 Cormorant Garamond 16pt。选中色 `accent-700`，未选 `neutral-600`。选中项**顶部一条 2pt 金线**，宽度 = 1/3 容器宽，切换时 `left` 以 260ms ease 滑过去。分隔用 1px `divider` 顶边。
  - SwiftUI：不要用系统 `TabView` 的默认 tabItem（拿不到金线动画）。用 `ZStack` + 自绘底栏，或 `TabView` 配 `.toolbarBackground` 再叠一层金线。
- **视图切换**：换 Tab / 进出复习时，内容区整体 opacity 1→0（150ms）换内容再 0→1（180ms ease）。原型里是 `switchTo()`。
- **卡片**（`.card`）：`background: transparent`，1px `divider` 边框，`radius-md`，`padding: space-4`。**不填色**。
- **按钮**：
  - primary = 1px `accent` 描边 + 透明底 + `accent` 文字；hover 12% 金淡填，按下 22%。
  - secondary = 1px `divider` 描边 + 透明底 + `text` 文字。
  - 「记得」这一个键例外：底为 `accent-100`（最淡的金）以示默认动作，仍带金描边。
  - 键盘/辅助焦点：`2px accent` 描边，offset 2。
- **标签**（`.tag`）：11pt，`padding 3px 10px`，`radius 3`。`tag-accent` = `accent-100` 底 + `accent-800` 字；`tag-neutral` = `neutral-100` 底 + `neutral-800` 字；`tag-outline` = 1px `accent` 描边 + `accent` 字。
- **进度线**：全部是 1px `divider` 底线 + 上面一条 3pt 实色（金或 `neutral-800`）。**不用圆头胶囊进度条**。宽度变化 400ms ease。

### 1. 学习首页

用户在这里看今天要做多少、一键开始、或接着读书。

- 顶栏：左「日本語 · {目标等级}」Cormorant 26pt；右 kicker 「含 N5 · N4 · N3」（备考范围，金色 11pt 大写）。下方 1px hairline。
- **今日待办卡**（card）：
  - kicker「今日待办」（`.card-kicker`，10pt 金色大写 `letter-spacing .1em`）
  - 大数字：队列总数，Cormorant 400 / 58pt / line-height .9，tnum；右侧「约 N 分钟」12pt `neutral-600`
  - 三格统计（生词 / 巩固 / 复习）：上边 1px hairline，格间 1px 竖线；数字 Cormorant 22pt tnum（生词那格为 `accent-700`），标签 11pt `neutral-600`
  - primary 按钮 block：「开始 · N 张」，`padding 13pt 0`，15pt
  - 队列为 0 时按钮文案变「没有可学的卡 —— 去词库启用一个包」，opacity .45，点击直接跳到等级词库
  - 入场动画：`rise`（opacity 0→1 + translateY 10px→0，300ms ease）
- **读到一半卡**（card，整卡可点进阅读器）：kicker「读到一半」+ 右侧百分比；书名 Noto Serif JP 22pt 500；作者 + 段号 12pt；右侧 secondary 小按钮「续读」；底部 hairline 进度线（金）。入场动画延迟 60ms。
- **词库进度**：kicker「词库」+ 右「已接触 X / Y · 未学 Z」（Y = 已启用词库包的词条总数，见「等级词库」）；hairline 进度线（`neutral-800`）。延迟 120ms。
- **连续天数**：「连续 6 天」+ 7 个 10×10 方块。已完成 = 1px 金描边 + `accent-200` 底；今天未完成 = 1px `divider` 空框。逐个 `dotIn`（opacity + scale .4→1，280ms），间隔 50ms。

### 2. 复习卡片

- 顶栏：左「收工」13pt `neutral-600`（退出）；中间 hairline 进度线（金，宽 = idx/total，300ms ease）；右「03 / 51」12pt tnum。
- 正面：`space-6` 顶部留白起，依次
  - 标签行：`tag-outline` 阶段（初见 / 巩固中 / 复习 · 第 N 次）+ `tag-accent` 等级（N5…N1）
  - 词条：Noto Serif JP 500 / 62pt / `letter-spacing .06em`
  - 读音位：**正面不可见**（opacity 0，占位保留避免翻面时跳版），翻面后 250ms 淡入。**不要用半透明泄露答案。**
  - 底部 primary block 按钮「显示答案」
- 背面追加（`rise` 280ms）：
  - 48pt 宽金色短横线
  - 释义 Cormorant 600 / 28pt + `tag-neutral` 词性 + `tag-accent` 分类
  - 例句块：**左侧 1px 金色竖线** + 左内边距 `space-4`；日文 20pt 行高 2.2 带振假名（ruby）；中文 14pt `neutral-700`
  - 底部一行 11pt `neutral-500`：`EF 2.50 · 第 0 次` 与 slug
- 评分区（背面才出现，顶边 hairline）：一行提示 11pt 大写「下次到期 / 共 N 张」；四个按钮 —— 忘了 / 困难 / 记得 / 简单，各自下方是**间隔预览**（`IntervalFormatter` 的输出，如 `1分` `6分` `10分` `4天`），11pt tnum `neutral-600`。「记得」flex 1.3 且底为 `accent-100`，其余 secondary flex 1。
- 评分推进动画：当前卡 opacity→0 且 translateY 0→14px（200ms），200ms 后换下一张再反向淡入。

### 3. 复习完成

- 背景一个巨大的金色淡数字（本轮张数）：Cormorant 400 / 170pt / `accent-200`，绝对定位 top 130，`fadeIn` 600ms；**从 0 逐格数上来**（40ms/步）。
- 前景：kicker「这一轮毕」→ 标题「N 张，收工」Cormorant 34pt → 说明 13pt 行高 1.9。
- 四格统计（记得 / 困难 / 忘了 / 简单）：上下 hairline，格间竖线，忘了那格 `accent-700`。
- 两个按钮：secondary「回首页」+ primary「去读羅生門」。
- 三段依次 `rise`，延迟 0 / 80 / 140ms。

### 4. 书架

- 顶栏：「书架」Cormorant 26pt + 右上 primary 小按钮「导入」。
- 正在读的书用一张 card 突出：kicker「正在读」、书名 Noto Serif JP 25pt、作者 13pt、右侧大百分比 Cormorant 28pt tnum `accent-700`、hairline 进度线、底部一行元信息（字数 / 原文注音 / 编码 / 段号）11pt tnum。
- 其余书：纯 hairline 列表行，无卡片。每行上边 1px `divider`；书名 Noto Serif JP 17–18pt 500；第二行 11pt tnum「作者 · 字数 · 原文注音」；右侧状态（`未读` / `12%` / `读完`）12pt。
- 数据来自 `BookEntity`：`title` / `author` / `charCount` / `hasEmbeddedRuby` / `encodingName` / `progress` / `paragraphIndex`。
- 空状态：118×154 的 1px 描边矩形 + 135° 斜纹（`neutral-200` / `bg` 各 6px）当书影；标题「架子还空着」Cormorant 26pt；说明 13pt 行高 2（导入 .txt 或带文字层的 PDF；编码认得 UTF-8 / Shift_JIS / EUC-JP；青空文庫原文注音自动识别）；灰注「扫描件不行 —— 本 App 不做 OCR」；primary 按钮「导入文件」。
- 错误态：一张 card，边框换成 `accent`（不是红色 —— 这套系统里没有语义红），文案两行：第一行说清哪个文件、什么问题；第二行 `neutral-600` 给出路。对应 `BookImportError` 的三种 case（`undecodable` / `emptyDocument` / `scannedPDF`）。

### 5. 阅读器

- 顶栏：左「← 书架」；中间 `.seg` 段控「横 / 縦」（选中项 `inset 0 0 0 1px accent` + 金字）；右「ふり ON/OFF」金色（振假名开关）。
- 正文：Noto Serif JP 19pt，行高 2.2，`letter-spacing .03em`，`text-align: justify`，段间距 `space-4`，段首全角空格。
- 振假名：ruby，rt 字号 .5em，opacity .7；关闭时 rt opacity→0（300ms 过渡），**用透明度而不是 display:none**，行高不跳。
- 竖排：`writing-mode: vertical-rl`，容器固定高（约 560–620pt）+ `overflow: hidden`，内容右起。**不要加 `text-orientation: upright`**（CJK 本来就是直立的，加上反而让 ruby 变慢）。SwiftUI 侧竖排需要自绘（`CTFrame` / `NSAttributedString` 的 `.verticalForms`，或逐字排布）—— 这是本次设计里工程量最大的一块，可以放到第二个迭代。
- 每个词是可点的：命中时下方 2pt 金色下划线（未选中为同宽透明边，避免布局跳动）。分词沿用现有 `ReaderText.words(annotated:)` + `TappableRubyText`。
- 底栏：`128 ——●—— 376`，1px hairline 上一个 7×7 金色方点表示位置。

### 6. 点词详情（底部弹层）

- 遮罩：`neutral-900` 34% 透明，180ms `fadeIn`；点遮罩关闭。
- 弹层：顶角 `radius-lg`，`shadow-lg`，`popIn`（translateY 26px→0 + opacity，260ms）。顶部一条 36×1 的 `neutral-400` 短线当把手。
- 头部：词形 Noto Serif JP 38pt 500（带 ruby）+ kicker「羅生門 · 第 128 段」；右侧 secondary 按钮「收藏 / 已收藏」（选中转金）。下边 hairline。
- **词形还原**（不依赖词库，任何词都给得出）：kicker「词形还原」；还原形 Noto Serif JP 26pt + `tag-outline` 词类（动词 · 一类 / 二类 / 三类、い形容词、な形容词 —— 文案取 `WordClass.labelZh`）；下面一行链式展示 `待って ← [て形] ← 待つ`；有歧义时再加一行 12pt `neutral-500`「其他可能：…」（`Deinflector` 返回的是候选列表，不要假装只有一个答案）。
- **释义**（依赖词库）：kicker「释义」+ 右上来源标 `JMdict` / `本地词库`；释义 15pt 行高 1.8；本地库没中文时退到 JMdict 英文，并在下面用 12pt `neutral-600` 说明「中文释义只覆盖 JLPT 核心词」。查不到就明说查不到，不要编。
- 底部两键：secondary「关掉」+ primary「加进今日卡组」（点后文案变「已加入今日卡组」）。

### 7. 设置

- 顶栏「设置」Cormorant 26pt。
- **每日额度**：kicker + 两组「标签 / 大数字（Cormorant 26pt tnum）」+ hairline 滑杆。滑杆 = 1px `divider` 轨 + 3pt 金色已填段 + 11×11 圆形把手（`bg` 底 + 1px 金描边）。新词 0–60 步长 5；复习 20–500 步长 20。变化 180ms ease。下方 12pt 说明：「新词上限决定每天引进多少生面孔；复习上限是断更之后的护栏，免得回来时被两百多张卡按住。」
- **阅读**：两个开关行（显示振假名 / 默认竖排），行间 hairline。开关 44×24 胶囊：开 = 1px 金描边 + `accent-100` 底 + 金色 18pt 圆钮右移 20pt；关 = `neutral-400` 描边与钮。200ms ease。
- **词库**：一行可点条目「等级词库 · N5–N1」，副行 11pt tnum「目标 N3 · 已启用 N5 · N4 · N3 · 6,000 词」，右侧金色 `›` → 进入等级词库屏。另一行「JMdict 词典 / 已安装 · 208,431 条」。
- 对应 `@AppStorage`：`SettingKey.newCardsPerDay`、`maxReviewsPerDay`、`showFurigana`，新增 `readerVertical`、`goalLevel`。

### 8. 等级词库（新增功能）

用户在这里选备考目标、导入 N5–N1 的词库包、启用/停用。

- 顶栏：「← 设置」/ 标题「等级词库」Cormorant 19pt / 右侧留白对齐。
- **备考目标**：kicker「备考目标」+ 一个撑满宽度的 `.seg` 段控，5 格 N5 N4 N3 N2 N1，选中格 `inset 0 0 0 1px accent` + 金字。下面 12pt 说明：「考 {目标} 要连下面的等级一起背，所以范围是 **含 N5 · N4 · N3**。超出范围的包不会进今天的队列。」
  - 逻辑直接用 `JLPTLevel.cumulativeScope`（已存在于 `JLPTCore/JLPTLevel.swift`）。
- **词库包列表**（5 行，行间 hairline）：
  - 左：等级 Cormorant 22pt tnum + 名称 13pt（基础 / 初级 / 中级 / 中高级 / 高级）+ 词条数 11pt tnum
  - 右：secondary 小按钮 —— 未导入「导入」（金字）/ 已导入「启用」或「停用」（`neutral-600`）
  - 中：hairline 进度线。已启用为金色，已导入未启用为 `neutral-400`，导入中为金色且随进度增长（linear 200ms）
  - 底：左「已启用 / 已导入 · 未启用 / 未导入 / 导入中 · 42%」（启用态为 `accent-700`），右「在备考范围内 / 超出当前目标」
  - 超出范围的行整行 opacity .45（200ms 过渡）
  - 参考词条量：N5 800 / N4 1,500 / N3 3,700 / N2 6,000 / N1 10,000（换成真包的实际数）
- **导入结果**：导入完成后浮出一张 card（边框金色，`rise` 300ms）：「N4 词库导入完成 · 新增 1,500 · 更新 0 · 跳过 0」，第二行 11pt `neutral-600`：「导入只写内容表，不动已有进度；同一个包再导一次是空操作。」
  - 这三个数字直接来自 `ImportReport`（`inserted` / `updated` / `skipped`），`ContentImporter` 已按指纹判重，重复导入返回 `skipped = true`。
- 底部 11pt `neutral-500`：「已启用 N 个包，共 X 词。停用某个包只是把它从队列里摘掉，进度会留着。」

## Interactions & Behavior

| 交互 | 行为 | 时长 / 曲线 |
| --- | --- | --- |
| 切 Tab | 金线滑动 + 内容淡出淡入 | 线 260ms ease；内容 150ms out / 180ms in |
| 显示答案 | 答案区 `rise`（opacity + translateY 10px）；读音淡入 | 280ms ease / 读音 250ms |
| 评分 | 当前卡淡出上移 → 200ms 后下一张淡入；顶部进度线增长 | 200ms ease；进度线 300ms |
| 一轮结束 | 进完成页，大数字从 0 计数 | 40ms/步 |
| 点词 | 遮罩淡入 + 弹层从下浮起 | 180ms / 260ms ease |
| 振假名开关 | 所有 rt 同时淡出/淡入（复习卡与阅读器一致） | 300ms ease |
| 横/縦 切换 | 立即换 `writing-mode`，段控选中环随之移动 | 无位移动画，避免竖排重排闪烁 |
| 滑杆 | 点/拖轨道即改值，已填段与把手同步 | 180ms ease |
| 词库导入 | 进度线 0→100%，完成后浮出 ImportReport 卡 | 每步 60ms；报告卡 300ms |
| 队列为空 | 首页按钮降透明并改文案，点击跳转等级词库 | 200ms |

原则：**只用透明度和位移**，没有弹跳、没有缩放、没有色块滑入。全部 ≤ 320ms。SwiftUI 对应 `.animation(.easeOut(duration: 0.2), value:)` 与 `.transition(.opacity.combined(with: .move(edge: .bottom)))`。

## State Management

原型里的状态（`renderVals` 的输入），映射到 SwiftUI 时建议拆成 `HomeView` 本地 `@State` + 一个 `PackLibraryStore`：

| 状态 | 类型 | 触发 / 说明 |
| --- | --- | --- |
| `tab` | enum study / shelf / settings | 底栏 |
| `mode` | enum home / study / done / shelf / reader / settings / packs | 屏内路由 |
| `idx`, `revealed` | Int, Bool | 复习流；`revealed` 每张卡重置 |
| `ratings` | [Rating: Int] | 本轮四键计数，喂完成页 |
| `newLimit`, `reviewLimit` | Int | `@AppStorage`；改动后要重算队列 |
| `furigana`, `vertical` | Bool | `@AppStorage`；跨屏共享 |
| `goal` | JLPTLevel | `@AppStorage`；决定 `cumulativeScope` |
| `packs` | [PackState: level, imported, on, prog] | 持久化。建议在 SwiftData 里加 `VocabPackEntity`（或复用现有的导入记录表）存 `imported` / `enabled` |
| `importing`, `importPct`, `report` | 临时 | 导入任务的进度与 `ImportReport` |
| `sel` | ReaderWord? | 点词弹层 |

队列构建：`已启用且在 cumulativeScope 内的包 → 生词（截 newLimit）+ 巩固 + 复习（截 reviewLimit）`。现有 `ReviewSession.todayQueue(in:)` / `DailyQueueConfig` 已经做了后半段，需要新增的是**按启用包 + 等级范围过滤**这一层（`VocabEntity.level` 字段已存在）。

数据获取：导入走已有的 `ContentImporter.importVocabPack(...)`；它是幂等的（按内容指纹判重），可以每次启动都调。词库包文件建议随包（`App/Resources/vocab_n{1..5}.json`）或按需下载 —— 设计上两种都成立，导入中状态已经画好了。

## Assets

没有位图资源。空状态的书影是纯 CSS 斜纹（135°，`neutral-200` / `bg` 各 6px），SwiftUI 里用 `Canvas` 画斜线或 `LinearGradient` 重复即可。

图标：Classical 规定用 [Lucide](https://lucide.dev)。但这套设计里我**几乎没有用图标** —— 导航是文字，操作是文字按钮，方向用 `←` `›`。iOS 上如果要换成 SF Symbols，请只在返回箭头、加号、星标这三处使用，保持轻描边风格（`.thin` / `.light`），不要把文字按钮换成图标按钮。

字体需随包并在 `Info.plist` 注册：Cormorant Garamond（400/600）、Lora（400/600）、Noto Serif JP（400/500）。三者都在 Google Fonts（OFL 许可）。

## Files

设计文件见本目录的 `prototype/`、`static-screens/`、`explorations/`、`design-system/`（清单见上文「About the Design Files」）。

目标工程里对应要改/新增的文件：

| 现有文件 | 改动 |
| --- | --- |
| `App/Features/RootView.swift` | 两个 Tab → 三个（学习 / 书架 / 设置），换成自绘底栏 + 金线 |
| `App/Features/HomeView.swift` | 按「学习首页」重做；词库进度分母改为已启用包的词条总数 |
| `App/Features/StudyView.swift` | 卡片版式、阶段/等级标签、评分区、完成页；正面不再显示读音 |
| `App/Features/BookshelfView.swift` | 正在读的卡 + hairline 列表；空状态与错误态文案 |
| `App/Features/ReaderView.swift` | 版式；新增横/竖排段控与 `ふり` 开关入口 |
| `App/Features/WordDetailSheet.swift` | 弹层版式；词形还原做成链式展示 |
| `App/Features/SettingsView.swift` | 自绘滑杆与开关；新增「等级词库」入口 |
| `App/Shared/RubyText.swift` / `TappableRubyText.swift` | rt 透明度过渡；竖排支持（如做） |
| **新增** `App/Features/PackLibraryView.swift` | 等级词库屏 |
| **新增** `App/Shared/Theme.swift` | Classical token（Color / Font / spacing / radius） |
| `Core/Sources/JLPTContent/ReviewSession.swift` | 队列按启用包 + `cumulativeScope` 过滤 |
| `Core/Sources/JLPTContent/Models/ContentEntities.swift` | 词库包的 `imported` / `enabled` 状态 |

建议实现顺序：Theme → 底栏与首页 → 复习流 → 等级词库 → 书架/阅读器版式 → 竖排（最后，工程量最大）。
