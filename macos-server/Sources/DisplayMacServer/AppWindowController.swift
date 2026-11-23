import AppKit
import DisplayMacProtocol

public final class AppWindowController: NSWindowController {
    private var viewModel = AppViewModel()

    private var visualEffectView: NSVisualEffectView!
    private var tabSegment: NSSegmentedControl!
    private var targetPopup: NSPopUpButton!
    private var actionButton: NSButton!
    private var codeField: NSTextField!
    private var codeDisplayLabel: NSTextField!
    private var statusLabel: NSTextField!
    private var spinner: NSProgressIndicator!
    private var updateBanner: NSButton!

    public convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "DisplayMac"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()
        self.init(window: window)
        setupLiquidGlassUI()
        checkForUpdates()
    }

    private func setupLiquidGlassUI() {
        guard let window = window else { return }

        // Liquid Glass Background (Translucent Vibrancy adapting to Light/Dark Mode)
        visualEffectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 500, height: 480))
        visualEffectView.material = .underWindowBackground
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.autoresizingMask = [.width, .height]
        window.contentView = visualEffectView

        let contentView = visualEffectView!

        // Header Title
        let titleLabel = NSTextField(labelWithString: "DisplayMac")
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.frame = NSRect(x: 24, y: 410, width: 280, height: 30)
        contentView.addSubview(titleLabel)

        let copyrightLabel = NSTextField(labelWithString: "© 2026 Sumit Kumar. All rights reserved.")
        copyrightLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        copyrightLabel.textColor = .secondaryLabelColor
        copyrightLabel.frame = NSRect(x: 24, y: 390, width: 350, height: 18)
        contentView.addSubview(copyrightLabel)

        // Update Notification Banner (Hidden by default)
        updateBanner = NSButton(frame: NSRect(x: 24, y: 355, width: 452, height: 26))
        updateBanner.bezelStyle = .inline
        updateBanner.title = "✨ New Update Available! Click to Install"
        updateBanner.target = self
        updateBanner.action = #selector(openUpdateLink)
        updateBanner.isHidden = true
        contentView.addSubview(updateBanner)

        // Segmented Control (Liquid glass pill style)
        tabSegment = NSSegmentedControl(labels: ["Share Screen", "Receive / Control"], trackingMode: .selectOne, target: self, action: #selector(tabChanged))
        tabSegment.selectedSegment = 0
        tabSegment.frame = NSRect(x: 24, y: 315, width: 452, height: 32)
        contentView.addSubview(tabSegment)

        // Target Picker (Screen or Window - Google Meet style)
        let targetLabel = NSTextField(labelWithString: "Select what to share:")
        targetLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        targetLabel.frame = NSRect(x: 24, y: 275, width: 452, height: 20)
        targetLabel.identifier = NSUserInterfaceItemIdentifier("ShareElements")
        contentView.addSubview(targetLabel)

        targetPopup = NSPopUpButton(frame: NSRect(x: 24, y: 242, width: 452, height: 28), pullsDown: false)
        targetPopup.target = self
        targetPopup.action = #selector(targetSelected)
        targetPopup.identifier = NSUserInterfaceItemIdentifier("ShareElements")
        contentView.addSubview(targetPopup)

        // 6-digit Code Display (Sharer mode)
        codeDisplayLabel = NSTextField(labelWithString: "")
        codeDisplayLabel.font = NSFont.monospacedSystemFont(ofSize: 36, weight: .bold)
        codeDisplayLabel.alignment = .center
        codeDisplayLabel.frame = NSRect(x: 40, y: 165, width: 420, height: 50)
        codeDisplayLabel.isHidden = true
        contentView.addSubview(codeDisplayLabel)

        // 6-digit Code Input (Receiver mode)
        codeField = NSTextField(frame: NSRect(x: 150, y: 230, width: 200, height: 42))
        codeField.font = NSFont.monospacedSystemFont(ofSize: 26, weight: .semibold)
        codeField.alignment = .center
        codeField.placeholderString = "6-Digit Code"
        codeField.isHidden = true
        contentView.addSubview(codeField)

        // Primary Action Button (Liquid glass accent)
        actionButton = NSButton(frame: NSRect(x: 130, y: 100, width: 240, height: 38))
        actionButton.bezelStyle = .rounded
        actionButton.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        actionButton.title = "Create Session & Share"
        actionButton.target = self
        actionButton.action = #selector(actionClicked)
        contentView.addSubview(actionButton)

        // Spinner
        spinner = NSProgressIndicator(frame: NSRect(x: 238, y: 68, width: 24, height: 24))
        spinner.style = .spinning
        spinner.isDisplayedWhenStopped = false
        contentView.addSubview(spinner)

        // Status Label
        statusLabel = NSTextField(labelWithString: "Ready to connect")
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.frame = NSRect(x: 24, y: 44, width: 452, height: 20)
        contentView.addSubview(statusLabel)

        // Footer links: Privacy, User Manual, Feedback
        let footerStack = NSStackView(frame: NSRect(x: 24, y: 14, width: 452, height: 22))
        footerStack.orientation = .horizontal
        footerStack.distribution = .equalCentering

        let privacyBtn = createHyperlinkButton(title: "Privacy Policy", action: #selector(openPrivacy))
        let manualBtn = createHyperlinkButton(title: "User Manual", action: #selector(openManual))
        let feedbackBtn = createHyperlinkButton(title: "Feedback & Support", action: #selector(openFeedback))

        footerStack.addArrangedSubview(privacyBtn)
        footerStack.addArrangedSubview(manualBtn)
        footerStack.addArrangedSubview(feedbackBtn)
        contentView.addSubview(footerStack)

        refreshTargets()
    }

    private func createHyperlinkButton(title: String, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.isBordered = false
        btn.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        btn.contentTintColor = .linkColor
        return btn
    }

    private func checkForUpdates() {
        UpdateChecker.shared.checkForUpdates { [weak self] updateInfo in
            guard let self = self, let update = updateInfo else { return }
            self.updateBanner.title = "🚀 Update v\(update.latestVersion) Available! Click to Install"
            self.updateBanner.isHidden = false
        }
    }

    @objc private func openUpdateLink() {
        if let url = URL(string: "https://github.com/sumitkumar/DisplayMac/releases") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openPrivacy() {
        let alert = NSAlert()
        alert.messageText = "DisplayMac Privacy Policy"
        alert.informativeText = "DisplayMac collects ZERO cloud data. All video streaming and remote touch inputs stay 100% private and encrypted within your local network."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func openManual() {
        let alert = NSAlert()
        alert.messageText = "DisplayMac User Manual"
        alert.informativeText = "1. To Share: Select screen/window, click 'Create Session & Share' and enter the 6-digit code on Android.\n2. To Receive: Enter the 6-digit code from Android and click 'Receive & Control'."
        alert.addButton(withTitle: "Got it")
        alert.runModal()
    }

    @objc private func openFeedback() {
        let alert = NSAlert()
        alert.messageText = "Send Feedback"
        alert.informativeText = "Have an idea, bug report, or feature request? We'd love to hear from you at sumitranjanhisu@gmail.com."
        alert.addButton(withTitle: "Send Email")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            if let emailUrl = URL(string: "mailto:sumitranjanhisu@gmail.com?subject=DisplayMac%20Feedback") {
                NSWorkspace.shared.open(emailUrl)
            }
        }
    }

    private func refreshTargets() {
        Task {
            let targets = (try? await ScreenCaptureEngine.getShareableTargets()) ?? []
            await MainActor.run {
                self.targetPopup.removeAllItems()
                for target in targets {
                    self.targetPopup.addItem(withTitle: target.name)
                }
                self.viewModel.availableTargets = targets
                self.viewModel.selectedTarget = targets.first
            }
        }
    }

    @objc private func tabChanged() {
        let isShare = tabSegment.selectedSegment == 0
        codeField.isHidden = isShare
        targetPopup.isHidden = !isShare
        codeDisplayLabel.isHidden = true

        for view in visualEffectView.subviews {
            if view.identifier?.rawValue == "ShareElements" {
                view.isHidden = !isShare
            }
        }

        if isShare {
            actionButton.title = "Create Session & Share"
            statusLabel.stringValue = "Select a screen/window to start sharing."
        } else {
            actionButton.title = "Receive & Control Peer"
            statusLabel.stringValue = "Enter 6-digit code shown on peer device."
        }
    }

    @objc private func targetSelected() {
        let index = targetPopup.indexOfSelectedItem
        if index >= 0 && index < viewModel.availableTargets.count {
            viewModel.selectedTarget = viewModel.availableTargets[index]
        }
    }

    @objc private func actionClicked() {
        if viewModel.mode != .idle {
            viewModel.stopAll()
            actionButton.title = tabSegment.selectedSegment == 0 ? "Create Session & Share" : "Receive & Control Peer"
            codeDisplayLabel.isHidden = true
            tabSegment.isEnabled = true
            spinner.stopAnimation(nil)
            statusLabel.stringValue = "Ready"
            return
        }

        if tabSegment.selectedSegment == 0 {
            // Share
            viewModel.startSharing()
            if case .sharing(let code, _) = viewModel.mode {
                codeDisplayLabel.stringValue = "\(code)"
                codeDisplayLabel.isHidden = false
                actionButton.title = "Stop Sharing"
                tabSegment.isEnabled = false
                statusLabel.stringValue = "Sharing active! Enter PIN \(code) on Android."
            }
        } else {
            // Receive
            let code = codeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard code.count == 6 else {
                statusLabel.stringValue = "Please enter a valid 6-digit PIN"
                return
            }
            viewModel.pinCodeInput = code
            viewModel.startReceiving()
            actionButton.title = "Cancel"
            tabSegment.isEnabled = false
            spinner.startAnimation(nil)
            statusLabel.stringValue = "Searching for peer with PIN \(code) on local Wi-Fi..."
        }
    }
}
