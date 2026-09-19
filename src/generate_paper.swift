import AppKit

func generatePaperImage(outputPath: String, isDark: Bool = false, width: Int = 3840, height: Int = 2400) {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        fatalError("Failed to create graphics context")
    }

    if isDark {
        // Muted e-ink dark slate: #1A1A1A (RGB 26, 26, 26)
        context.setFillColor(red: 26.0 / 255.0, green: 26.0 / 255.0, blue: 26.0 / 255.0, alpha: 1.0)
    } else {
        // Warm, muted e-ink paper tone: #EBEBE6 (RGB 235, 235, 230)
        context.setFillColor(red: 235.0 / 255.0, green: 235.0 / 255.0, blue: 230.0 / 255.0, alpha: 1.0)
    }
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    guard let image = context.makeImage() else {
        fatalError("Failed to create image")
    }

    let rep = NSBitmapImageRep(cgImage: image)
    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to create PNG data")
    }

    let url = URL(fileURLWithPath: outputPath)
    try! pngData.write(to: url)
    print("Generated \(isDark ? "Dark E-Ink slate" : "Light E-Ink paper") wallpaper at: \(outputPath)")
}

if CommandLine.arguments.count > 1 {
    let target = CommandLine.arguments[1]
    let isDark = CommandLine.arguments.count > 2 && CommandLine.arguments[2].lowercased() == "dark"
    generatePaperImage(outputPath: target, isDark: isDark)
} else {
    generatePaperImage(outputPath: "assets/eink_paper.png", isDark: false)
    generatePaperImage(outputPath: "assets/eink_dark_paper.png", isDark: true)
}
