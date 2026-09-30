import SwiftUI
import AppKit
import ScreenzCore
import ServiceManagement

@main
struct ScreenzApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Settings { Text("Screenz keeps your photos on your local network.").padding(30) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    var window: NSWindow!
    let model = AppModel()
    private var statusItem: NSStatusItem!
    private let optionsMenu = NSMenu()
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMenuBarItem()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 570),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Screenz"
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 720, height: 550)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: MainView(model: model))
        window.center()
        model.bringForward = { [weak self] in
            guard let self else { return }
            // Always bring the confirmation back to the primary screen after a rearrangement.
            if let screen = NSScreen.screens.first {
                let frame = screen.visibleFrame
                self.window.setFrameOrigin(CGPoint(x: frame.midX - self.window.frame.width / 2, y: frame.midY - self.window.frame.height / 2))
            }
            self.showWindow()
        }
        if CommandLine.arguments.contains("--demo") { model.demo(); showWindow() }
        else if CommandLine.arguments.contains("--show-window") { showWindow() }
    }

    private func installMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "display.2", accessibilityDescription: "Screenz")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = "Screenz · Click to open, right-click for options"
        statusItem.button?.setAccessibilityLabel("Screenz")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        let menu = optionsMenu
        menu.autoenablesItems = false
        menu.delegate = self
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Screenz", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func statusItemClicked() {
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp || event.modifierFlags.contains(.control),
           let button = statusItem.button {
            optionsMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
        } else { showWindow() }
    }

    func menuWillOpen(_ menu: NSMenu) {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        loginItem.title = SMAppService.mainApp.status == .requiresApproval ? "Allow Launch at Login…" : "Launch at Login"
    }

    @objc func showWindow() {
        model.hideMarkers()
        if model.phase == .markers { model.phase = .pairing }
        if model.phase == .idle || model.phase == .done { model.refresh() }
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func toggleLogin() {
        do {
            switch SMAppService.mainApp.status {
            case .enabled: try SMAppService.mainApp.unregister()
            case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
            default:
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            model.error = "Could not update Launch at Login: \(error.localizedDescription)"
            showWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.shutdown()
        return model.phase == .confirming ? .terminateCancel : .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if model.phase == .confirming { model.revert() }
        guard model.phase != .confirming else { return false }
        model.hideMarkers()
        if model.phase == .markers { model.phase = .pairing }
        sender.orderOut(nil)
        return false
    }
}

private let ink = Color.primary
private let accent = Color.accentColor

struct MainView: View {
    @ObservedObject var model: AppModel
    var reviewing: Bool { [.review, .confirming, .done].contains(model.phase) }
    private var title: String {
        switch model.phase {
        case .idle: return "Arrange your displays"
        case .pairing, .markers: return "Connect your iPhone"
        case .processing: return "Reading your photo"
        case .review: return "Check your arrangement"
        case .confirming: return "Keep this arrangement?"
        case .done: return "Displays arranged"
        }
    }
    private var subtitle: String {
        switch model.phase {
        case .idle: return "Take a photo of your screens to match your desk."
        case .pairing, .markers: return "Scan the code with your iPhone camera. Use the same Wi-Fi."
        case .processing: return "Finding the markers on your displays…"
        case .review: return "Drag to adjust. Your main display stays fixed."
        case .confirming: return "Reverting in \(model.remaining) seconds unless you keep it."
        case .done: return "Your arrangement is saved."
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 26, weight: .semibold)).tracking(-0.6)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if reviewing { review }
            else if model.phase == .idle { welcome }
            else if model.phase == .processing {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { pairing }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(32).padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.primary).background(Color(nsColor: .windowBackgroundColor))
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            if model.displays.isEmpty {
                Text("No displays detected").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ArrangementView(displays: .constant(model.displays), editable: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                Text("\(model.displays.count) displays connected").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button("Connect iPhone", action: model.start).buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
    }

    private var pairing: some View {
        VStack(alignment: .leading, spacing: 20) {
            GeometryReader { geometry in
                HStack(spacing: 32) {
                    if !model.url.isEmpty, let image = QR.image(model.url) {
                        Image(nsImage: image).interpolation(.none).resizable()
                            .frame(width: 176, height: 176).padding(20)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    } else { ProgressView().frame(width: 216, height: 216) }
                    VStack(alignment: .leading, spacing: 16) {
                        if model.connected {
                            Label("iPhone connected", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(.green)
                        }
                        Text("Open the link, show the screen markers, then take one photo of all your displays.")
                            .font(.system(size: 14)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if model.addresses.count > 1 {
                            Picker("Network", selection: $model.selectedAddress) {
                                ForEach(model.addresses, id: \.self) { Text($0).tag($0) }
                            }.font(.system(size: 12))
                        }
                        Button("Copy link") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(model.url, forType: .string)
                        }.buttonStyle(.plain).foregroundStyle(accent).disabled(model.url.isEmpty)
                    }.frame(width: max(0, geometry.size.width - 248), alignment: .leading)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 16) {
                Button("Back") { model.endSession(); model.phase = .idle; model.error = nil }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button("Import photo…", action: model.importPhoto).buttonStyle(.plain)
                Button("Show markers", action: model.showMarkers).buttonStyle(.borderedProminent).controlSize(.large)
            }.disabled(model.url.isEmpty)
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 16) {
            ArrangementView(displays: $model.proposal, editable: model.phase == .review)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            if let warning = model.validationError {
                Label(warning, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(.orange)
            }
            HStack(spacing: 16) {
                if model.phase == .confirming {
                    Button("Revert", action: model.revert).keyboardShortcut(.cancelAction)
                        .buttonStyle(.plain)
                    Spacer()
                    Button("Keep arrangement", action: model.keep).buttonStyle(.borderedProminent).controlSize(.large)
                } else if model.phase == .done {
                    Spacer()
                    Button("Done") { model.phase = .idle; model.proposal = []; model.refresh() }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                } else {
                    Button("Retake photo") {
                        if model.url.isEmpty { model.start() } else { model.showMarkers() }
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                    Spacer()
                    Text(model.isDemo ? "Demo" : "Auto-reverts after 20 seconds")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Button(model.isDemo ? "Connect iPhone" : "Apply arrangement", action: model.isDemo ? model.start : model.apply)
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(!model.isDemo && model.validationError != nil)
                }
            }
        }
    }
}

struct ArrangementView: View {
    @Binding var displays: [Display]
    let editable: Bool
    @State private var dragStart: Display?
    @State private var dragBounds: CGRect?
    var body: some View {
        GeometryReader { geometry in
            let union = dragBounds ?? displays.reduce(CGRect.null) { $0.union($1.rect) }
            let scale = min((geometry.size.width - 70) / max(union.width, 1), (geometry.size.height - 50) / max(union.height, 1))
            let ox = (geometry.size.width - union.width * scale) / 2
            let oy = (geometry.size.height - union.height * scale) / 2
            ZStack(alignment: .topLeading) {
                ForEach(Array(displays.enumerated()), id: \.element.id) { index, display in
                    VStack(spacing: 6) {
                        HStack {
                            Text(String(index + 1)).font(.system(size: 12, weight: .semibold, design: .monospaced))
                            Spacer()
                            if display.isMain { Image(systemName: "star.fill").font(.system(size: 9)) }
                        }
                        Spacer(minLength: 0)
                        Text(display.name).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                    }
                    .padding(10).frame(width: max(20, display.width * scale), height: max(20, display.height * scale))
                    .background(display.isMain ? accent.opacity(0.10) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(display.isMain ? accent.opacity(0.45) : ink.opacity(0.18), lineWidth: 1))
                    .offset(x: ox + (display.x - union.minX) * scale, y: oy + (display.y - union.minY) * scale)
                    .gesture(DragGesture().onChanged { value in
                        guard editable, !display.isMain else { return }
                        if dragStart == nil { dragStart = display; dragBounds = union }
                        guard var moved = dragStart, let i = displays.firstIndex(where: { $0.id == display.id }) else { return }
                        moved.x += value.translation.width / scale; moved.y += value.translation.height / scale
                        displays[i] = moved
                    }.onEnded { _ in
                        if let i = displays.firstIndex(where: { $0.id == dragStart?.id }) {
                            displays[i] = Layout.snap(displays[i], to: displays.filter { $0.id != displays[i].id }, threshold: 16 / scale)
                        }
                        dragStart = nil; dragBounds = nil
                    })
                    .accessibilityLabel("Display \(index + 1), \(display.name)\(display.isMain ? ", main display" : "")")
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
