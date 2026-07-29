# App Store Connect 填写内容

照抄即可。所有描述都只写这个 App **实际有的**功能 —— 上架审核时夸大的功能会被要求演示，
而 TestFlight 阶段写实也省得以后改口。

---

## 一、New App 弹窗（建记录用）

| 字段 | 填 |
| --- | --- |
| Platforms | ☑︎ **iOS**（必须勾，不勾 Create 是灰的） |
| Name | `日本語` —— 若提示重名，换 `日本語ノート` 或 `JLPTPrep` |
| Primary Language | Chinese (Simplified) |
| Bundle ID | `JLPTPrep - com.qianli.JLPTPrep` |
| SKU | `jlptprep-001` |
| User Access | Full Access |

---

## 二、TestFlight → 测试信息

内部测试（自己和邀请的人）**不需要审核**，填这两项就能发。

**反馈电子邮件**

```
liqian_19990306@yahoo.com
```

**测试内容说明（What to Test）**

```
第一个可用版本。想请你重点看这几处：

1. 背单词 —— 设置里可以切「翻卡自评」和「选择题」两种方式。
   选择题的干扰项是按 JLPT 真题套路生成的（清浊、长短、促音），
   看看有没有出得不合理的题。

2. 读书 —— 书架里有 8 本青空文庫的公版小说。
   点任意一个词看词形还原和释义，长按一句可以翻译。
   注意振假名有没有标错的地方。

3. 竖排 —— 阅读器顶部可以切「横 / 縦」。
   竖排是逐字排的，留意标点位置和拉丁数字的方向。

4. 句子翻译需要 iOS 18，首次使用要在
   设置 › 通用 › 翻译 里下载日语和中文语言包。

已知不足：
· N3 以上的词只有英文释义，中文只覆盖 N5 和 N4
· 竖排里跨词的拉丁串会被拆开（N4 会显示成 N 和 4）
· 语法、听力、模拟考都还没做
```

---

## 三、App 信息（上架时才需要，TestFlight 内测可跳过）

**宣传文本 Promotional Text**（最多 170 字，改它不需要重新提交版本）

```
背单词和读原文用同一套记忆系统——读书时点开的生词，明天就出现在复习队列里。内置 21 万条离线词典和 8 篇青空文庫公版小说，全程不联网。
```

**副标题**（最多 30 字）

```
JLPT 备考 · 读原文 · 记生词
```

**类别**

- 主要：教育
- 次要：参考

**关键词**（最多 100 字符，逗号分隔，不要空格）

```
JLPT,日语,日本语,N5,N4,背单词,间隔重复,振假名,青空文库,日语阅读,离线词典,五十音
```

**描述**

```
为 JLPT 备考做的日语学习工具。背单词和读原文用的是同一套记忆系统——读书时遇到的生词，明天会出现在复习队列里。

【单词】
· N5–N1 共 8,029 词，按等级分包，可以只启用备考范围内的
· 间隔重复调度，同一个词答对三次才算过，一次蒙对不作数
· 两种复习方式：翻卡自评，或者从四个近似选项里选
· 选择题的干扰项按真题套路生成——清浊、长短、促音，都是最容易混的那几组
· 每个按钮标着「按下去下次什么时候再见」，1分、10分、6天，一目了然

【阅读】
· 导入 .txt 或带文字层的 PDF；编码认得 UTF-8 / Shift_JIS / EUC-JP
· 青空文庫的原文注音会自动识别；没有注音的会自动生成
· 横排竖排都支持，竖排的标点和拉丁数字按日文排版规矩处理
· 点任意一个词：读音、原形、活用变形、释义
  「待って」会告诉你它是「待つ」的て形，不是让你自己猜
· 长按一句：翻译（端上运行，不联网）
· 生词一键收进复习队列，读到什么背什么

【词典】
· 内置 JMdict，218,173 词条，完全离线
· 中文释义覆盖 N5 和 N4 的核心词，其余显示英文
· 读音全部经过词典交叉校验

【笔记】
· 划词或选句都能记，按书归档，点一条跳回原文那一段

随包 8 篇青空文庫的公版作品：芥川龍之介《羅生門》《蜘蛛の糸》《杜子春》、太宰治《走れメロス》、宮沢賢治《注文の多い料理店》《セロ弾きのゴーシュ》、新美南吉《ごん狐》《手袋を買いに》。

所有数据都在设备本地：没有账号，不联网，不采集任何信息，没有广告。

——

关于内容来源：词典数据来自 JMdict（CC BY-SA 4.0，EDRDG）；日文作品取自青空文庫，著作权已过保护期；JLPT 分级词表为社区整理版本（JLPT 官方自 2010 年起不再公布词表）。详见 App 内「设置 › 关于 · 许可」。
```

**版本 Version**

```
1.0
```

工程里的 `MARKETING_VERSION` 已改成 `1.0`，和这里一致 —— 两边对不上的话
App Store 的版本记录会找不到匹配的构建。

**版权 Copyright**（最多 200 字）

```
2026 Qian Li
```

格式是「年份 + 持有者」，不要自己写 © 符号，Apple 会加。

**营销网址 Marketing URL** —— **留空**。可选字段，没有产品宣传页就别填。

**支持网址 Support URL**

```
https://jlpt-nihongo.vercel.app
```

**隐私政策网址 Privacy Policy URL**

```
https://jlpt-nihongo.vercel.app/#privacy
```

同一个页面，锚点跳到隐私政策那一节。源文件在 `Site/index.html`，改完重新部署即可。

> ⚠️ 只能用 `jlpt-nihongo.vercel.app` 这个域名。Vercel 同时生成的团队作用域别名
> （`jlpt-nihongo-emotion-puzzle.vercel.app` 等）**带登录保护**，返回 302 跳 Vercel
> 登录页 —— 审核员打不开，会被打回。

---

## 四、App 隐私（App Privacy）

问卷选 **"不收集数据"（No, we do not collect data from this app）** —— 这是实话：
没有账号系统，没有网络请求，没有分析 SDK。

`PrivacyInfo.xcprivacy` 里已经声明了三类「需要理由的 API」：

| API | 理由 | 为什么用 |
| --- | --- | --- |
| UserDefaults | CA92.1 | `@AppStorage` 存每日额度、振假名开关等设备偏好 |
| 文件时间戳 | C617.1 | 导入书籍时读用户主动选择的文件 |
| 磁盘空间 | E174.1 | SwiftData / SQLite 内部查询 |

---

## 五、年龄分级

全部选「无」/「从不」。这个 App 没有暴力、成人内容、赌博、用户生成内容或社交功能。
结果应该是 **4+**。

---

## 六、出口合规

工程里已经声明了 `ITSAppUsesNonExemptEncryption = NO`，所以上传时**不会再问**。
这是实话：App 不含自研加密，也不发起网络请求。

---

## 七、上传凭证（二选一）

**A. App Store Connect API 密钥**（推荐，长期可用）

appstoreconnect.apple.com/access/integrations/api → Team Keys → +
· Access 选 **App Manager**
· 下载 `.p8`（**只能下一次**），记下 Key ID 和 Issuer ID
· 把 `.p8` 放到 `~/.appstoreconnect/private_keys/`

上传命令：

```
xcrun altool --upload-app -f /tmp/export/JLPTPrep.ipa -t ios \
  --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
```

**B. app 专用密码**（更快）

account.apple.com → 登录与安全 → App 专用密码 → 生成

```
xcrun altool --upload-app -f /tmp/export/JLPTPrep.ipa -t ios \
  -u liqian_19990306@yahoo.com -p <abcd-efgh-ijkl-mnop>
```
