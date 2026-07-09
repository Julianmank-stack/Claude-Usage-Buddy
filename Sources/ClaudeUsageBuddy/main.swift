import AppKit
import WebKit

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

// MARK: - Built-in claude.ai fetcher
//
// A hidden WKWebView logged into claude.ai. Because it's a real browser engine
// with its own persistent cookies, requests made from inside the page are
// authenticated and pass Cloudflare — no external browser, no stored key.
// You log in once via the "Log in to claude.ai…" menu item (which shows this
// same web view in a window); after that the app refreshes on its own.
final class ClaudeWebFetcher: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var pageReady = false

    private(set) var lastFraction: Double?
    private(set) var lastSuccess: Date?
    private(set) var lastError: String?

    /// Which limit to track: "session" (5-hour), "weekly_all" (7-day), or
    /// "min" (whichever is closest to its cap).
    let which: String

    init(which: String) {
        self.which = which
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // persistent cookies -> login survives restarts
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 760), configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        super.init()
        webView.navigationDelegate = self
        loadHome()
    }

    /// The web view, so the app can show it in a login window. It keeps
    /// fetching whether or not it's on screen.
    var view: WKWebView { webView }

    func loadHome() {
        pageReady = false
        webView.load(URLRequest(url: URL(string: "https://claude.ai/")!))
    }

    var needsLogin: Bool {
        guard let e = lastError else { return false }
        return e.contains("HTTP 401") || e.contains("HTTP 403")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageReady = true
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        lastError = error.localizedDescription
    }

    // Same-origin fetches run inside the page: discover the org, read its
    // usage, and reduce it to a remaining fraction. `which` is injected as an
    // argument by callAsyncJavaScript.
    private static let js = """
    const g = async (u) => {
      const r = await fetch(u, { headers: { accept: 'application/json' } });
      if (!r.ok) { throw new Error('HTTP ' + r.status); }
      return r.json();
    };
    try {
      const orgs = await g('/api/organizations');
      const id = (Array.isArray(orgs) ? orgs[0] : orgs).uuid;
      const j = await g('/api/organizations/' + id + '/usage');
      const num = (v) => typeof v === 'number' && isFinite(v);
      const lims = Array.isArray(j.limits) ? j.limits : [];
      let used = null;
      if (which !== 'min') {
        const e = lims.find((l) => l.kind === which || l.group === which);
        if (e && num(e.percent)) { used = e.percent; }
      }
      if (used === null) {
        const ps = lims.filter((l) => num(l.percent)).map((l) => l.percent);
        if (ps.length) { used = Math.max(...ps); }
      }
      if (used === null) {
        const m = [j.five_hour, j.seven_day].filter((o) => o && num(o.utilization)).map((o) => o.utilization);
        if (m.length) { used = Math.max(...m); }
      }
      if (used === null) { return 'ERR:no-percent-in-response'; }
      let r = 1 - used / 100;
      r = Math.max(0, Math.min(1, r));
      return 'OK:' + r.toFixed(4);
    } catch (e) {
      return 'ERR:' + (e && e.message ? e.message : String(e));
    }
    """

    func refresh(completion: @escaping () -> Void) {
        guard pageReady else {
            if lastError == nil { lastError = "page still loading" }
            completion()
            return
        }
        webView.callAsyncJavaScript(Self.js, arguments: ["which": which], in: nil, in: .defaultClient) { [weak self] result in
            defer { completion() }
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.lastError = error.localizedDescription
            case .success(let value):
                guard let s = value as? String else {
                    self.lastError = "unexpected response type"
                    return
                }
                if s.hasPrefix("OK:"), let f = Double(s.dropFirst(3)) {
                    self.lastFraction = min(max(f, 0.0), 1.0)
                    self.lastSuccess = Date()
                    self.lastError = nil
                } else if s.hasPrefix("ERR:") {
                    self.lastError = String(s.dropFirst(4))
                } else {
                    self.lastError = "unexpected response"
                }
            }
        }
    }
}

// MARK: - Fallback sources
//
// The state file lets external scripts (or you, by hand) set the fraction:
//   ~/.claude-usage-buddy/state.json -> {"fraction": 0.42} or {"percent": 42}
// It's only used when the built-in claude.ai fetcher has no reading yet.
// Demo mode is a toggleable drain-and-refill for showing off the fade.
final class UsageProvider {
    static let stateURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".claude-usage-buddy")
            .appendingPathComponent("state.json")
    }()

    var demoEnabled = false
    private var demoStart = Date()

    func fileFraction() -> Double? {
        guard let data = try? Data(contentsOf: Self.stateURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let frac = obj["fraction"] as? Double {
            return clamp(frac)
        }
        if let pct = obj["percent"] as? Double {
            return clamp(pct / 100.0)
        }
        return nil
    }

    // Slow saw-tooth: drains over ~2 min, snaps back to full, repeats.
    func demoFraction() -> Double {
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
    private var fetcher: ClaudeWebFetcher!
    private var timer: Timer?
    private var loginWindow: NSWindow?
    private var lastFetchAttempt = Date.distantPast

    private let fetchInterval: TimeInterval = 10  // how often to ask claude.ai
    private let staleAfter: TimeInterval = 90     // live reading older than this shows as stale

    func applicationDidFinishLaunching(_ notification: Notification) {
        let which = ProcessInfo.processInfo.environment["CLAUDE_USAGE_LIMIT"] ?? "session"
        fetcher = ClaudeWebFetcher(which: which)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageOnly

        refreshUI()

        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        if Date().timeIntervalSince(lastFetchAttempt) >= fetchInterval {
            lastFetchAttempt = Date()
            fetcher.refresh { [weak self] in self?.refreshUI() }
        }
        refreshUI()
    }

    @objc private func forceRefresh() {
        lastFetchAttempt = .distantPast
        tick()
    }

    // What to show: demo (if toggled on) > live > stale live > state file > "log in".
    private func currentDisplay() -> (fraction: Double, source: String) {
        if provider.demoEnabled {
            return (provider.demoFraction(), "demo")
        }
        if let f = fetcher.lastFraction, let t = fetcher.lastSuccess {
            let age = Date().timeIntervalSince(t)
            if age <= staleAfter {
                return (f, "live (claude.ai, \(fetcher.which))")
            }
            return (f, "STALE — \(Int(age / 60)) min old")
        }
        if let f = provider.fileFraction() {
            return (f, "state.json")
        }
        if fetcher.needsLogin {
            return (1.0, "not logged in — use the menu")
        }
        return (1.0, "connecting to claude.ai…")
    }

    private func refreshUI() {
        let (fraction, source) = currentDisplay()
        statusItem.button?.image = Buddy.image(fraction: fraction)
        statusItem.button?.toolTip = "Claude usage remaining: \(percentString(fraction)) — \(source)"
        rebuildMenu(fraction: fraction, source: source)
    }

    private func rebuildMenu(fraction: Double, source: String) {
        let menu = NSMenu()

        let header = NSMenuItem(
            title: "Claude usage: \(percentString(fraction))",
            action: nil, keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)

        let sourceItem = NSMenuItem(title: "Source: \(source)", action: nil, keyEquivalent: "")
        sourceItem.isEnabled = false
        menu.addItem(sourceItem)

        menu.addItem(.separator())

        let login = NSMenuItem(
            title: fetcher.needsLogin ? "⚠️ Log in to claude.ai…" : "Log in to claude.ai…",
            action: #selector(showLogin), keyEquivalent: ""
        )
        login.target = self
        menu.addItem(login)

        let refreshItem = NSMenuItem(
            title: "Refresh now", action: #selector(forceRefresh), keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        let demoToggle = NSMenuItem(
            title: "Demo drain", action: #selector(toggleDemo), keyEquivalent: ""
        )
        demoToggle.target = self
        demoToggle.state = provider.demoEnabled ? .on : .off
        menu.addItem(demoToggle)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Claude Usage Buddy", action: #selector(quit), keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // Shows the fetcher's own web view in a window so you can log in. The
    // session lives in the web view's persistent cookie store, so once you're
    // in you can close the window and the buddy keeps fetching forever.
    @objc private func showLogin() {
        if loginWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered, defer: false
            )
            w.title = "Log in to claude.ai — Claude Usage Buddy"
            w.isReleasedWhenClosed = false
            w.center()
            loginWindow = w
        }
        loginWindow?.contentView = fetcher.view
        fetcher.loadHome()
        NSApp.activate(ignoringOtherApps: true)
        loginWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleDemo() {
        provider.demoEnabled.toggle()
        refreshUI()
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
