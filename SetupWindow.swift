import AppKit

final class SetupWindow: NSWindowController {
    private let model = NSTextField(wrappingLabelWithString: "")
    private let microphone = NSTextField(wrappingLabelWithString: "")
    private let paste = NSTextField(wrappingLabelWithString: "")
    private let shortcuts = NSTextField(wrappingLabelWithString: "")
    private let download = NSButton(title: "Download model", target: nil, action: nil)
    private let progress = NSProgressIndicator()
    private let allowMic = NSButton(title: "Allow microphone", target: nil, action: nil)
    private let allowPaste = NSButton(title: "Enable automatic paste", target: nil, action: nil)
    private let keyboard = NSButton(title: "Keyboard shortcuts…", target: nil, action: nil)
    private let done = NSButton(title: "Done", target: nil, action: nil)

    var onDownload: (() -> Void)?
    var onMicrophone: (() -> Void)?
    var onPaste: (() -> Void)?
    var onKeyboard: (() -> Void)?
    var onDone: (() -> Void)?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 525),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Nemotron Dictation Setup"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let title = NSTextField(labelWithString: "Set up Nemotron Dictation")
        title.font = .systemFont(ofSize: 23, weight: .semibold)
        let intro = NSTextField(wrappingLabelWithString: "Dictate in English. Your recordings are transcribed on this Mac.")
        let trial = NSTextField(string: "")
        trial.placeholderString = "Try dictating into this field"
        trial.setAccessibilityLabel("Dictation test field")
        let tip = NSTextField(wrappingLabelWithString: "Say “This is my first dictation.” If automatic paste is off, press ⌘V to insert the transcript.")
        tip.textColor = .secondaryLabelColor
        progress.minValue = 0
        progress.maxValue = 1
        progress.isIndeterminate = false

        let rows: [(NSButton, Selector)] = [
            (download, #selector(downloadModel)), (allowMic, #selector(enableMicrophone)),
            (allowPaste, #selector(enablePaste)), (keyboard, #selector(openKeyboard)), (done, #selector(finishSetup))
        ]
        for (button, action) in rows {
            button.target = self
            button.action = action
            button.bezelStyle = .rounded
        }
        let stack = NSStackView(views: [title, intro, model, download, progress, microphone, allowMic,
                                       paste, allowPaste, shortcuts, keyboard, trial, tip, done])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(19, after: intro)
        stack.setCustomSpacing(16, after: progress)
        stack.setCustomSpacing(16, after: allowMic)
        stack.setCustomSpacing(16, after: allowPaste)
        stack.setCustomSpacing(12, after: keyboard)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        window.contentView = content
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
        ] + [intro, model, microphone, paste, shortcuts, progress, trial, tip].map {
            $0.widthAnchor.constraint(equalTo: stack.widthAnchor)
        })
        window.initialFirstResponder = trial
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func update(modelInstalled: Bool, state: ModelAssets.State?, micGranted: Bool, pasteEnabled: Bool,
                pasteGranted: Bool, toggleAvailable: Bool, holdAvailable: Bool) {
        progress.isHidden = true
        download.title = "Download model"
        download.isEnabled = !modelInstalled
        if modelInstalled {
            model.stringValue = "Speech model ready"
        } else {
            switch state {
            case .downloading(let fraction):
                model.stringValue = "Downloading English speech model… \(Int(fraction * 100))%"
                progress.isHidden = false
                progress.doubleValue = fraction
                download.isEnabled = false
            case .verifying:
                model.stringValue = "Verifying the model checksum…"
                progress.isHidden = false
                progress.doubleValue = 1
                download.isEnabled = false
            case .failed(let message):
                model.stringValue = "Download failed. \(message)"
                download.title = "Retry download"
            default:
                model.stringValue = "Download the 939 MB speech model once to dictate offline."
            }
        }
        microphone.stringValue = micGranted ? "Microphone access granted" : "Allow microphone access to record when you use a shortcut."
        allowMic.isEnabled = !micGranted
        paste.stringValue = pasteEnabled && pasteGranted ? "Automatic paste is on" :
            "Optional: allow Accessibility to paste into the field where you started."
        allowPaste.isEnabled = !pasteEnabled || !pasteGranted
        if toggleAvailable {
            let hint = holdAvailable ? "" : " The hold shortcut is unavailable."
            shortcuts.stringValue = "Click below. Press ⌃Space to start and again to transcribe.\(hint)"
        } else if holdAvailable {
            shortcuts.stringValue = "⌃Space is unavailable. Click below, then hold ⌃⌥Space to talk and release to transcribe."
        } else {
            shortcuts.stringValue = "Both shortcuts are unavailable. Free one in Keyboard Shortcuts, then reopen the app."
        }
        keyboard.isHidden = toggleAvailable && holdAvailable
        done.isEnabled = modelInstalled && micGranted
        window?.contentView?.layoutSubtreeIfNeeded()
    }

    @objc private func downloadModel() { onDownload?() }
    @objc private func enableMicrophone() { onMicrophone?() }
    @objc private func enablePaste() { onPaste?() }
    @objc private func openKeyboard() { onKeyboard?() }
    @objc private func finishSetup() { onDone?() }
}
