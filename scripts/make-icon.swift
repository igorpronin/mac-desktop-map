// Рисует мастер-PNG иконки 1024×1024. Использование: swift make-icon.swift <out.png>
import AppKit

let size = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Сквиркл с полями по гайдлайнам macOS (иконка занимает ~82% холста)
let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: CGFloat(size) - 2 * inset, height: CGFloat(size) - 2 * inset)
let squircle = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.16, green: 0.09, blue: 0.36, alpha: 1),
    ending: NSColor(calibratedRed: 0.38, green: 0.24, blue: 0.72, alpha: 1)
)!
gradient.draw(in: squircle, angle: 90)

// Сетка 2×2 «десктопов»; один активный — белый, с номером.
let cell: CGFloat = 250
let gap: CGFloat = 44
let gridSize = cell * 2 + gap
let gx = (CGFloat(size) - gridSize) / 2
let gy = (CGFloat(size) - gridSize) / 2

for row in 0..<2 {
    for col in 0..<2 {
        let r = NSRect(
            x: gx + CGFloat(col) * (cell + gap),
            y: gy + CGFloat(row) * (cell + gap),
            width: cell, height: cell
        )
        let path = NSBezierPath(roundedRect: r, xRadius: 48, yRadius: 48)
        let active = row == 1 && col == 0  // верхний левый (координаты снизу вверх)
        if active {
            NSColor.white.setFill()
            path.fill()
            let num = "2" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 170, weight: .heavy),
                .foregroundColor: NSColor(calibratedRed: 0.30, green: 0.18, blue: 0.62, alpha: 1),
            ]
            let s = num.size(withAttributes: attrs)
            num.draw(
                at: NSPoint(x: r.midX - s.width / 2, y: r.midY - s.height / 2),
                withAttributes: attrs
            )
        } else {
            NSColor.white.withAlphaComponent(0.28).setFill()
            path.fill()
        }
    }
}

NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("written:", CommandLine.arguments[1])
