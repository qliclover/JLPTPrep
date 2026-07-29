// 生成 App 图标。用工程自己的视觉语言：米白纸底、金色描边、明朝体的「語」。
//
// 不用位图素材是刻意的 —— Classical 这套设计里连空状态的书影都是画出来的，
// 图标也该由同一组 token 推导出来，改配色时重跑一次就行。
//
// 用法: makeicon <输出.png>
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png")

guard let context = CGContext(
    data: nil, width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { exit(1) }

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

// 纸底
context.setFillColor(color(0xF3F2F2))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))

// 内嵌的金色细框 —— 对应设计里到处都是的 hairline
let inset = CGFloat(size) * 0.11
context.setStrokeColor(color(0xB68235))
context.setLineWidth(CGFloat(size) * 0.008)
context.stroke(CGRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2))

// 「語」—— 明朝体，墨色
let glyphSize = CGFloat(size) * 0.52
let font = CTFontCreateWithName("HiraMinProN-W6" as CFString, glyphSize, nil)
// 命令行环境没有 AppKit/UIKit，用 CoreText 的属性键常量
let attributed = NSAttributedString(
    string: "語",
    attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(0x201F1D),
    ]
)
let line = CTLineCreateWithAttributedString(attributed)
let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
context.textPosition = CGPoint(
    x: (CGFloat(size) - bounds.width) / 2 - bounds.minX,
    y: (CGFloat(size) - bounds.height) / 2 - bounds.minY
)
CTLineDraw(line, context)

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
          output as CFURL, UTType.png.identifier as CFString, 1, nil
      )
else { exit(1) }
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print("写出 \(output.path)")
