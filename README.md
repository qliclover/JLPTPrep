<div align="center">

# 日本語

**背单词和读原文用同一套记忆系统 —— 读书时点开的生词，明天就出现在复习队列里。**

一个为 JLPT 备考做的 iOS 应用。SwiftUI · SwiftData · iOS 17+ · 全程离线

[![License: MIT](https://img.shields.io/badge/License-MIT-b68235.svg)](LICENSE)
![Platform](https://img.shields.io/badge/iOS-17%2B-201f1d.svg)
![Tests](https://img.shields.io/badge/tests-328%20passing-7d5411.svg)

</div>

---

## 它解决什么

背单词 App 和日语阅读器通常是两个东西。你在阅读器里查了「乾く」，
查完就忘；背单词 App 里那 15 张卡，和你正在读的书毫无关系。

这个 App 把两者接在一起：阅读器里点开的每个生词都能一键进复习队列，
用的是同一套 SM-2 调度器、同一份掌握进度。

## 功能

### 单词

- N5–N1 共 **8,029 词**，按等级分包，可以只启用备考范围内的
- SM-2 间隔重复，**同一个词答对三次才算过**，一次蒙对不作数
  （选择题有 25% 的瞎猜基线，只能靠重复把运气滤掉）
- 两种复习方式：翻卡自评，或从四个近似选项里选
- 选择题的干扰项按真题套路生成 —— **清浊、长短、促音**，都是最容易混的那几组
- 每个评分键上标着「按下去下次什么时候再见」：1 分、10 分、6 天

### 阅读

- 导入 **.txt 或带文字层的 PDF**；编码自动识别 UTF-8 / Shift_JIS / EUC-JP / ISO-2022-JP
- 青空文庫的 `《》` 注音会被解析；没有注音的用 `CFStringTokenizer` 自动生成
- **横排竖排都支持**。竖排实现了縦中横（两位以内的拉丁串直立成组）和禁则处理
  （`、` `。` `」` 不落列首，`「` `（` 不落列尾）
- 点任意一个词：读音、原形、**活用还原**、释义
  —— 「待って」会告诉你它是「待つ」的て形，不是让你自己猜
- 长按一句：翻译（Apple 端上翻译框架，不联网）
- 三处**朗读**：词详情、复习卡（仅翻面后）、整句

### 词典与复盘

- 内置 **JMdict**，218,173 词条，完全离线
- 中文释义覆盖 N5 和 N4 的核心词（1,382 条手工撰写），其余显示英文
- **错题本**：最近反复答错的词，按错的次数排，可以只刷这一批
- **每日提醒**：提前排好未来 7 天，通知里写具体数字而不是「该复习了」
- **备份**：导出可读的 JSON，恢复是合并不是覆盖

随包 8 篇青空文庫公版作品：芥川龍之介《羅生門》《蜘蛛の糸》《杜子春》、
太宰治《走れメロス》、宮沢賢治《注文の多い料理店》《セロ弾きのゴーシュ》、
新美南吉《ごん狐》《手袋を買いに》。

## 隐私

**不收集任何数据。** 没有账号，不发起任何网络请求，不含第三方分析、广告或跟踪 SDK。
全部内容只存在设备本地。删除 App 即删除全部数据。

## 工程结构

```
Core/                      SPM 包，三个 target，纯逻辑无 UI
  Sources/JLPTCore/        SM-2 调度器、队列构建、评分模型
  Sources/JLPTJapanese/    分词、注音、活用还原、青空标记、竖排排版
  Sources/JLPTContent/     SwiftData 实体、内容导入、词典、备份
  Tests/                   328 个测试
App/                       SwiftUI 界面
  Features/                各屏
  Shared/                  设计系统、朗读、提醒、注音渲染
Tools/                     构建期脚本（Python / Swift）
Docs/                      上架资料、截图
Site/                      支持页与隐私政策（jlpt-nihongo.vercel.app）
```

### 几个设计决定

**内容表和进度表分开。** `VocabEntity` 是内容，`ReviewItemEntity` 是你的学习状态，
两者只靠 slug 关联。这样重新导入内容包不会碰到任何 SRS 状态 —— 词表更新了，
你的进度还在。

**调度器藏在 `SchedulerProtocol` 后面。** 现在是 SM-2；将来换 FSRS 时，
`ReviewLogEntity` 里积累的完整评分历史就是训练数据。

**注音标记用 `{漢字|かんじ}` 而不是 Anki 的 `漢字[かんじ]`。**
后者在正文本来就含方括号时无法消歧。

**默认 actor 隔离设为 MainActor。** 但 `UIColor { traits in ... }` 这类会被
UIKit 从渲染线程调用的闭包必须显式 `nonisolated` —— 否则真机上一点就闪退，
而模拟器完全复现不出来。这个坑踩过一次，见 `App/Shared/Theme.swift` 的注释。

## 构建

需要 Xcode 26+ 与 iOS 17 SDK。

```bash
git clone https://github.com/qliclover/JLPTPrep.git
cd JLPTPrep
open JLPTPrep.xcodeproj
```

直接就能跑。**离线词典不在仓库里**（41 MB 的生成物），缺了它 App 照常运行，
只是「设置 › 词库」会显示 JMdict 未安装、词详情只有自有词库的释义。

### 重建离线词典

```bash
# 1. 下载 JMdict（约 60 MB XML）
curl -o /tmp/JMdict_e.gz http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz
gunzip /tmp/JMdict_e.gz

# 2. 编译成 SQLite
python3 Tools/build_jmdict.py /tmp/JMdict_e App/Resources/jmdict.sqlite
```

### 重建词库包

```bash
python3 Tools/build_jlpt_packs.py <csv目录> App/Resources/jmdict.sqlite App/Resources/
```

CSV 来自 [open-anki-jlpt-decks](https://github.com/jamsinclair/open-anki-jlpt-decks)。
生成的 `vocab_n*.json` 已在仓库里，通常不需要重跑。

### 测试

```bash
cd Core && swift test
```

## 已知不足

这些是现在就知道的问题，写出来是为了让你心里有数：

- **N3 以上只有英文释义**（6,647 词）。日中的开源词典不存在，中文是手工写的，
  目前只覆盖 N5 和 N4
- **JLPT 官方自 2010 年起不再公布词表**。App 里的分级来自社区根据真题反推的版本，
  与真题可能有出入
- **自动注音准确率约 78%**（在 56 句手工标注的样本上测得）。
  用的是系统的 `CFStringTokenizer` 而非 MeCab —— 后者要多带十几 MB 词典
- **活用还原覆盖率约 14%**（真实文本上测得）。分母里大部分是名词和助词，
  它们本来就没有活用
- **竖排里跨词的拉丁串会被拆开**（`N4` 显示成 `N` 和 `4`）
- **句子翻译需要 iOS 18**，首次使用要在系统设置里下载语言包
- **语法、听力、模拟考都还没做**。`GrammarEntity` 已定义但零引用

## 内容来源与许可

| 内容 | 来源 | 许可 |
| --- | --- | --- |
| 词典数据 | [JMdict / EDICT](https://www.edrdg.org/jmdict/j_jmdict.html)（EDRDG） | CC BY-SA 4.0 |
| JLPT 分级词表 | [open-anki-jlpt-decks](https://github.com/jamsinclair/open-anki-jlpt-decks) | MIT |
| 日文作品 | [青空文庫](https://www.aozora.gr.jp) | 著作权已过保护期 |
| Cormorant Garamond / Lora | Google Fonts | SIL OFL 1.1 |

**代码采用 [MIT](LICENSE)。** 随包的数据和字体不在此列 —— 它们是第三方作品，
各按上表的许可分发，MIT 不能也没有重新授权它们。

其中 **JMdict 是 CC BY-SA 4.0**，带「相同方式共享」条款：再分发这份数据
（无论是否修改）要承担它自己的义务。数据在本项目中未经修改地随包分发，
App 内「关于 · 许可」页和[支持页](https://jlpt-nihongo.vercel.app)都有完整署名。

简单说：只用代码的话，MIT 就够了；连数据一起用，还要遵守上表的许可。
完整的第三方声明见 [NOTICE.md](NOTICE.md)。

---

<div align="center">
支持与隐私政策 · <a href="https://jlpt-nihongo.vercel.app">jlpt-nihongo.vercel.app</a>
</div>
