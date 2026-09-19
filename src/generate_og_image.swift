import AppKit
import CoreGraphics
import CoreText

func createOGImage(outputPath: String) {
    let width: CGFloat = 1200
    let height: CGFloat = 630
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    guard let ctx = CGContext(
        data: nil,
        width: Int(width),
        height: Int(height),
        bitsPerComponent: 8,
        bytesPerRow: Int(width) * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        fatalError("Could not create graphics context")
    }

    // Colors
    let paperBg = CGColor(red: 238/255, green: 236/255, blue: 230/255, alpha: 1.0)      // #ECECE6
    let borderLine = CGColor(red: 205/255, green: 203/255, blue: 195/255, alpha: 1.0)   // #CDCBC3
    let inkPrimary = CGColor(red: 20/255, green: 20/255, blue: 20/255, alpha: 1.0)       // #141414
    let inkSecondary = CGColor(red: 90/255, green: 90/255, blue: 86/255, alpha: 1.0)    // #5A5A56
    let inkMuted = CGColor(red: 130/255, green: 130/255, blue: 125/255, alpha: 1.0)     // #82827D

    let darkCardBg = CGColor(red: 25/255, green: 25/255, blue: 25/255, alpha: 1.0)      // #191919
    let darkBorder = CGColor(red: 55/255, green: 55/255, blue: 55/255, alpha: 1.0)      // #373737
    let lightText = CGColor(red: 235/255, green: 235/255, blue: 230/255, alpha: 1.0)     // #EBEBE6
    let lightMuted = CGColor(red: 160/255, green: 160/255, blue: 155/255, alpha: 1.0)   // #A0A09B

    // Fill main paper background
    ctx.setFillColor(paperBg)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

    // Outer frame hairline
    ctx.setStrokeColor(borderLine)
    ctx.setLineWidth(1.0)
    ctx.stroke(CGRect(x: 32, y: 32, width: width - 64, height: height - 64))

    // Text Helper (CoreText renders bottom-up in flipped CG coordinates)
    func drawText(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        fontSize: CGFloat,
        weight: NSFont.Weight = .regular,
        color: CGColor,
        isMono: Bool = false
    ) {
        let font: NSFont
        if isMono {
            font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: weight)
        } else {
            font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)

        ctx.saveGState()
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    // Top Section
    // Category kicker
    drawText("MACOS DISPLAY UTILITY  •  100% REVERSIBLE", x: 64, y: 552, fontSize: 13, weight: .bold, color: inkMuted, isMono: true)

    // Main Title
    drawText("eink-mode", x: 64, y: 494, fontSize: 52, weight: .bold, color: inkPrimary)

    // Subtitle / value prop
    drawText("A calmer, text-first environment for your Mac laptop.", x: 64, y: 456, fontSize: 23, weight: .medium, color: inkSecondary)
    drawText("Approximates the focus of e-ink through Light appearance, grayscale, high UI contrast, and paper canvas.", x: 64, y: 426, fontSize: 16, weight: .regular, color: inkSecondary)

    // Lower Section: Two specimens (Light Card & Dark Card)

    // 1. Light Card (CLI Status Ledger)
    let leftCardRect = CGRect(x: 64, y: 88, width: 660, height: 300)
    ctx.setFillColor(CGColor(red: 245/255, green: 244/255, blue: 239/255, alpha: 1.0))
    ctx.fill(leftCardRect)
    ctx.setStrokeColor(borderLine)
    ctx.setLineWidth(1.0)
    ctx.stroke(leftCardRect)

    // Light card title bar
    let leftHeaderRect = CGRect(x: 64, y: 350, width: 660, height: 38)
    ctx.setFillColor(CGColor(red: 232/255, green: 230/255, blue: 224/255, alpha: 1.0))
    ctx.fill(leftHeaderRect)
    ctx.stroke(leftHeaderRect)

    drawText("Terminal — eink status", x: 84, y: 362, fontSize: 13, weight: .semibold, color: inkPrimary, isMono: true)
    drawText("● ● ●", x: 670, y: 362, fontSize: 10, weight: .bold, color: inkMuted, isMono: true)

    // Command invocation
    drawText("$ eink on", x: 84, y: 318, fontSize: 16, weight: .bold, color: inkPrimary, isMono: true)
    drawText("E-Ink Mode: ACTIVE (LIGHT)  •  Baseline saved to ~/.config/eink-mode/state.json", x: 84, y: 294, fontSize: 12, weight: .regular, color: inkMuted, isMono: true)

    // Divider
    ctx.setStrokeColor(borderLine)
    ctx.strokeLineSegments(between: [CGPoint(x: 84, y: 280), CGPoint(x: 704, y: 280)])

    // Table rows
    let rows: [(String, String, String)] = [
        ("Appearance", "Light (OFF)", "Reversible boolean"),
        ("Grayscale", "Active", "System-wide filter"),
        ("UI Contrast", "Enhanced", "High legibility"),
        ("Transparency", "Reduced", "Opaque paper surfaces"),
        ("Wallpaper", "Warm Paper", "Pre-test restored on exit")
    ]

    var rowY: CGFloat = 250
    for row in rows {
        drawText(row.0, x: 84, y: rowY, fontSize: 13, weight: .semibold, color: inkPrimary, isMono: true)
        drawText(row.1, x: 280, y: rowY, fontSize: 13, weight: .bold, color: inkPrimary, isMono: true)
        drawText(row.2, x: 440, y: rowY, fontSize: 12, weight: .regular, color: inkSecondary, isMono: true)
        rowY -= 30
    }

    // 2. Dark Card (Dark E-Ink Mode preview)
    let rightCardRect = CGRect(x: 748, y: 88, width: 388, height: 300)
    ctx.setFillColor(darkCardBg)
    ctx.fill(rightCardRect)
    ctx.setStrokeColor(darkBorder)
    ctx.setLineWidth(1.0)
    ctx.stroke(rightCardRect)

    // Dark card header
    let rightHeaderRect = CGRect(x: 748, y: 350, width: 388, height: 38)
    ctx.setFillColor(CGColor(red: 35/255, green: 35/255, blue: 35/255, alpha: 1.0))
    ctx.fill(rightHeaderRect)
    ctx.stroke(rightHeaderRect)

    drawText("Night Mode — eink dark", x: 768, y: 362, fontSize: 13, weight: .semibold, color: lightText, isMono: true)

    drawText("$ eink on dark", x: 768, y: 318, fontSize: 16, weight: .bold, color: lightText, isMono: true)
    drawText("Immediate appearance switch:", x: 768, y: 294, fontSize: 12, weight: .regular, color: lightMuted, isMono: true)

    drawText("• Dark appearance active", x: 768, y: 254, fontSize: 13, weight: .regular, color: lightText, isMono: false)
    drawText("• Charcoal slate canvas", x: 768, y: 224, fontSize: 13, weight: .regular, color: lightText, isMono: false)
    drawText("• Full grayscale & contrast", x: 768, y: 194, fontSize: 13, weight: .regular, color: lightText, isMono: false)
    drawText("• Baseline stays intact", x: 768, y: 164, fontSize: 13, weight: .regular, color: lightText, isMono: false)

    drawText("$ eink off  # restores baseline", x: 768, y: 116, fontSize: 13, weight: .bold, color: lightMuted, isMono: true)

    // Footer bar
    drawText("github.com/toshon-jennings/eink-mode", x: 64, y: 48, fontSize: 13, weight: .bold, color: inkPrimary, isMono: true)
    drawText("Zero dependencies  •  Standalone Swift CLI  •  macOS Sequoia+", x: 748, y: 48, fontSize: 12, weight: .regular, color: inkSecondary, isMono: true)

    // Export to PNG
    guard let image = ctx.makeImage() else {
        fatalError("Failed to create image from context")
    }

    let rep = NSBitmapImageRep(cgImage: image)
    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to create PNG data")
    }

    let url = URL(fileURLWithPath: outputPath)
    try! pngData.write(to: url)
    print("Generated OG Image at: \(outputPath)")
}

let target = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets/og_image.png"
createOGImage(outputPath: target)
