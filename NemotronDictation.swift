import AppKit
import AVFoundation
import Carbon
import OSLog
import ServiceManagement

private let hotKeySignature: OSType = 0x4E444943 // NDIC

private let diagnostics = Logger(subsystem: "io.github.huevi.nemotron-dictation", category: "Dictation")

private final class WaveformView: NSView {
    private var level: Double = 0
    private var phase: Double = 0
    private var processing = false
    private let shapes: [Double] = [0.22, 0.44, 0.68, 0.90, 0.68, 1, 0.78, 0.58, 0.34, 0.21, 0.13]

    func update(level: Double, processing: Bool = false) {
        self.processing = processing
        self.level += (level - self.level) * (level > self.level ? 0.49 : 0.24)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { phase += 0.38 }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let spacing = bounds.width / Double(shapes.count)
        let accent = processing ? NSColor.systemTeal : NSColor.systemPink
        for (index, weight) in shapes.enumerated() {
            let fluctuation = 0.75 + 0.25 * sin(phase + Double(index) * 0.83)
            let height = 3 + weight * (2 + 17 * level) * fluctuation
            let bar = NSRect(x: Double(index) * spacing + (spacing - 2.6) / 2,
                             y: (bounds.height - height) / 2, width: 2.6, height: height)
            accent.withAlphaComponent(0.40 + weight * 0.52).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 1.3, yRadius: 1.3).fill()
        }
    }
}

private final class OverlayButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(symbol: String, label: String, tint: NSColor) {
        super.init(frame: .zero)
        title = ""
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        imagePosition = .imageOnly
        isBordered = false
        contentTintColor = tint
        toolTip = label
        setAccessibilityLabel(label)
    }

    required init?(coder: NSCoder) { nil }
}

private final class CapsuleBackground: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let outline = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius = outline.height / 2
        let capsule = NSBezierPath(roundedRect: outline, xRadius: radius, yRadius: radius)
        NSColor(srgbRed: 0.075, green: 0.078, blue: 0.087, alpha: 0.97).setFill()
        capsule.fill()
        NSColor(white: 1, alpha: 0.21).setStroke()
        capsule.lineWidth = 1
        capsule.stroke()
    }
}

private final class RecordingIndicator: NSObject {
    private enum Mode {
        case recording, processing, finished

        var size: NSSize {
            switch self {
            case .recording: return NSSize(width: 248, height: 40)
            case .processing: return NSSize(width: 168, height: 36)
            case .finished: return NSSize(width: 186, height: 36)
            }
        }
    }

    private let panel: NSPanel
    private let dot = NSView()
    private let label = NSTextField(labelWithString: "")
    private let clock = NSTextField(labelWithString: "")
    private let waveform = WaveformView()
    private let separator = NSView()
    private let stopButton = OverlayButton(symbol: "stop.fill", label: "Stop and transcribe", tint: .white)
    private let discardButton = OverlayButton(symbol: "xmark", label: "Discard recording", tint: NSColor(white: 0.73, alpha: 1))
    private var timer: Timer?
    private var dismissTimer: Timer?
    var onStop: (() -> Void)?
    var onDiscard: (() -> Void)?

    override init() {
        let rect = NSRect(origin: .zero, size: Mode.recording.size)
        panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        super.init()
        panel.title = "Nemotron Dictation Indicator"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        // One alpha-masked silhouette keeps the panel corners clear on the desktop.
        let backdrop = CapsuleBackground(frame: rect)
        panel.contentView = backdrop

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3.5
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        clock.frame = NSRect(x: 98, y: 11, width: 47, height: 18)
        clock.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        clock.textColor = NSColor(white: 0.73, alpha: 1)
        separator.frame = NSRect(x: 184, y: 11, width: 1, height: 18)
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor(white: 1, alpha: 0.13).cgColor
        stopButton.frame = NSRect(x: 189, y: 6, width: 28, height: 28)
        discardButton.frame = NSRect(x: 217, y: 6, width: 28, height: 28)
        stopButton.target = self
        stopButton.action = #selector(stop)
        discardButton.target = self
        discardButton.action = #selector(discard)
        for view in [dot, label, clock, waveform, separator, stopButton, discardButton] {
            backdrop.addSubview(view)
        }
    }

    func record(_ recorder: AVAudioRecorder) {
        showRecording()
        recorder.isMeteringEnabled = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.065, repeats: true) { [weak self, weak recorder] _ in
            guard let self, let recorder else { return }
            recorder.updateMeters()
            self.waveform.update(level: max(0, min(1, Double(recorder.averagePower(forChannel: 0) + 54) / 42)))
            self.setTime(Int(recorder.currentTime))
        }
    }

    func showRecording() {
        resetTimers()
        setMode(.recording, title: "Recording", accent: .systemPink)
        setTime(0)
        waveform.update(level: 0)
        show()
    }

    func previewLevels() {
        waveform.update(level: 0.82)
        setTime(7)
    }

    private func setTime(_ seconds: Int) {
        clock.stringValue = String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    func processing() {
        resetTimers()
        setMode(.processing, title: "Transcribing…", accent: .systemTeal)
        waveform.update(level: 0.55, processing: true)
        show()
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            timer = Timer.scheduledTimer(withTimeInterval: 0.085, repeats: true) { [weak self] _ in
                self?.waveform.update(level: 0.55, processing: true)
            }
        }
    }

    func finish(_ message: String, success: Bool = true) {
        resetTimers()
        setMode(.finished, title: message, accent: success ? .systemGreen : .systemOrange)
        show()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 1.15, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    func hide() {
        resetTimers()
        panel.orderOut(nil)
    }

    private func resetTimers() {
        timer?.invalidate()
        timer = nil
        dismissTimer?.invalidate()
        dismissTimer = nil
    }

    private func setMode(_ mode: Mode, title: String, accent: NSColor) {
        let size = mode.size
        let recording = mode == .recording
        let frame = panel.frame
        let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.minY)
        dot.frame = NSRect(x: 13, y: (size.height - 7) / 2, width: 7, height: 7)
        dot.layer?.backgroundColor = accent.cgColor
        label.stringValue = title
        let waveformStart: CGFloat = recording ? 148 : 127
        let labelEnd = mode == .finished ? size.width - 13 : waveformStart - 4
        label.frame = NSRect(x: 27, y: (size.height - 18) / 2,
                             width: recording ? 70 : labelEnd - 27, height: 18)
        waveform.frame = NSRect(x: waveformStart, y: (size.height - 22) / 2, width: 33, height: 22)
        waveform.isHidden = mode == .finished
        for view in [clock, separator, stopButton, discardButton] { view.isHidden = !recording }
        panel.ignoresMouseEvents = !recording
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    private func show() {
        if !panel.isVisible, let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 45))
        }
        panel.orderFrontRegardless()
        panel.invalidateShadow()
    }

    @objc private func stop() { onStop?() }
    @objc private func discard() { onDiscard?() }
}

private final class SpeechMenuHeader: NSView {
    private let detail = NSTextField(labelWithString: "")

    init(name: String, symbol: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 58))
        let icon = NSImageView(frame: NSRect(x: 17, y: 19, width: 22, height: 22))
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        let title = NSTextField(labelWithString: name)
        title.frame = NSRect(x: 48, y: 32, width: 216, height: 18)
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        detail.frame = NSRect(x: 48, y: 12, width: 216, height: 17)
        detail.font = .systemFont(ofSize: 11, weight: .medium)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        for view in [icon, title, detail] { addSubview(view) }
        setAccessibilityRole(.group)
        setAccessibilityLabel(name)
    }

    required init?(coder: NSCoder) { nil }

    func setStatus(_ text: String) {
        detail.stringValue = text
        detail.toolTip = text
        setAccessibilityValue(text)
    }
}

private final class ShortcutMenuRow: NSView {
    private let label: NSTextField
    private let keys: NSTextField
    private let keyLabel: String

    init(_ title: String, keys: String) {
        label = NSTextField(labelWithString: title)
        self.keys = NSTextField(labelWithString: keys)
        keyLabel = keys
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 23))
        label.frame = NSRect(x: 19, y: 4, width: 151, height: 16)
        label.font = .menuFont(ofSize: 0)
        self.keys.frame = NSRect(x: 168, y: 4, width: 96, height: 16)
        self.keys.font = .systemFont(ofSize: 12, weight: .medium)
        self.keys.textColor = .secondaryLabelColor
        self.keys.alignment = .right
        addSubview(label)
        addSubview(self.keys)
        setAccessibilityRole(.group)
        setAvailable(true)
    }

    required init?(coder: NSCoder) { nil }

    func setAvailable(_ available: Bool) {
        label.textColor = available ? .labelColor : .secondaryLabelColor
        keys.stringValue = available ? keyLabel : "Unavailable"
        setAccessibilityLabel("\(label.stringValue), \(keyLabel)")
        setAccessibilityValue(available ? nil : "Unavailable")
        toolTip = available ? nil : "\(keyLabel) is unavailable. See Setup."
    }

    func menuItem() -> NSMenuItem {
        let item = NSMenuItem()
        item.view = self
        return item
    }
}

private struct InsertionTarget {
    let application: NSRunningApplication
    let element: AXUIElement?
    let range: CFTypeRef?

    init?() {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        self.application = application
        element = Self.focusedElement(in: application)
        var initialRange: CFTypeRef?
        if let element {
            AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &initialRange)
        }
        range = initialRange
    }

    static func focusedElement(in application: NSRunningApplication) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        var value: CFTypeRef?
        let app = AXUIElementCreateApplication(application.processIdentifier)
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
}

final class DictationApp: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menuHeader = SpeechMenuHeader(name: "Nemotron Dictation", symbol: "waveform")
    private let toggleRow = ShortcutMenuRow("Start / Stop Recording", keys: "⌃Space")
    private let holdRow = ShortcutMenuRow("Hold to Talk", keys: "⌃⌥Space")
    private var stopItem: NSMenuItem!
    private var pasteItem: NSMenuItem!
    private var copyItem: NSMenuItem!
    private var setupItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var shortcut: EventHotKeyRef?
    private var toggleShortcut: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var destination: InsertionTarget?
    private var recordingUsesToggle = false
    private var permissionTimer: Timer?
    private let indicator = RecordingIndicator()
    private var awaitingTranscript = false {
        didSet { refreshStatus() }
    }
    private var lastTranscript = ""
    private var micRequestInProgress = false
    private let settings = UserDefaults.standard
    private var setup: SetupWindow?
    private var modelState: ModelAssets.State?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        settings.register(defaults: ["autoPaste": true])
        let header = NSMenuItem()
        header.view = menuHeader
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(toggleRow.menuItem())
        menu.addItem(holdRow.menuItem())
        stopItem = addMenuAction("Stop Recording", action: #selector(stopRecording), to: menu)
        menu.addItem(.separator())
        copyItem = addMenuAction("Copy Last Transcript", action: #selector(copyLast), to: menu)
        pasteItem = addMenuAction("Paste Automatically", action: #selector(togglePaste), to: menu)
        menu.addItem(.separator())
        setupItem = addMenuAction("Setup…", action: #selector(showSetup), to: menu)
        loginItem = addMenuAction("Open at Login", action: #selector(toggleOpenAtLogin), to: menu)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Nemotron Dictation", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.delegate = self
        statusItem.menu = menu

        indicator.onStop = { [weak self] in self?.stopRecording() }
        indicator.onDiscard = { [weak self] in self?.discardRecording() }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, self.setup?.window?.isVisible == true else { return }
            self.refreshSetup()
            self.refreshStatus()
        }
        registerHotKeys()
        refreshMenu()
        if !settings.bool(forKey: "finishedSetup") { showSetup() }
        if CommandLine.arguments.contains("--enable-open-at-login") {
            setOpenAtLogin(true)
        }
    }

    @objc private func showSetup() {
        if setup == nil {
            let window = SetupWindow()
            window.onDownload = { [weak self] in self?.downloadModel() }
            window.onMicrophone = { [weak self] in self?.requestMicrophone() }
            window.onPaste = { [weak self] in self?.requestPasteAccess() }
            window.onKeyboard = { [weak self] in self?.openKeyboardSettings() }
            window.onDone = { [weak self] in
                self?.settings.set(true, forKey: "finishedSetup")
                self?.setup?.close()
            }
            setup = window
        }
        refreshSetup()
        NSApp.activate(ignoringOtherApps: true)
        setup?.showWindow(nil)
        setup?.window?.makeKeyAndOrderFront(nil)
    }

    private func refreshSetup() {
        setup?.update(modelInstalled: ModelAssets.installedModel != nil, state: modelState,
                      micGranted: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                      pasteEnabled: settings.bool(forKey: "autoPaste"), pasteGranted: AXIsProcessTrusted(),
                      toggleAvailable: toggleShortcut != nil, holdAvailable: shortcut != nil)
    }

    private func downloadModel() {
        if case .downloading = modelState { return }
        if case .verifying = modelState { return }
        modelState = .downloading(0)
        refreshSetup()
        refreshStatus()
        ModelAssets { [weak self] state in
            self?.modelState = state
            self?.refreshSetup()
            self?.refreshStatus()
        }.start()
    }

    private func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func addMenuAction(_ title: String, action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) { refreshMenu() }

    private func refreshMenu() {
        refreshStatus()
        toggleRow.setAvailable(toggleShortcut != nil)
        holdRow.setAvailable(shortcut != nil)
        stopItem.isHidden = recorder == nil
        let autoPaste = settings.bool(forKey: "autoPaste")
        let needsPasteAccess = autoPaste && !AXIsProcessTrusted()
        pasteItem.state = needsPasteAccess ? .mixed : (autoPaste ? .on : .off)
        pasteItem.toolTip = needsPasteAccess ? "Automatic paste needs Accessibility access." : nil
        switch SMAppService.mainApp.status {
        case .enabled:
            loginItem.state = .on
            loginItem.toolTip = nil
        case .requiresApproval:
            loginItem.state = .mixed
            loginItem.toolTip = "Approve in Login Items & Extensions."
        default:
            loginItem.state = .off
            loginItem.toolTip = nil
        }

        if ModelAssets.installedModel == nil {
            switch modelState {
            case .downloading, .verifying: setupItem.title = "View Model Setup…"
            case .failed: setupItem.title = "Retry Model Setup…"
            default: setupItem.title = "Set Up Speech Model…"
            }
        } else if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            setupItem.title = "Set Up Microphone…"
        } else if toggleShortcut == nil || shortcut == nil {
            setupItem.title = "Set Up Shortcuts…"
        } else if needsPasteAccess {
            setupItem.title = "Set Up Automatic Paste…"
        } else {
            setupItem.title = "Setup…"
        }
    }

    @objc private func toggleOpenAtLogin() {
        let status = SMAppService.mainApp.status
        if status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        } else {
            setOpenAtLogin(status != .enabled)
        }
    }

    private func setOpenAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        let registered = service.status == .enabled || service.status == .requiresApproval
        do {
            if enabled && !registered { try service.register() }
            if !enabled && registered { try service.unregister() }
            if enabled && service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            diagnostics.error("Could not change Open at Login: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn’t change Open at Login"
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item === copyItem { return recorder == nil && !awaitingTranscript && !lastTranscript.isEmpty }
        if item === stopItem { return recorder != nil }
        return true
    }

    private func registerHotKeys() {
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let installation = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &key)
            guard result == noErr, key.signature == hotKeySignature else {
                return OSStatus(eventNotHandledErr)
            }
            let app = Unmanaged<DictationApp>.fromOpaque(context).takeUnretainedValue()
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            switch key.id {
            case 1:
                if pressed { app.startRecording(usingToggle: false) }
                else if !app.recordingUsesToggle { app.stopRecording() }
            case 2:
                if !pressed { app.toggleRecording() }
            default:
                return OSStatus(eventNotHandledErr)
            }
            return noErr
        }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installation == noErr else {
            diagnostics.error("Keyboard handler installation failed: \(installation, privacy: .public)")
            return
        }
        let backup = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey),
                                         EventHotKeyID(signature: hotKeySignature, id: 1),
                                         GetApplicationEventTarget(), 0, &shortcut)
        let primary = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey),
                                          EventHotKeyID(signature: hotKeySignature, id: 2),
                                          GetApplicationEventTarget(), 0, &toggleShortcut)
        diagnostics.notice("Control-Space registration: \(primary, privacy: .public); backup: \(backup, privacy: .public)")
    }

    private func toggleRecording() {
        if recorder != nil { stopRecording() }
        else { startRecording(usingToggle: true) }
    }

    @objc private func requestPasteAccess() {
        settings.set(true, forKey: "autoPaste")
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            openPrivacyPane("Privacy_Accessibility")
        }
        refreshSetup()
        refreshStatus()
    }

    private func openPrivacyPane(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func requestMicrophone() {
        guard !micRequestInProgress else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            refreshStatus()
            refreshSetup()
        case .notDetermined:
            micRequestInProgress = true
            refreshStatus()
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.micRequestInProgress = false
                    NSLog("Microphone authorization granted: %d", granted ? 1 : 0)
                    self.refreshStatus()
                    self.refreshSetup()
                }
            }
        default:
            refreshStatus()
            openPrivacyPane("Privacy_Microphone")
        }
    }

    private func startRecording(usingToggle: Bool) {
        guard recorder == nil, !awaitingTranscript else { return }
        guard ModelAssets.installedModel != nil else {
            showSetup()
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            requestMicrophone()
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Nemotron-\(UUID().uuidString).wav")
        let target = InsertionTarget()
        do {
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ])
            guard recorder.record() else { throw DictationError(name: "Couldn’t start the microphone") }
            self.recorder = recorder
            recordingURL = url
            diagnostics.notice("Recording started")
            destination = target
            recordingUsesToggle = usingToggle
            indicator.record(recorder)
            refreshStatus()
        } catch {
            try? FileManager.default.removeItem(at: url)
            indicator.finish("Microphone failed to start", success: false)
            NSLog("Recording failed: %@", String(describing: error))
        }
    }

    @objc private func stopRecording() {
        guard let recorder, let url = recordingURL else { return }
        let duration = recorder.currentTime
        recorder.stop()
        diagnostics.notice("Recording stopped")
        self.recorder = nil
        recordingUsesToggle = false
        recordingURL = nil
        let capturedDestination = destination
        destination = nil
        guard duration >= 0.20 else {
            try? FileManager.default.removeItem(at: url)
            indicator.finish("Recording was too short", success: false)
            refreshStatus()
            return
        }
        awaitingTranscript = true
        indicator.processing()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try DictationApp.transcribe(url) }
            try? FileManager.default.removeItem(at: url)
            DispatchQueue.main.async { [weak self] in
                self?.deliver(result, to: capturedDestination)
            }
        }
    }

    private func discardRecording() {
        guard let recorder, let url = recordingURL else { return }
        recorder.stop()
        self.recorder = nil
        recordingURL = nil
        recordingUsesToggle = false
        destination = nil
        try? FileManager.default.removeItem(at: url)
        refreshStatus()
        indicator.finish("Recording discarded")
    }

    private struct DictationError: Error { let name: String }
    private struct Transcript: Decodable { let text: String }

    private static func transcribe(_ wav: URL) throws -> String {
        guard let resources = Bundle.main.resourceURL else {
            throw DictationError(name: "Missing dictation resources")
        }
        guard let model = ModelAssets.installedModel else {
            throw DictationError(name: "Download the speech model in Setup")
        }
        let process = Process()
        process.executableURL = resources.appendingPathComponent("Engine/parakeet-cli")
        process.arguments = ["transcribe", "--model", model.path, "--input", wav.path, "--lang", "en",
                             "--threads", String(min(8, ProcessInfo.processInfo.activeProcessorCount)), "--json"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DictationError(name: "Recognizer exited with code \(process.terminationStatus)")
        }
        return try JSONDecoder().decode(Transcript.self, from: data).text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func deliver(_ result: Result<String, Error>, to target: InsertionTarget?) {
        indicator.hide()
        switch result {
        case .success(let transcript) where !transcript.isEmpty:
            lastTranscript = transcript
            writeTranscriptToClipboard()
            indicator.finish("Copied to Clipboard")
            guard settings.bool(forKey: "autoPaste"), AXIsProcessTrusted(),
                  let target, target.element != nil, !target.application.isTerminated,
                  !IsSecureEventInputEnabled() else {
                awaitingTranscript = false
                return
            }
            let clipboardVersion = NSPasteboard.general.changeCount
            if !target.application.isActive {
                guard target.element != nil, target.application.activate(options: []) else {
                    awaitingTranscript = false
                    return
                }
            }
            paste(to: target, clipboardVersion: clipboardVersion, attempts: 5)
        case .success:
            awaitingTranscript = false
            indicator.finish("No speech recognized", success: false)
        case .failure(let error):
            awaitingTranscript = false
            indicator.finish("Transcription failed", success: false)
            diagnostics.error("Transcription failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func paste(to target: InsertionTarget, clipboardVersion: Int, attempts: Int) {
        guard attempts > 0, NSPasteboard.general.changeCount == clipboardVersion else {
            awaitingTranscript = false
            return
        }
        if target.application.isActive, !IsSecureEventInputEnabled(), let original = target.element {
            if let focused = InsertionTarget.focusedElement(in: target.application), CFEqual(focused, original) {
                if let range = target.range {
                    var current: CFTypeRef?
                    AXUIElementCopyAttributeValue(original, kAXSelectedTextRangeAttribute as CFString, &current)
                    if current == nil || !CFEqual(current, range) {
                        guard AXUIElementSetAttributeValue(original, kAXSelectedTextRangeAttribute as CFString, range) == .success else {
                            awaitingTranscript = false
                            return
                        }
                    }
                }
                sendPaste(to: target.application.processIdentifier)
                return
            }
            AXUIElementSetAttributeValue(original, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.paste(to: target, clipboardVersion: clipboardVersion, attempts: attempts - 1)
        }
    }

    private func sendPaste(to pid: pid_t) {
        awaitingTranscript = false
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(pid)
        up.postToPid(pid)
        indicator.finish("Transcript pasted")
        diagnostics.notice("Sent paste to dictation target")
    }

    @objc private func togglePaste() {
        if settings.bool(forKey: "autoPaste") {
            settings.set(false, forKey: "autoPaste")
            refreshSetup()
            refreshStatus()
        } else {
            requestPasteAccess()
        }
    }

    @objc private func copyLast() {
        guard validateMenuItem(copyItem) else { return }
        writeTranscriptToClipboard()
    }

    private func writeTranscriptToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastTranscript, forType: .string)
    }

    private func refreshStatus() {
        let message: String
        let symbol: String
        if recorder != nil {
            message = recordingUsesToggle ? "Recording…" : "Recording · Release to transcribe"
            symbol = "mic.fill"
        } else if awaitingTranscript {
            message = "Transcribing…"
            symbol = "ellipsis.circle"
        } else if ModelAssets.installedModel == nil {
            switch modelState {
            case .downloading: message = "Downloading speech model…"
            case .verifying: message = "Verifying speech model…"
            case .failed: message = "Model download failed"
            default: message = "Speech model required"
            }
            symbol = "waveform"
        } else if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            message = "Microphone access required"
            symbol = "mic.slash"
        } else if toggleShortcut == nil && shortcut == nil {
            message = "Shortcuts unavailable"
            symbol = "waveform"
        } else if settings.bool(forKey: "autoPaste") && !AXIsProcessTrusted() {
            message = "Ready · Copies to clipboard"
            symbol = "waveform"
        } else {
            message = "Ready"
            symbol = "waveform"
        }
        guard let button = statusItem.button else { return }
        menuHeader.setStatus(message)
        let description = "Nemotron Dictation, \(message)"
        if button.toolTip != description {
            let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
            image?.isTemplate = true
            button.image = image
            button.toolTip = description
            button.setAccessibilityLabel(description)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        recorder?.stop()
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        indicator.hide()
        permissionTimer?.invalidate()
        if let shortcut { UnregisterEventHotKey(shortcut) }
        if let toggleShortcut { UnregisterEventHotKey(toggleShortcut) }
        if let handler { RemoveEventHandler(handler) }
    }

    static func run() {
        if CommandLine.arguments == [CommandLine.arguments[0], "--preview-indicator"] {
            let application = NSApplication.shared
            application.setActivationPolicy(.accessory)
            let indicator = RecordingIndicator()
            indicator.showRecording()
            indicator.previewLevels()
            Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { _ in
                indicator.hide()
                application.terminate(nil)
            }
            application.run()
            return
        }
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--test-file" {
            do { print(try transcribe(URL(fileURLWithPath: CommandLine.arguments[2]))) }
            catch {
                fputs("Dictation test failed: \(error)\n", stderr)
                exit(1)
            }
            return
        }
        let app = NSApplication.shared
        let delegate = DictationApp()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
