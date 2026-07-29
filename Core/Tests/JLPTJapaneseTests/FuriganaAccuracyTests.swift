import XCTest
@testable import JLPTJapanese
import JLPTCore
import JLPTContent

/// 拿手工标注的种子例句当标准答案，量一量系统分词器到底能做到什么程度。
///
/// 这个测试的产出不是「过 / 不过」，而是**一个可以拿去做决策的数字**：
/// 如果读音准确率不够，整个阅读器方向就得换 MeCab + IPAdic。
final class FuriganaAccuracyTests: XCTestCase {

    private struct Sample {
        let slug: String
        let ja: String
        let truth: String   // 手工标注
    }

    private func loadSamples() throws -> [Sample] {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "vocab_n5_sample", withExtension: "json", subdirectory: "Fixtures")
                ?? Bundle.module.url(forResource: "vocab_n5_sample", withExtension: "json")
        )
        let pack = try ContentPackSchema.decoder().decode(VocabPack.self, from: Data(contentsOf: url))
        return pack.vocab.flatMap { seed in
            (seed.examples ?? []).compactMap { example in
                guard let furigana = example.furigana else { return nil }
                return Sample(slug: seed.slug, ja: example.ja, truth: furigana)
            }
        }
    }

    // MARK: - 硬性保证：一个字都不能丢

    func testAnnotationNeverLosesOrAltersText() throws {
        for sample in try loadSamples() {
            let generated = RubyAnnotator.annotate(sample.ja)
            XCTAssertEqual(
                FuriganaParser.plainText(generated),
                sample.ja,
                "\(sample.slug)：去掉注音后必须还原成原文"
            )
        }
    }

    func testTokenizerOutputReassemblesIntoTheOriginal() throws {
        let tokenizer = JapaneseTokenizer()
        for sample in try loadSamples() {
            let rebuilt = tokenizer.tokenize(sample.ja).map(\.surface).joined()
            XCTAssertEqual(rebuilt, sample.ja, "\(sample.slug)：分词结果拼不回原文")
        }
        // 标点、空格、拉丁字母混排也不能丢
        for text in ["これはABCです。", "ねえ、ちょっと！", "  前後に空白  ", "100円です。"] {
            XCTAssertEqual(tokenizer.tokenize(text).map(\.surface).joined(), text)
        }
    }

    func testGeneratedAnnotationsAreWellFormed() throws {
        for sample in try loadSamples() {
            let generated = RubyAnnotator.annotate(sample.ja)
            // 解析器能吃下去，且注音里不能再出现汉字（那说明对齐错了）
            for segment in FuriganaParser.parse(generated) {
                if case .ruby(_, let reading) = segment {
                    XCTAssertFalse(
                        Kana.containsKanji(reading),
                        "\(sample.slug)：注音「\(reading)」里混进了汉字"
                    )
                }
            }
        }
    }

    // MARK: - 准确率测量

    private func measure(
        _ samples: [Sample],
        overrides: ReadingOverrides,
        label: String
    ) -> (exact: Double, reading: Double) {
        var exactMatches = 0
        var readingMatches = 0
        var mismatches: [(slug: String, expected: String, got: String)] = []

        for sample in samples {
            let generated = RubyAnnotator.annotate(sample.ja, overrides: overrides)

            if generated == sample.truth { exactMatches += 1 }

            // 真正要紧的指标：读音对不对。标注粒度不同不算错 ——
            // 手工标的 {毎朝|まいあさ} 和分词器给的 {毎|まい}{朝|あさ} 读出来一样。
            let expectedReading = FuriganaParser.readingText(sample.truth)
            let actualReading = FuriganaParser.readingText(generated)
            if expectedReading == actualReading {
                readingMatches += 1
            } else {
                mismatches.append((sample.slug, expectedReading, actualReading))
            }
        }

        let total = samples.count
        let exactRate = Double(exactMatches) / Double(total) * 100
        let readingRate = Double(readingMatches) / Double(total) * 100

        print("""

        ┌─ \(label)（样本 \(total) 句，标准答案为手工标注）
        │  标注完全一致  \(exactMatches)/\(total)  \(String(format: "%.1f", exactRate))%
        │  读音正确      \(readingMatches)/\(total)  \(String(format: "%.1f", readingRate))%
        └─ 读错的句子：\(mismatches.isEmpty ? "无" : "")
        """)
        for m in mismatches {
            print("   \(m.slug)\n     应读 \(m.expected)\n     实读 \(m.got)")
        }
        print("")
        return (exactRate, readingRate)
    }

    func testMeasureAccuracyAgainstHandAnnotatedGroundTruth() throws {
        let samples = try loadSamples()
        XCTAssertGreaterThan(samples.count, 40, "标准答案样本太少，测出来的数没意义")

        let bare = measure(samples, overrides: ReadingOverrides(), label: "只用系统分词器")
        let corrected = measure(samples, overrides: .common, label: "加读音覆盖表后（in-sample，偏乐观）")

        XCTAssertGreaterThanOrEqual(corrected.reading, bare.reading, "覆盖表不能让结果变差")

        // 回归底线：锁的是**不带覆盖表**的裸准确率，因为覆盖表是照着这批句子
        // 的错误挑的，用它当基线等于自己给自己判卷。
        XCTAssertGreaterThanOrEqual(bare.reading, 75.0, "系统分词器裸准确率退化了")
        XCTAssertGreaterThanOrEqual(bare.exact, 70.0)
    }
}
