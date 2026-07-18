// Renders README screenshots offscreen with fake data (no real desktop involved).
// Built by scripts/make-screenshots.sh together with the app sources.
import AppKit
import SwiftUI

MainActor.assumeIsolated {
    _ = NSApplication.shared
    let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs"
    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    L10n.shared.lang = "en"

    // Композиция вью на градиентном «обое», чтобы была видна полупрозрачность
    @MainActor func render<V: View>(_ view: V, out: String) {
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()

        let scale: CGFloat = 2
        let panelRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        panelRep.size = size
        host.cacheDisplay(in: host.bounds, to: panelRep)
        let panelImage = NSImage(size: size)
        panelImage.addRepresentation(panelRep)

        let pad: CGFloat = 22
        let bgSize = NSSize(width: size.width + pad * 2, height: size.height + pad * 2)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bgSize.width * scale), pixelsHigh: Int(bgSize.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = bgSize

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGradient(
            starting: NSColor(calibratedRed: 0.30, green: 0.24, blue: 0.62, alpha: 1),
            ending: NSColor(calibratedRed: 0.22, green: 0.48, blue: 0.68, alpha: 1)
        )!.draw(in: NSRect(origin: .zero, size: bgSize), angle: 35)
        panelImage.draw(in: NSRect(x: pad, y: pad, width: size.width, height: size.height))
        NSGraphicsContext.restoreGraphicsState()

        let png = rep.representation(using: .png, properties: [:])!
        try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(out)"))
        print("written: \(outDir)/\(out)")
    }

    @MainActor func renderPanel(
        number: Int, name: String?,
        compact: Bool = false, indexOnly: Bool = false,
        contrast: Bool = false, opacity: Double = 0.35,
        out: String
    ) {
        let monitor = SpaceMonitor()
        monitor.setScreenshotState(number: number, name: name)
        monitor.compact = compact
        monitor.indexOnly = indexOnly
        monitor.contrast = contrast
        monitor.opacity = opacity
        monitor.alignRight = false
        render(ContentView(monitor: monitor), out: out)
    }

    renderPanel(number: 4, name: "Mail", out: "screenshot-normal.png")
    renderPanel(number: 4, name: "Very long desktop name", compact: true, out: "screenshot-compact.png")
    renderPanel(number: 4, name: "Mail", contrast: true, opacity: 0.6, out: "screenshot-contrast.png")
    renderPanel(number: 4, name: nil, indexOnly: true, out: "screenshot-number-only.png")
}
