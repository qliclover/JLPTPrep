// 把日语教材扫描件 OCR 成结构化文本。
//
// 为什么要自己做而不是用现成的 OCR 结果：手上那份 .docx 是按中文配置跑的 OCR，
// 把假名整个丢掉了（全书只剩 133 个假名字符）。而 macOS Vision 支持日语，
// 实测读音、汉字、例句都能干净识别出来。
//
// 用法: ocrbook <pdf> <输出.jsonl> [起始页] [结束页]
import Foundation
import PDFKit
import Vision
import CoreGraphics

let args = CommandLine.arguments
guard args.count >= 3, let doc = PDFDocument(url: URL(fileURLWithPath: args[1])) else {
    FileHandle.standardError.write("用法: ocrbook <pdf> <输出.jsonl> [起始页] [结束页]\n".data(using: .utf8)!)
    exit(1)
}
let outputURL = URL(fileURLWithPath: args[2])
let first = args.count > 3 ? Int(args[3]) ?? 0 : 0
let last = args.count > 4 ? min(Int(args[4]) ?? doc.pageCount, doc.pageCount) : doc.pageCount

FileManager.default.createFile(atPath: outputURL.path, contents: nil)
let handle = try FileHandle(forWritingTo: outputURL)

/// 渲染一页成位图。2x 是实测下来质量和速度的平衡点。
func render(_ page: PDFPage, scale: CGFloat = 2.0) -> CGImage? {
    let bounds = page.bounds(for: .mediaBox)
    guard bounds.width > 1, bounds.height > 1 else { return nil }
    let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    guard let context = CGContext(
        data: nil, width: Int(size.width), height: Int(size.height),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(origin: .zero, size: size))
    context.scaleBy(x: scale, y: scale)
    page.draw(with: .mediaBox, to: context)
    return context.makeImage()
}

func ocr(_ image: CGImage) -> [(String, Float)] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    // 日语在前：这本书是日中对照，日语部分才是不能出错的那一半
    request.recognitionLanguages = ["ja-JP", "zh-Hans"]
    request.usesLanguageCorrection = true
    guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil else { return [] }
    return (request.results ?? []).compactMap {
        guard let best = $0.topCandidates(1).first else { return nil }
        return (best.string, best.confidence)
    }
}

let started = Date()
var done = 0

for index in first..<last {
    guard let page = doc.page(at: index), let image = render(page) else { continue }
    let lines = ocr(image)
    let payload: [String: Any] = [
        "page": index,
        "lines": lines.map { ["text": $0.0, "confidence": $0.1] },
    ]
    if let data = try? JSONSerialization.data(withJSONObject: payload) {
        handle.write(data)
        handle.write("\n".data(using: .utf8)!)
    }
    done += 1
    if done % 20 == 0 {
        let rate = Double(done) / Date().timeIntervalSince(started)
        let remaining = Double(last - first - done) / max(rate, 0.001)
        FileHandle.standardError.write(
            String(format: "  %d/%d 页  %.1f 页/秒  剩余约 %.0f 秒\n",
                   done, last - first, rate, remaining).data(using: .utf8)!
        )
    }
}

try? handle.close()
FileHandle.standardError.write(
    String(format: "完成 %d 页，耗时 %.0f 秒\n", done, Date().timeIntervalSince(started)).data(using: .utf8)!
)
