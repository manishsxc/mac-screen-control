import SwiftUI
import DisplayMacProtocol

public enum AppMode: Equatable {
    case idle
    case sharing(code: String, target: ShareableTarget)
    case receiving(code: String, hostIP: String)
}

@MainActor
public final class AppViewModel: ObservableObject {
    @Published public var mode: AppMode = .idle
    @Published public var pinCodeInput: String = ""
    @Published public var generatedCode: String = ""
    @Published public var statusMessage: String = "Ready to Connect"
    @Published public var isConnected: Bool = false
    @Published public var availableTargets: [ShareableTarget] = []
    @Published public var selectedTarget: ShareableTarget?
    @Published public var isScanning: Bool = false

    private let discoveryManager = PeerDiscoveryManager()
    private var coordinator: DisplayMacCoordinator?

    public init() {
        self.coordinator = DisplayMacCoordinator()
        setupDiscovery()
        loadTargets()
    }

    public func loadTargets() {
        Task {
            do {
                let targets = try await ScreenCaptureEngine.getShareableTargets()
                await MainActor.run {
                    self.availableTargets = targets
                    if self.selectedTarget == nil {
                        self.selectedTarget = targets.first
                    }
                }
            } catch {
                print("Failed to load targets: \(error)")
            }
        }
    }

    private func setupDiscovery() {
        discoveryManager.onPeerDiscovered = { [weak self] beacon, ip in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if case .receiving(let enteredCode, _) = self.mode, enteredCode == beacon.code {
                    self.statusMessage = "Found peer: \(beacon.deviceName) at \(ip)"
                    self.connectToPeer(ip: ip, port: beacon.port)
                }
            }
        }
    }

    /// Action: Start Sharing (Host mode)
    public func startSharing() {
        guard let target = selectedTarget else {
            statusMessage = "Please select a screen or window to share"
            return
        }

        let code = PeerDiscoveryManager.generate6DigitCode()
        self.generatedCode = code
        self.mode = .sharing(code: code, target: target)
        self.statusMessage = "Sharing active! Waiting for peer code: \(code)"

        // Start local server
        coordinator?.start(usbOnly: false, target: target)

        // Broadcast 6-digit PIN
        let deviceName = Host.current().localizedName ?? "Mac"
        let beacon = DiscoveryBeacon(
            code: code,
            role: "sharer",
            deviceName: deviceName,
            platform: "macos",
            port: ProtocolConstants.controlPort
        )
        discoveryManager.startAdvertising(beacon: beacon)
    }

    /// Action: Start Receiving (Client/Viewer mode)
    public func startReceiving() {
        let code = pinCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == 6 else {
            statusMessage = "Please enter a valid 6-digit code"
            return
        }

        self.mode = .receiving(code: code, hostIP: "")
        self.statusMessage = "Searching for device with code \(code) on Wi-Fi..."
        self.isScanning = true
        discoveryManager.startListening()
    }

    private func connectToPeer(ip: String, port: UInt16) {
        self.statusMessage = "Connecting to \(ip):\(port)..."
        self.isConnected = true
        self.isScanning = false
        // Connection & remote view window management
    }

    public func stopAll() {
        discoveryManager.stop()
        coordinator?.stop()
        self.mode = .idle
        self.isConnected = false
        self.statusMessage = "Disconnected / Ready"
        self.isScanning = false
    }
}
