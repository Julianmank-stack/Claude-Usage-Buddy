import AppKit

// MARK: - Buddy pixel art
//
// The "Claude buddy" from the screenshot: a chunky, rounded clay creature with
// two square eyes up top and four little stub legs at the bottom. 1 = filled
// (clay) pixel, 0 = empty/transparent; the two eyes are punched out as gaps so
// the dark menu bar shows through. The whole thing is drawn in Claude's
// clay/terracotta color and fades toward a faint ghost as usage drains.
enum Buddy {
    // 14 columns wide. Read top -> bottom. Modeled on the attached screenshot.
    static let pixels: [[Int]] = [
        [0,0,1,1,1,1,1,1,1,1,1,1,0,0], // rounded top
        [0,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [1,1,1,1,1,1,1,1,1,1,1,1,1,1],
        [1,1,1,1,1,1,1,1,1,1,1,1,1,1],
        [1,1,1,0,0,1,1,1,1,0,0,1,1,1], // eyes (holes)
        [1,1,1,0,0,1,1,1,1,0,0,1,1,1], // eyes (holes)
        [1,1,1,1,1,1,1,1,1,1,1,1,1,1],
        [1,1,1,1,1,1,1,1,1,1,1,1,1,1],
        [1,1,1,1,1,1,1,1,1,1,1,1,1,1],
        [1,1,1,1,1,1,1,1,1,1,1,1,1,1], // bottom of body
        [1,1,0,0,1,1,0,0,1,1,0,0,1,1], // legs
        [1,1,0,0,1,1,0,0,1,1,0,0,1,1], // legs
    ]

    static var cols: Int { pixels.first?.count ?? 0 }
    static var rows: Int { pixels.count }

    /// Claude clay color.
    static let clay = NSColor(calibratedRed: 0.757, green: 0.431, blue: 0.314, alpha: 1.0)

    /// Render the buddy as a status-bar image at the given remaining-usage
    /// fraction (1.0 = full, 0.0 = empty). Lower fraction => more faded /
    /// ghostly, so you can *see* the usage leaving.
    static func image(fraction: Double, height: CGFloat = 18) -> NSImage {
        let f = max(0.0, min(1.0, fraction))

        // Never fully invisible — keep a faint ghost so it stays clickable.
        let floorAlpha = 0.16
        let alpha = floorAlpha + (1.0 - floorAlpha) * f

        // As it drains, drift the color slightly toward a desaturated gray so
        // a low buddy reads as "tired", not just dim.
        let gray = NSColor(calibratedWhite: 0.6, alpha: 1.0)
        let color = clay.blended(withFraction: CGFloat(1.0 - f) * 0.45, of: gray) ?? clay

        // Draw at a high internal resolution (large cells), then scale the
        // finished image down to the menu-bar height. This keeps the pixel
        // edges crisp instead of squishing the art into a 1px-per-cell blob.
        let cell: CGFloat = 6
        let pxW = cell * CGFloat(cols)
        let pxH = cell * CGFloat(rows)

        let image = NSImage(size: NSSize(width: pxW, height: pxH))
        image.lockFocus()
        color.withAlphaComponent(CGFloat(alpha)).setFill()

        for (r, row) in pixels.enumerated() {
            for (c, value) in row.enumerated() where value == 1 {
                // Flip vertically: pixel art row 0 is the top.
                let x = CGFloat(c) * cell
                let y = CGFloat(rows - 1 - r) * cell
                NSBezierPath(rect: NSRect(x: x, y: y, width: cell, height: cell)).fill()
            }
        }

        image.unlockFocus()

        // Resize to the menu-bar height, preserving aspect ratio.
        image.size = NSSize(width: pxW * (height / pxH), height: height)
        image.isTemplate = false // keep the brand color, don't auto-tint
        return image
    }
}

// MARK: - Usage source
//
// The app shows whatever "remaining fraction" (0...1) it can find. Priority:
//   1. A state file at ~/.claude-usage-buddy/state.json -> {"fraction": 0.42}
//      (write this from anything: a cron job, ccusage, a shell script, etc.)
//   2. Demo mode: a slow drain-and-refill so the fade is visible out of the box.
struct UsageReading {
    let fraction: Double
    let isLive: Bool   // true = read from the state file, false = demo
}

final class UsageProvider {
    static let stateURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".claude-usage-buddy")
            .appendingPathComponent("state.json")
    }()

    var demoEnabled = true
    private var demoStart = Date()

    func read() -> UsageReading {
        if let live = readStateFile() {
            return UsageReading(fraction: live, isLive: true)
        }
        if demoEnabled {
            return UsageReading(fraction: demoFraction(), isLive: false)
        }
        return UsageReading(fraction: 1.0, isLive: false)
    }

    private func readStateFile() -> Double? {
        guard let data = try? Data(contentsOf: Self.stateURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // Accept either {"fraction": 0..1} or {"percent": 0..100}.
        if let frac = obj["fraction"] as? Double {
            return clamp(frac)
        }
        if let pct = obj["percent"] as? Double {
            return clamp(pct / 100.0)
        }
        return nil
    }

    // Slow saw-tooth: drains over ~2 min, snaps back to full, repeats.
    private func demoFraction() -> Double {
        let period = 120.0
        let t = Date().timeIntervalSince(demoStart).truncatingRemainder(dividingBy: period)
        return clamp(1.0 - t / period)
    }

    private func clamp(_ v: Double) -> Double { max(0.0, min(1.0, v)) }
}

// MARK: - App
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let provider = UsageProvider()
    private var timer: Timer?
    private var lastFraction: Double = 1.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageOnly

        refresh()

        // Update a few times a minute so the fade is smooth in demo mode and
        // promptly reflects the state file when it's live.
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    @objc private func refresh() {
        let reading = provider.read()
        lastFraction = reading.fraction
        statusItem.button?.image = Buddy.image(fraction: reading.fraction)
        statusItem.button?.toolTip = "Claude usage remaining: \(percentString(reading.fraction))"
        rebuildMenu(reading: reading)
    }

    private func rebuildMenu(reading: UsageReading) {
        let menu = NSMenu()

        let header = NSMenuItem(
            title: "Claude usage: \(percentString(reading.fraction))",
            action: nil, keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)

        let source = NSMenuItem(
            title: reading.isLive ? "Source: live (state.json)" : "Source: demo",
            action: nil, keyEquivalent: ""
        )
        source.isEnabled = false
        menu.addItem(source)

        menu.addItem(.separator())

        let demoToggle = NSMenuItem(
            title: "Demo drain", action: #selector(toggleDemo), keyEquivalent: ""
        )
        demoToggle.target = self
        demoToggle.state = provider.demoEnabled ? .on : .off
        menu.addItem(demoToggle)

        let refreshItem = NSMenuItem(
            title: "Refresh now", action: #selector(refresh), keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Claude Usage Buddy", action: #selector(quit), keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func toggleDemo() {
        provider.demoEnabled.toggle()
        refresh()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func percentString(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}

// Run as a menu-bar-only agent (no Dock icon, no main window).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
