#!/usr/bin/env swift
import AppKit

/// 输出 1024×1024 圆角方图到 Resources（供 iconutil / 打包使用）。
let outputPath = CommandLine.arguments.dropFirst().first
    ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/VoiceText-AppIcon.png").path

let px: CGFloat = 1024
let cornerRadius = px * 0.223

let image = NSImage(size: NSSize(width: px, height: px), flipped: true) { rect in
    NSGraphicsContext.saveGraphicsState()

    let squircle = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    squircle.addClip()

    let g = NSGradient(
        colors: [
            NSColor(calibratedRed: 0.21, green: 0.18, blue: 0.48, alpha: 1),
            NSColor(calibratedRed: 0.09, green: 0.13, blue: 0.28, alpha: 1),
        ],
        atLocations: [0, 1],
        colorSpace: NSColorSpace.deviceRGB
    )
    g?.draw(in: rect, angle: -38)

    let pad = px * 0.19
    let inner = rect.insetBy(dx: pad, dy: pad)
    let midY = inner.midY

    let waveWidth = inner.width * 0.52
    let amp = inner.height * 0.26
    let steps = 48
    let wavePath = NSBezierPath()
    wavePath.lineWidth = px * 0.028
    wavePath.lineCapStyle = .round
    wavePath.lineJoinStyle = .round
    NSColor.white.setStroke()
    for i in 0 ... steps {
        let t = CGFloat(i) / CGFloat(steps)
        let x = inner.minX + t * waveWidth
        let y = midY + sin(t * .pi * 2) * amp
        let p = NSPoint(x: x, y: y)
        if i == 0 { wavePath.move(to: p) } else { wavePath.line(to: p) }
    }
    wavePath.stroke()

    let x0 = inner.minX + inner.width * 0.58
    let x1 = inner.maxX - px * 0.06
    let lineW = px * 0.014
    let textPath = NSBezierPath()
    textPath.lineWidth = lineW
    textPath.lineCapStyle = .round
    NSColor(white: 1, alpha: 0.52).setStroke()
    for dy in [-inner.height * 0.1, inner.height * 0.1] as [CGFloat] {
        let y = midY + dy
        textPath.move(to: NSPoint(x: x0, y: y))
        textPath.line(to: NSPoint(x: x1, y: y))
    }
    textPath.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return true
}

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff) else {
    fputs("Failed to rasterize icon.\n", stderr)
    exit(1)
}
rep.size = NSSize(width: px, height: px)
guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG.\n", stderr)
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
    print("Wrote \(outputPath)")
} catch {
    fputs("Write error: \(error)\n", stderr)
    exit(1)
}
