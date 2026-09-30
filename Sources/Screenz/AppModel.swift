import AppKit
import SwiftUI
import ScreenzCore

@MainActor
final class AppModel: ObservableObject {
    @Published var displays: [Display] = []
    @Published var proposal: [Display] = []
    @Published var url = ""
    @Published var addresses: [String] = []
    @Published var selectedAddress = "" { didSet { updateURL() } }
    @Published var status = "Your desk, in the right order."
    @Published var error: String?
    @Published var phase: Phase = .idle
    @Published var remaining = 0
    @Published var connected = false
    @Published var isDemo = false
    enum Phase { case idle, pairing, markers, processing, review, confirming, done }
    private var session = ""
    private var port: UInt16 = 0
    private var expires = Date.distantPast
    private var server: LocalServer?
    private var overlays: [NSWindow] = []
    private var previous: [Display] = []
    private var timer: Timer?
    private var expiryTimer: Timer?
    private var deadline: Date?
    var bringForward: (() -> Void)?

    init() { refresh() }
    func refresh() { displays = DisplaySystem.read() }

    var validationError: String? {
        do { try Layout.validate(proposal); return nil }
        catch { return error.localizedDescription }
    }

    func start() {
        guard phase != .confirming else { return }
        endSession()
        isDemo = false; error = nil; proposal = []; refresh()
        guard displays.count > 1 else { error = "Connect at least two displays to scan your desk."; return }
        do { try DisplaySystem.ensureSameDisplays(displays) } catch { self.error = error.localizedDescription; return }
        addresses = LocalServer.addresses()
        guard let address = addresses.first else { error = "Connect your Mac and iPhone to the same Wi-Fi or local network, then try again."; return }
        session = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        expires = Date().addingTimeInterval(900)
        let currentSession = session
        selectedAddress = address
        phase = .pairing; status = "Starting your private phone connection…"
        let server = LocalServer()
        self.server = server
        server.handler = { [weak self] request, reply in self?.handle(request, reply: reply) }
        server.start { [weak self] result in
            Task { @MainActor in
                guard let self, self.session == currentSession else { return }
                switch result {
                case .success(let port): self.port = port; self.updateURL(); self.status = "Scan the code with your iPhone camera."
                case .failure(let error): self.error = "Could not start the local connection: \(error.localizedDescription)"; self.endSession(); self.phase = .idle
                }
            }
        }
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.session == currentSession else { return }
                self.endSession()
                if self.phase == .pairing || self.phase == .markers || self.phase == .processing {
                    self.phase = .idle; self.status = "Connection expired. Start a new scan."
                }
            }
        }
    }

    private func updateURL() {
        url = port > 0 && !selectedAddress.isEmpty && !session.isEmpty ? "http://\(selectedAddress):\(port)/s/\(session)" : ""
    }

    func showMarkers() {
        guard !session.isEmpty, phase == .pairing || phase == .markers || phase == .review else { return }
        do { try DisplaySystem.ensureSameDisplays(displays) } catch { self.error = error.localizedDescription; return }
        hideMarkers(); error = nil; phase = .markers
        status = "Take one photo with every screen marker visible."
        for (index, d) in displays.enumerated() {
            guard let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == d.id }) else { continue }
            let window = MarkerWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.setFrame(screen.frame, display: true)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.contentView = MarkerView(display: d, index: index, session: session)
            window.onEscape = { [weak self] in self?.hideMarkers(); self?.phase = .pairing; self?.bringForward?() }
            window.makeKeyAndOrderFront(nil)
            overlays.append(window)
        }
    }

    func hideMarkers() { overlays.forEach { $0.close() }; overlays.removeAll() }

    func importPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard bytes <= HTTPRequest.maxBody else { throw AppError.message("Choose a photo under 24 MB.") }
                    self?.process(try Data(contentsOf: url))
                } catch { self?.error = error.localizedDescription }
            }
        }
    }

    private func process(_ data: Data) {
        guard phase == .markers || phase == .pairing || phase == .review, !session.isEmpty else { return }
        let token = session, snapshot = displays
        hideMarkers(); phase = .processing; error = nil; status = "Finding your displays…"; bringForward?()
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<[Display], Error> in
                Result { try Layout.infer(displays: snapshot, markers: PhotoDetector.detect(data, session: token, displays: snapshot)) }
            }.value
            guard session == token else { return }
            do {
                try DisplaySystem.ensureSameDisplays(snapshot)
                proposal = try result.get(); phase = .review
                status = "Found all \(proposal.count) displays. Check the arrangement."
            } catch {
                self.error = error.localizedDescription; phase = .pairing
                status = "Let’s try that photo again."
            }
        }
    }

    private func handle(_ request: HTTPRequest, reply: @escaping (LocalServer.Reply) -> Void) {
        let base = "/s/\(session)"
        guard !session.isEmpty, Date() < expires,
              request.path == base || request.path.hasPrefix(base + "/") else {
            reply(.json(404, ["error": "This connection has expired. Scan a new code on your Mac."])); return
        }
        // Bearer URL plus strict Host/Origin checking; no CORS or remote resources.
        let allowedHosts = addresses.map { "\($0):\(port)" }
        guard let host = request.headers["host"], allowedHosts.contains(host),
              request.headers["origin"] == nil || request.headers["origin"] == "http://\(host)" else {
            reply(.json(403, ["error": "Connection not allowed."])); return
        }
        if request.method == "GET", request.path == base || request.path == base + "/" {
            let packagedBundle = Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("Screenz_Screenz.bundle")) }
            guard let path = (packagedBundle ?? Bundle.module).url(forResource: "phone", withExtension: "html"), let html = try? Data(contentsOf: path) else {
                reply(.json(500, ["error": "Phone page is missing."])); return
            }
            connected = true
            reply(.init(status: 200, type: "text/html; charset=utf-8", body: html))
        } else if request.method == "GET", request.path == base + "/status" {
            reply(.json(["phase": String(describing: phase), "message": status, "error": error ?? "", "count": String(displays.count)]))
        } else if request.method == "POST", request.path == base + "/markers" {
            guard phase == .pairing || phase == .review || phase == .markers else { reply(.json(409, ["error": "Finish the current step on your Mac first."])); return }
            showMarkers()
            if let error { reply(.json(409, ["error": error])) } else { reply(.json(["message": "Markers are ready."])) }
        } else if request.method == "POST", request.path == base + "/upload" {
            guard phase == .markers || phase == .pairing || phase == .review else { reply(.json(409, ["error": "Finish the current step on your Mac first."])); return }
            guard !request.body.isEmpty, request.headers["content-type"]?.hasPrefix("image/") == true else {
                reply(.json(400, ["error": "Please select a photo."])); return
            }
            process(request.body)
            reply(.json(["message": "Photo received. Finding your displays…"]))
        } else { reply(.json(404, ["error": "Not found."])) }
    }

    func apply() {
        guard phase == .review, !isDemo else { return }
        do {
            try Layout.validate(proposal)
            try DisplaySystem.ensureSameDisplays(displays)
            previous = DisplaySystem.read()
            try DisplaySystem.apply(proposal)
            phase = .confirming; remaining = 20; error = nil
            deadline = Date().addingTimeInterval(20)
            status = "Does everything look right?"
            bringForward?()
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let deadline = self.deadline else { return }
                    self.remaining = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
                    if self.remaining == 0 { self.revert() }
                }
            }
        } catch { self.error = error.localizedDescription }
    }

    func keep() {
        guard phase == .confirming else { return }
        do {
            try DisplaySystem.apply(proposal, permanently: true)
            timer?.invalidate(); timer = nil; deadline = nil; previous = []
            phase = .done; status = "Your displays are in place."; refresh(); endSession()
        } catch { self.error = error.localizedDescription; revert() }
    }

    func revert() {
        guard !previous.isEmpty else { return }
        timer?.invalidate(); timer = nil; deadline = nil
        do {
            try DisplaySystem.apply(previous)
            previous = []; phase = .review; status = "Previous arrangement restored."; refresh()
        } catch {
            self.error = "Could not restore the previous arrangement: \(error.localizedDescription) Open System Settings → Displays to adjust it."
            phase = .confirming
        }
        bringForward?()
    }

    func shutdown() { if !previous.isEmpty { revert() }; endSession() }
    func endSession() {
        hideMarkers(); expiryTimer?.invalidate(); expiryTimer = nil
        server?.stop(); server = nil; session = ""; url = ""; port = 0; connected = false
    }

    func demo() {
        guard phase != .confirming else { return }
        endSession(); isDemo = true; error = nil
        proposal = [Display(id: 1, name: "Studio Display", width: 2560, height: 1440, x: 0, y: 0, isMain: true),
                    Display(id: 2, name: "MacBook Pro", width: 1512, height: 982, x: -1512, y: 458, isMain: false),
                    Display(id: 3, name: "Portrait Display", width: 1080, height: 1920, x: 2560, y: -480, isMain: false)]
        phase = .review; status = "A little desk inspiration. Drag a screen to try it."
    }
}
