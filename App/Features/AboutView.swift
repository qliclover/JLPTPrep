import SwiftUI

/// 「关于 · 许可」。
///
/// 这一屏不是装饰：随包的词典和字体都带署名要求，
/// **分发（含 TestFlight）时必须提供**，不给就是违反许可。
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Credit: Identifiable {
        let id = UUID()
        let name: String
        let license: String
        let detail: String
        let url: String?
    }

    private let credits: [Credit] = [
        Credit(
            name: "JMdict / EDICT",
            license: "CC BY-SA 4.0",
            detail: "日语词典数据，218,173 词条。版权归 Electronic Dictionary Research and Development Group（EDRDG）所有，按 CC BY-SA 4.0 使用。",
            url: "https://www.edrdg.org/jmdict/j_jmdict.html"
        ),
        Credit(
            name: "JLPT 词表",
            license: "MIT",
            detail: "N5–N1 分级词表来自 jamsinclair/open-anki-jlpt-decks。JLPT 官方自 2010 年起不再公布词表，这是社区依据真题整理的版本，不是官方数据。",
            url: "https://github.com/jamsinclair/open-anki-jlpt-decks"
        ),
        Credit(
            name: "青空文庫",
            license: "公有领域",
            detail: "随包的日文作品（芥川龍之介、太宰治、宮沢賢治、新美南吉）著作权已过保护期，取自青空文庫。",
            url: "https://www.aozora.gr.jp"
        ),
        Credit(
            name: "Cormorant Garamond",
            license: "SIL Open Font License 1.1",
            detail: "标题与数字字体。Copyright 2015 The Cormorant Project Authors。",
            url: "https://github.com/CatharsisFonts/Cormorant"
        ),
        Credit(
            name: "Lora",
            license: "SIL Open Font License 1.1",
            detail: "正文字体。Copyright 2011 The Lora Project Authors。",
            url: "https://github.com/cyrealtype/Lora-Cyrillic"
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s6) {
                    intro
                    ForEach(credits) { credit in
                        creditRow(credit)
                    }
                    footer
                }
                .padding(.horizontal, Theme.Space.screen)
                .padding(.vertical, Theme.Space.s4)
            }
        }
        .background(Theme.Palette.bg.ignoresSafeArea())
    }

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button("← 设置") { dismiss() }
                    .font(.classicalBody(13))
                    .foregroundStyle(Theme.Palette.neutral600)
                Spacer()
                Text("关于")
                    .font(.classicalHeading(19))
                    .foregroundStyle(Theme.Palette.text)
                Spacer()
                Text("← 设置")
                    .font(.classicalBody(13))
                    .opacity(0)
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, Theme.Space.s3)
            Hairline()
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            Kicker(text: "这个 App")
            Text("所有内容都在设备本地：没有账号，不联网，不采集任何数据。词库、词典、书和复习进度都只存在这台设备上。")
                .font(.classicalBody(13))
                .lineSpacing(5)
                .foregroundStyle(Theme.Palette.neutral700)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func creditRow(_ credit: Credit) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text(credit.name)
                    .font(.classicalBody(15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.text)
                Spacer()
                ClassicalTag(text: credit.license, style: .outline)
            }
            Text(credit.detail)
                .font(.classicalBody(12))
                .lineSpacing(4)
                .foregroundStyle(Theme.Palette.neutral600)
                .fixedSize(horizontal: false, vertical: true)
            if let url = credit.url, let link = URL(string: url) {
                Link(url, destination: link)
                    .font(.classicalBody(11))
                    .foregroundStyle(Theme.Palette.accent700)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .classicalCard()
    }

    private var footer: some View {
        Text("JMdict 采用 CC BY-SA 4.0，署名与相同方式共享条款随数据传递。若要公开分发本 App，请先确认对该条款的合规方式。")
            .font(.classicalBody(11))
            .lineSpacing(3)
            .foregroundStyle(Theme.Palette.neutral500)
            .fixedSize(horizontal: false, vertical: true)
    }
}
