import Foundation
import AppKit
import Darwin

// MARK: - UniversalAccess & Accessibility Dynamic Bindings

final class SystemInterface {
    private var uaHandle: UnsafeMutableRawPointer?
    private var axHandle: UnsafeMutableRawPointer?

    typealias BoolGetter = @convention(c) () -> Bool
    typealias BoolSetter = @convention(c) (UInt8) -> Void
    typealias IntGetter = @convention(c) () -> Int32
    typealias NotifyPost = @convention(c) (UnsafePointer<CChar>) -> UInt32

    private var fnGrayscaleGet: BoolGetter?
    private var fnGrayscaleSet: BoolSetter?
    private var fnContrastGet: BoolGetter?
    private var fnContrastSet: BoolSetter?
    private var fnTransparencyGet: BoolGetter?
    private var fnTransparencySet: BoolSetter?
    private var fnDiffColorGet: BoolGetter?
    private var fnDiffColorSet: BoolSetter?
    private var fnMotionGet: IntGetter?
    private var fnNotifyPost: NotifyPost?

    static let shared = SystemInterface()

    private init() {
        uaHandle = dlopen("/System/Library/PrivateFrameworks/UniversalAccess.framework/UniversalAccess", RTLD_NOW)
        axHandle = dlopen("/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities", RTLD_NOW)

        if let ua = uaHandle {
            if let sym = dlsym(ua, "UAGrayscaleIsEnabled") {
                fnGrayscaleGet = unsafeBitCast(sym, to: BoolGetter.self)
            }
            if let sym = dlsym(ua, "UAGrayscaleSetEnabled") {
                fnGrayscaleSet = unsafeBitCast(sym, to: BoolSetter.self)
            }
            if let sym = dlsym(ua, "UAIncreaseContrastIsEnabled") {
                fnContrastGet = unsafeBitCast(sym, to: BoolGetter.self)
            }
            if let sym = dlsym(ua, "UAIncreaseContrastSetEnabled") {
                fnContrastSet = unsafeBitCast(sym, to: BoolSetter.self)
            }
            if let sym = dlsym(ua, "UAReduceTransparencyIsEnabled") {
                fnTransparencyGet = unsafeBitCast(sym, to: BoolGetter.self)
            }
            if let sym = dlsym(ua, "UAReduceTransparencySetEnabled") {
                fnTransparencySet = unsafeBitCast(sym, to: BoolSetter.self)
            }
            if let sym = dlsym(ua, "UADifferentiateWithoutColorIsEnabled") {
                fnDiffColorGet = unsafeBitCast(sym, to: BoolGetter.self)
            }
            if let sym = dlsym(ua, "UADifferentiateWithoutColorSetEnabled") {
                fnDiffColorSet = unsafeBitCast(sym, to: BoolSetter.self)
            }
        }

        if let ax = axHandle {
            if let sym = dlsym(ax, "_AXSReduceMotionEnabled") {
                fnMotionGet = unsafeBitCast(sym, to: IntGetter.self)
            }
        }

        if let sym = dlsym(dlopen(nil, RTLD_NOW), "notify_post") {
            fnNotifyPost = unsafeBitCast(sym, to: NotifyPost.self)
        }
    }

    // Grayscale
    func getGrayscale() -> Bool {
        return fnGrayscaleGet?() ?? false
    }

    func setGrayscale(_ enabled: Bool) {
        fnGrayscaleSet?(enabled ? 1 : 0)
    }

    // Increase Contrast
    func getIncreaseContrast() -> Bool {
        return fnContrastGet?() ?? false
    }

    func setIncreaseContrast(_ enabled: Bool) {
        fnContrastSet?(enabled ? 1 : 0)
    }

    // Reduce Transparency
    func getReduceTransparency() -> Bool {
        return fnTransparencyGet?() ?? false
    }

    func setReduceTransparency(_ enabled: Bool) {
        fnTransparencySet?(enabled ? 1 : 0)
    }

    // Differentiate Without Color
    func getDifferentiateWithoutColor() -> Bool {
        return fnDiffColorGet?() ?? false
    }

    func setDifferentiateWithoutColor(_ enabled: Bool) {
        fnDiffColorSet?(enabled ? 1 : 0)
    }

    // Reduce Motion
    func getReduceMotion() -> Bool {
        if let val = fnMotionGet?() {
            return val != 0
        }
        let domain = "com.apple.Accessibility" as CFString
        let key = "ReduceMotionEnabled" as CFString
        guard let val = CFPreferencesCopyAppValue(key, domain) as? Bool else { return false }
        return val
    }

    func setReduceMotion(_ enabled: Bool) {
        let domain = "com.apple.Accessibility" as CFString
        let key = "ReduceMotionEnabled" as CFString
        CFPreferencesSetAppValue(key, enabled ? kCFBooleanTrue : kCFBooleanFalse, domain)
        CFPreferencesAppSynchronize(domain)
        _ = fnNotifyPost?("com.apple.accessibility.reduce.motion.status")
    }

    // AppleScript helper
    func runAppleScript(_ script: String) -> (output: String, error: String?) {
        var errorDict: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&errorDict)
            if let error = errorDict {
                let msg = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
                return ("", msg)
            }
            return (result.stringValue ?? "", nil)
        }
        return ("", "Failed to compile AppleScript")
    }

    // Dark Mode
    func getDarkMode() -> Bool {
        let script = "tell application \"System Events\" to tell appearance preferences to get dark mode"
        let (output, err) = runAppleScript(script)
        if err != nil {
            // Fallback: check defaults
            let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle")
            return style == "Dark"
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
    }

    func setDarkMode(_ dark: Bool) -> Bool {
        let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)"
        let (_, err) = runAppleScript(script)
        return err == nil
    }

    // Kept only to restore wallpapers recorded by older E-Ink Mode versions.
    func setDesktopPicture(_ path: String) -> Bool {
        let cleanPath = path.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"System Events\" to set picture of every desktop to \"\(cleanPath)\""
        let (_, err) = runAppleScript(script)
        return err == nil
    }
}

// MARK: - State Management

struct WallpaperSnapshot: Codable, Equatable {
    var displayID: UInt32
    var imageURL: URL
    var imageScaling: Int
    var allowClipping: Bool
    var fillColorArchive: Data
}

final class WallpaperManager {
    static let shared = WallpaperManager()

    private let workspace = NSWorkspace.shared

    private func screenID(_ screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "EinkWallpaper", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func screen(for displayID: UInt32) -> NSScreen? {
        NSScreen.screens.first { screenID($0) == displayID }
    }

    private func options(for snapshot: WallpaperSnapshot) throws -> [NSWorkspace.DesktopImageOptionKey: Any] {
        guard let color = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: NSColor.self,
            from: snapshot.fillColorArchive
        ) else {
            throw failure("Could not decode saved wallpaper fill color for display \(snapshot.displayID).")
        }
        return [
            .imageScaling: snapshot.imageScaling,
            .allowClipping: snapshot.allowClipping,
            .fillColor: color
        ]
    }

    func capture() throws -> [WallpaperSnapshot] {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { throw failure("No connected screens were reported.") }

        return try screens.map { screen in
            guard let displayID = screenID(screen),
                  let url = workspace.desktopImageURL(for: screen),
                  url.isFileURL,
                  FileManager.default.fileExists(atPath: url.path),
                  let options = workspace.desktopImageOptions(for: screen),
                  let scaling = options[.imageScaling] as? Int,
                  let clipping = options[.allowClipping] as? Bool,
                  let fillColor = options[.fillColor] as? NSColor else {
                throw failure("Could not capture a complete wallpaper and display options for a connected screen.")
            }
            let colorArchive = try NSKeyedArchiver.archivedData(
                withRootObject: fillColor,
                requiringSecureCoding: true
            )
            return WallpaperSnapshot(
                displayID: displayID,
                imageURL: url,
                imageScaling: scaling,
                allowClipping: clipping,
                fillColorArchive: colorArchive
            )
        }
    }

    func applyPaper(_ paperURL: URL, to snapshots: [WallpaperSnapshot]) throws {
        for snapshot in snapshots {
            guard let screen = screen(for: snapshot.displayID) else {
                throw failure("Display \(snapshot.displayID) is no longer connected.")
            }
            try workspace.setDesktopImageURL(paperURL, for: screen, options: try options(for: snapshot))
        }
    }

    func restore(_ snapshots: [WallpaperSnapshot]) throws {
        for snapshot in snapshots {
            guard let screen = screen(for: snapshot.displayID) else {
                throw failure("Display \(snapshot.displayID) is no longer connected; saved wallpaper remains in the ledger.")
            }
            try workspace.setDesktopImageURL(snapshot.imageURL, for: screen, options: try options(for: snapshot))
        }
        for snapshot in snapshots {
            let savedColor = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSColor.self,
                from: snapshot.fillColorArchive
            )
            var verified = false
            for attempt in 0..<20 {
                if let screen = screen(for: snapshot.displayID),
                   workspace.desktopImageURL(for: screen)?.standardizedFileURL == snapshot.imageURL.standardizedFileURL,
                   let current = workspace.desktopImageOptions(for: screen),
                   current[.imageScaling] as? Int == snapshot.imageScaling,
                   current[.allowClipping] as? Bool == snapshot.allowClipping,
                   let currentColor = current[.fillColor] as? NSColor,
                   let savedColor,
                   currentColor.isEqual(savedColor) {
                    verified = true
                    break
                }
                if attempt < 19 { Thread.sleep(forTimeInterval: 0.1) }
            }
            if !verified {
                throw failure("Wallpaper restoration could not be verified for display \(snapshot.displayID).")
            }
        }
    }
}

struct SettingsSnapshot: Codable, Equatable {
    var darkMode: Bool
    var grayscale: Bool
    var increaseContrast: Bool
    var reduceTransparency: Bool
    var differentiateWithoutColor: Bool
    var reduceMotion: Bool
    var desktopPicture: String?
}

struct EinkState: Codable, Equatable {
    var active: Bool
    var timestamp: String
    var baseline: SettingsSnapshot
    var paperImagePath: String?
    var wallpapers: [WallpaperSnapshot]?
    var currentMode: String?
}

final class StateManager {
    static let shared = StateManager()

    private let configDir: URL
    private let stateFile: URL

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        configDir = home.appendingPathComponent(".config/eink-mode", isDirectory: true)
        stateFile = configDir.appendingPathComponent("state.json")
    }

    func loadState() -> EinkState? {
        guard FileManager.default.fileExists(atPath: stateFile.path) else { return nil }
        guard let data = try? Data(contentsOf: stateFile) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(EinkState.self, from: data)
    }

    func saveState(_ state: EinkState) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(state) else { return false }

        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            try data.write(to: stateFile, options: .atomic)
            return loadState() == state
        } catch {
            return false
        }
    }

    func removeState() {
        try? FileManager.default.removeItem(at: stateFile)
    }

    var stateFilePath: String {
        return stateFile.path
    }

    var stateFileExists: Bool {
        FileManager.default.fileExists(atPath: stateFile.path)
    }
}

// MARK: - CLI Commands

final class EinkCLI {
    private let sys = SystemInterface.shared
    private let stateMgr = StateManager.shared
    private let wallpapers = WallpaperManager.shared

    private func ensurePaperImage(isDark: Bool) -> URL {
        let filename = isDark ? "eink_dark_paper.png" : "eink_paper.png"
        let home = FileManager.default.homeDirectoryForCurrentUser
        let localRepoURL = home.appendingPathComponent("eink-mode/assets/\(filename)")
        if FileManager.default.fileExists(atPath: localRepoURL.path) {
            return localRepoURL
        }

        if let exePath = Bundle.main.executableURL {
            let shareURL = exePath.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("share/eink/\(filename)")
            if FileManager.default.fileExists(atPath: shareURL.path) {
                return shareURL
            }
            let shareAssetsURL = exePath.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("share/eink/assets/\(filename)")
            if FileManager.default.fileExists(atPath: shareAssetsURL.path) {
                return shareAssetsURL
            }
        }

        let configDir = home.appendingPathComponent(".config/eink-mode", isDirectory: true)
        let configURL = configDir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: configURL.path) {
            return configURL
        }

        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        generatePaperAsset(outputPath: configURL.path, isDark: isDark)
        return configURL
    }

    private func generatePaperAsset(outputPath: String, isDark: Bool, width: Int = 3840, height: Int = 2400) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        if isDark {
            context.setFillColor(red: 26.0 / 255.0, green: 26.0 / 255.0, blue: 26.0 / 255.0, alpha: 1.0)
        } else {
            context.setFillColor(red: 235.0 / 255.0, green: 235.0 / 255.0, blue: 230.0 / 255.0, alpha: 1.0)
        }
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let pngData = rep.representation(using: .png, properties: [:]) else { return }
        try? pngData.write(to: URL(fileURLWithPath: outputPath))
    }

    private func paperURL(forDarkMode isDark: Bool = false) -> URL {
        return ensurePaperImage(isDark: isDark)
    }

    func run(args: [String]) {
        let command = args.count > 1 ? args[1] : "status"

        switch command {
        case "on":
            var isDark = false
            var explicit = false
            if args.count > 2 {
                let sub = args[2].lowercased()
                if sub == "dark" || sub == "--dark" {
                    isDark = true
                    explicit = true
                } else if sub == "light" || sub == "--light" {
                    isDark = false
                    explicit = true
                }
            } else if args.contains("--dark") {
                isDark = true
                explicit = true
            } else if args.contains("--light") {
                isDark = false
                explicit = true
            }
            handleOn(isDark: isDark, explicitMode: explicit)
        case "dark":
            switchAppearance(isDark: true)
        case "light":
            switchAppearance(isDark: false)
        case "off":
            let force = args.contains("--force")
            deactivate(force: force)
        case "status":
            showStatus()
        case "wallpaper-check":
            checkWallpaper()
        case "recover":
            let force = args.contains("--force")
            recover(force: force)
        case "help", "--help", "-h":
            showHelp()
        default:
            print("Unknown command: \(command)")
            showHelp()
            exit(1)
        }
    }

    private func captureCurrentSettings() -> SettingsSnapshot {
        return SettingsSnapshot(
            darkMode: sys.getDarkMode(),
            grayscale: sys.getGrayscale(),
            increaseContrast: sys.getIncreaseContrast(),
            reduceTransparency: sys.getReduceTransparency(),
            differentiateWithoutColor: sys.getDifferentiateWithoutColor(),
            reduceMotion: sys.getReduceMotion(),
            desktopPicture: nil
        )
    }

    private func handleOn(isDark: Bool, explicitMode: Bool) {
        let existing = stateMgr.loadState()
        if stateMgr.stateFileExists && existing == nil {
            print("Error: The state ledger exists but cannot be read. Refusing to replace its baseline.")
            exit(1)
        }
        if let existing, existing.active {
            if explicitMode {
                // User explicitly ran "eink on dark" or "eink on light" while already active!
                switchAppearance(isDark: isDark)
                return
            }
            let activeMode = (existing.currentMode ?? (sys.getDarkMode() ? "dark" : "light")).uppercased()
            print("Notice: E-Ink Mode is ALREADY active in \(activeMode) appearance (activated: \(existing.timestamp)).")
            print("Existing baseline settings are preserved and will not be overwritten.")
            print("\nTo switch appearance immediately while active:")
            print("  eink on dark   (or 'eink dark')")
            print("  eink on light  (or 'eink light')")
            print("\nRun 'eink off' to restore your original baseline, or 'eink status' to view details.")
            return
        }

        activate(isDark: isDark)
    }

    private func switchAppearance(isDark: Bool) {
        guard let state = stateMgr.loadState(), state.active else {
            print("E-Ink Mode is not currently active. Activating in \(isDark ? "DARK" : "LIGHT") appearance...")
            activate(isDark: isDark)
            return
        }

        let modeName = isDark ? "Dark" : "Light"
        print("=== Switching E-Ink Appearance to \(modeName.uppercased()) ===")

        print("Step 1/2: Setting system appearance to \(modeName)...")
        if !sys.setDarkMode(isDark) {
            print("  [Warning] System Events could not toggle appearance. Check Automation permissions if prompted.")
        }

        let paper = paperURL(forDarkMode: isDark)
        print("Step 2/2: Updating paper wallpaper (\(paper.lastPathComponent))...")
        if let wallpaperBaseline = state.wallpapers, FileManager.default.fileExists(atPath: paper.path) {
            do {
                try wallpapers.applyPaper(paper, to: wallpaperBaseline)
            } catch {
                print("  [Warning] Could not update wallpaper to \(paper.lastPathComponent): \(error.localizedDescription)")
            }
        }

        var updated = state
        updated.currentMode = isDark ? "dark" : "light"
        if stateMgr.saveState(updated) {
            print("\n Switched to \(modeName.uppercased()) appearance immediately.")
            print("Baseline settings remain preserved. Run 'eink off' to restore your original environment.")
        } else {
            print("\n Switched to \(modeName.uppercased()) appearance, but could not update state ledger.")
        }
    }

    private func activate(isDark: Bool = false) {
        let modeName = isDark ? "Dark" : "Light"
        print("=== Activating E-Ink Mode (\(modeName.uppercased())) ===")

        let existing = stateMgr.loadState()
        if stateMgr.stateFileExists && existing == nil {
            print("Error: The state ledger exists but cannot be read. Refusing to replace its baseline.")
            exit(1)
        }
        if let existing, existing.active {
            print("Notice: E-Ink Mode is ALREADY active (activated: \(existing.timestamp)).")
            print("Existing baseline settings are preserved and will not be overwritten.")
            print("Run 'eink off' to restore your original baseline, or 'eink status' to view details.")
            return
        }

        // 1. Snapshot baseline
        let baseline = captureCurrentSettings()
        var wallpaperBaseline: [WallpaperSnapshot]?
        let paper = paperURL(forDarkMode: isDark)
        if FileManager.default.fileExists(atPath: paper.path) {
            do {
                let captured = try wallpapers.capture()
                wallpaperBaseline = captured
                print("Wallpaper preflight: captured \(captured.count) connected screen(s).")
            } catch {
                print("  [Warning] Wallpaper will stay unchanged: \(error.localizedDescription)")
            }
        } else {
            print("  [Warning] Wallpaper will stay unchanged: paper image not found at \(paper.path).")
        }

        print("Step 1/6: Recorded baseline settings:")
        print("  - Dark Mode: \(baseline.darkMode)")
        print("  - Grayscale: \(baseline.grayscale)")
        print("  - Increase Contrast: \(baseline.increaseContrast)")
        print("  - Reduce Transparency: \(baseline.reduceTransparency)")
        print("  - Differentiate Without Color: \(baseline.differentiateWithoutColor)")
        print("  - Reduce Motion: \(baseline.reduceMotion)")

        // 2. Persist state BEFORE applying changes
        let isoFormatter = ISO8601DateFormatter()
        let nowStr = isoFormatter.string(from: Date())
        let state = EinkState(
            active: true,
            timestamp: nowStr,
            baseline: baseline,
            paperImagePath: nil,
            wallpapers: wallpaperBaseline,
            currentMode: isDark ? "dark" : "light"
        )

        guard stateMgr.saveState(state) else {
            print("Error: Failed to save baseline state to \(stateMgr.stateFilePath). Aborting activation for safety.")
            exit(1)
        }
        print("Step 2/6: Baseline saved and read back from \(stateMgr.stateFilePath)")

        // 3. Apply settings step-by-step
        print("Step 3/6: Switching to \(modeName) appearance...")
        if !sys.setDarkMode(isDark) {
            print("  [Warning] System Events could not toggle \(modeName) mode. Check Automation permissions if prompted.")
        }

        print("Step 4/6: Requesting display accessibility settings (Grayscale, Contrast, Transparency, Shapes)...")
        sys.setGrayscale(true)
        sys.setIncreaseContrast(true)
        sys.setReduceTransparency(true)
        sys.setDifferentiateWithoutColor(true)

        print("Step 5/6: Requesting Reduce Motion preference...")
        sys.setReduceMotion(true)

        print("Step 6/6: Requesting \(modeName.lowercased()) paper wallpaper for the captured current Space on each screen...")
        if let wallpaperBaseline {
            do {
                try wallpapers.applyPaper(paper, to: wallpaperBaseline)
            } catch {
                print("  [Warning] Paper wallpaper could not be applied to every screen: \(error.localizedDescription)")
                do {
                    try wallpapers.restore(wallpaperBaseline)
                    print("  Original wallpapers were restored after the partial failure.")
                } catch {
                    print("  [Warning] Wallpaper rollback was not verified: \(error.localizedDescription)")
                    print("  The active state ledger retains the baseline for 'eink off' or 'eink recover'.")
                }
            }
        } else {
            print("  Wallpaper unchanged because preflight did not capture every connected screen.")
        }

        print("\n E-Ink Mode (\(modeName.uppercased())) activation requested.")
        print("Run 'eink status' and inspect System Settings to confirm which settings applied.")
        print("To switch appearance at any time: eink on dark | eink on light (or 'eink dark' / 'eink light')")
        print("To restore your previous environment at any time, run: eink off")
    }

    private func deactivate(force: Bool) {
        print("=== Deactivating E-Ink Mode ===")

        guard let state = stateMgr.loadState(), state.active else {
            if force {
                print("Notice: No active E-Ink state recorded. Turning off controlled accessibility settings (--force)...")
                resetToSafeDefaults()
                return
            }
            print("Notice: E-Ink Mode is not currently marked active.")
            print("If your system appearance is stuck, run: eink recover --force")
            return
        }

        let baseline = state.baseline
        var restorationIssues: [String] = []
        print("Step 1/3: Restoring saved baseline appearance...")
        if !sys.setDarkMode(baseline.darkMode) {
            restorationIssues.append("System Events could not restore appearance")
        }

        print("Step 2/3: Requesting restoration of accessibility display settings...")
        sys.setGrayscale(baseline.grayscale)
        sys.setIncreaseContrast(baseline.increaseContrast)
        sys.setReduceTransparency(baseline.reduceTransparency)
        sys.setDifferentiateWithoutColor(baseline.differentiateWithoutColor)
        sys.setReduceMotion(baseline.reduceMotion)

        let reported = captureCurrentSettings()
        if reported.darkMode != baseline.darkMode { restorationIssues.append("appearance did not read back as saved") }
        if reported.grayscale != baseline.grayscale { restorationIssues.append("grayscale did not read back as saved") }
        if reported.increaseContrast != baseline.increaseContrast { restorationIssues.append("contrast did not read back as saved") }
        if reported.reduceTransparency != baseline.reduceTransparency { restorationIssues.append("transparency did not read back as saved") }
        if reported.differentiateWithoutColor != baseline.differentiateWithoutColor { restorationIssues.append("differentiate-without-color did not read back as saved") }
        if reported.reduceMotion != baseline.reduceMotion { restorationIssues.append("motion did not read back as saved") }

        if let wallpaperBaseline = state.wallpapers {
            print("Restoring wallpapers for \(wallpaperBaseline.count) captured screen(s)...")
            do {
                try wallpapers.restore(wallpaperBaseline)
            } catch {
                restorationIssues.append(error.localizedDescription)
            }
        } else if let picture = baseline.desktopPicture, !picture.isEmpty {
            print("Restoring wallpaper recorded by an older E-Ink Mode version...")
            if !sys.setDesktopPicture(picture) {
                restorationIssues.append("System Events could not restore the legacy wallpaper")
            }
        }

        if !restorationIssues.isEmpty {
            print("Restoration is incomplete; the active baseline was kept so 'eink recover' can retry:")
            restorationIssues.forEach { print("  - \($0)") }
            exit(1)
        }

        print("Step 3/3: Updating state ledger...")
        var updated = state
        updated.active = false
        guard stateMgr.saveState(updated) else {
            print("Error: Could not verify the updated ledger. Inspect 'eink status' before another activation.")
            exit(1)
        }

        print("\n E-Ink Mode is inactive; saved settings read back as restored for connected screens.")
        print("Other desktop Spaces and dynamic-wallpaper behavior are outside this check.")
    }

    private func resetToSafeDefaults() {
        print("Turning off controlled accessibility settings; this may overwrite personal accessibility choices:")
        sys.setGrayscale(false)
        sys.setIncreaseContrast(false)
        sys.setReduceTransparency(false)
        sys.setDifferentiateWithoutColor(false)
        sys.setReduceMotion(false)
        stateMgr.removeState()
        print("  - Grayscale: OFF")
        print("  - Increase Contrast: OFF")
        print("  - Reduce Transparency: OFF")
        print("  - Differentiate Without Color: OFF")
        print("  - Reduce Motion: OFF")
        print("  - State file removed.")
        print("\n Reset requested. Verify the settings in System Settings.")
    }

    private func recover(force: Bool) {
        print("=== E-Ink Mode Recovery ===")
        if let state = stateMgr.loadState(), state.active {
            print("Found active recorded baseline from \(state.timestamp). Restoring baseline...")
            deactivate(force: false)
        } else if force {
            resetToSafeDefaults()
        } else {
            print("No active state found. If the display is still grayscale/high-contrast:")
            print("  1. Use 'eink recover --force' only if you want to turn off your accessibility settings")
            print("  2. Or press Option + Command + F5 to open Accessibility Shortcuts and uncheck Color Filters.")
            print("  3. Or open System Settings > Accessibility > Display to adjust toggles manually.")
        }
    }

    private func pad(_ str: String, _ length: Int) -> String {
        return str.padding(toLength: length, withPad: " ", startingAt: 0)
    }

    private func checkWallpaper() {
        do {
            let captured = try wallpapers.capture()
            print("Wallpaper preflight ready for \(captured.count) connected screen(s) in their current Spaces.")
            for snapshot in captured {
                print("  Display \(snapshot.displayID): \(snapshot.imageURL.path)")
            }
            let lightPaper = paperURL(forDarkMode: false)
            let darkPaper = paperURL(forDarkMode: true)
            print("Paper images: Light (\(FileManager.default.fileExists(atPath: lightPaper.path) ? "available" : "missing")), Dark (\(FileManager.default.fileExists(atPath: darkPaper.path) ? "available" : "missing"))")
        } catch {
            print("Wallpaper preflight unavailable: \(error.localizedDescription)")
            exit(1)
        }
    }

    private func showStatus() {
        let current = captureCurrentSettings()
        let savedState = stateMgr.loadState()
        let isActive = savedState?.active ?? false

        print("""
        ======================================================================
        E-INK MODE STATUS
        ======================================================================
        Status:             \(isActive ? " ACTIVE" : " INACTIVE")
        State Ledger:       \(stateMgr.stateFilePath)
        """)

        if let saved = savedState, isActive {
            let activeMode = (saved.currentMode ?? (current.darkMode ? "dark" : "light")).uppercased()
            print("Mode:               \(activeMode) appearance")
            print("Activated At:       \(saved.timestamp)\n")
            if let wallpaperBaseline = saved.wallpapers {
                print("Wallpaper:          Saved for \(wallpaperBaseline.count) current-Space screen(s)\n")
            } else if saved.baseline.desktopPicture != nil {
                print("Wallpaper:          Legacy single-path snapshot\n")
            } else {
                print("Wallpaper:          Unchanged (preflight unavailable)\n")
            }
            print(pad("Setting", 28) + pad("Reported", 12) + pad("Baseline", 12) + pad("Mechanism", 20))
            print(String(repeating: "-", count: 72))
            print(pad("Appearance", 28) + pad(current.darkMode ? "Dark" : "Light", 12) + pad(saved.baseline.darkMode ? "Dark" : "Light", 12) + pad("AppleScript", 20))
            print(pad("Grayscale", 28) + pad(current.grayscale ? "ON" : "OFF", 12) + pad(saved.baseline.grayscale ? "ON" : "OFF", 12) + pad("Private framework", 20))
            print(pad("Increase Contrast", 28) + pad(current.increaseContrast ? "ON" : "OFF", 12) + pad(saved.baseline.increaseContrast ? "ON" : "OFF", 12) + pad("Private framework", 20))
            print(pad("Reduce Transparency", 28) + pad(current.reduceTransparency ? "ON" : "OFF", 12) + pad(saved.baseline.reduceTransparency ? "ON" : "OFF", 12) + pad("Private framework", 20))
            print(pad("Differentiate Without Color", 28) + pad(current.differentiateWithoutColor ? "ON" : "OFF", 12) + pad(saved.baseline.differentiateWithoutColor ? "ON" : "OFF", 12) + pad("Private framework", 20))
            print(pad("Reduce Motion", 28) + pad(current.reduceMotion ? "ON" : "OFF", 12) + pad(saved.baseline.reduceMotion ? "ON" : "OFF", 12) + pad("Preference write", 20))
        } else {
            print("\n" + pad("Setting", 28) + pad("Reported", 14) + pad("Mechanism", 20))
            print(String(repeating: "-", count: 62))
            print(pad("Appearance", 28) + pad(current.darkMode ? "Dark" : "Light", 14) + pad("AppleScript", 20))
            print(pad("Grayscale", 28) + pad(current.grayscale ? "ON" : "OFF", 14) + pad("Private framework", 20))
            print(pad("Increase Contrast", 28) + pad(current.increaseContrast ? "ON" : "OFF", 14) + pad("Private framework", 20))
            print(pad("Reduce Transparency", 28) + pad(current.reduceTransparency ? "ON" : "OFF", 14) + pad("Private framework", 20))
            print(pad("Differentiate Without Color", 28) + pad(current.differentiateWithoutColor ? "ON" : "OFF", 14) + pad("Private framework", 20))
            print(pad("Reduce Motion", 28) + pad(current.reduceMotion ? "ON" : "OFF", 14) + pad("Preference write", 20))
        }
        print("======================================================================")
    }

    private func showHelp() {
        print("""
        Usage: eink <command> [mode] [options]

        Commands:
          on [light|dark]  Snapshot current settings and activate E-Ink Mode (default: light).
                           If already active, immediately switches appearance mode.
          dark             Switch immediately to Dark E-Ink appearance (activates if inactive).
          light            Switch immediately to Light E-Ink appearance (activates if inactive).
          off              Attempt to restore baseline settings recorded on activation.
          status           Inspect current display settings and baseline status.
          wallpaper-check  Read-only check of current-Space wallpaper capture.
          recover          Retry baseline restoration, or reset accessibility settings.
          help             Show this help information.

        Options:
          --dark           Activate or switch to Dark appearance.
          --light          Activate or switch to Light appearance.
          --force          If no active ledger exists, turn off controlled accessibility
                           settings. This may overwrite your personal preferences.

        Emergency Shortcuts:
          Option + Command + F5   Open macOS Accessibility Shortcuts HUD instantly.
        """)
    }
}

// MARK: - Entry Point

let cli = EinkCLI()
cli.run(args: CommandLine.arguments)
