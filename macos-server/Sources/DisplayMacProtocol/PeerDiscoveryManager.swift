import Foundation
import Network

/// Represents the discovery payload broadcasted over UDP port 7105
public struct DiscoveryBeacon: Codable, Equatable {
    public let code: String          // 6-digit PIN (e.g. "482910")
    public let role: String          // "sharer" or "viewer"
    public let deviceName: String
    public let platform: String      // "macos" or "android"
    public let port: UInt16          // TCP control port (e.g. 7100)
    public let timestamp: TimeInterval

    public init(code: String, role: String, deviceName: String, platform: String, port: UInt16 = 7100) {
        self.code = code
        self.role = role
        self.deviceName = deviceName
        self.platform = platform
        self.port = port
        self.timestamp = Date().timeIntervalSince1970
    }
}

/// UDP Broadcast Discovery Manager for local 6-digit PIN pairing
public final class PeerDiscoveryManager {
    public static let discoveryPort: UInt16 = 7105
    public static let broadcastAddress = "255.255.255.255"

    private var broadcastTimer: Timer?
    private var listener: NWListener?
    private var activeBeacon: DiscoveryBeacon?
    private let queue = DispatchQueue(label: "com.displaymac.discovery", qos: .utility)

    public var onPeerDiscovered: ((DiscoveryBeacon, String) -> Void)?

    public init() {}

    /// Start advertising a 6-digit code as a Sharer (Host) or Receiver
    public func startAdvertising(beacon: DiscoveryBeacon) {
        self.activeBeacon = beacon
        startListening()

        DispatchQueue.main.async { [weak self] in
            self?.broadcastTimer?.invalidate()
            self?.broadcastTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.sendBroadcast()
            }
        }
    }

    /// Stop advertising
    public func stop() {
        DispatchQueue.main.async { [weak self] in
            self?.broadcastTimer?.invalidate()
            self?.broadcastTimer = nil
        }
        listener?.cancel()
        listener = nil
        activeBeacon = nil
    }

    /// Listen for incoming discovery beacons
    public func startListening() {
        guard listener == nil else { return }

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        do {
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.discoveryPort)!)
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingPacket(connection: connection)
            }
            listener?.start(queue: queue)
        } catch {
            print("[Discovery] Failed to start listener: \(error)")
        }
    }

    private func sendBroadcast() {
        guard let beacon = activeBeacon,
              let data = try? JSONEncoder().encode(beacon) else { return }

        let host = NWEndpoint.Host(Self.broadcastAddress)
        let port = NWEndpoint.Port(rawValue: Self.discoveryPort)!
        let connection = NWConnection(host: host, port: port, using: .udp)

        connection.stateUpdateHandler = { state in
            if case .ready = state {
                connection.send(content: data, completion: .contentProcessed({ _ in
                    connection.cancel()
                }))
            }
        }
        connection.start(queue: queue)
    }

    private func handleIncomingPacket(connection: NWConnection) {
        connection.start(queue: queue)
        connection.receiveMessage { [weak self] content, context, isComplete, error in
            defer { connection.cancel() }
            guard let data = content,
                  let beacon = try? JSONDecoder().decode(DiscoveryBeacon.self, from: data) else { return }

            var senderIP = "127.0.0.1"
            if case let .hostPort(host, _) = connection.endpoint {
                switch host {
                case .ipv4(let addr):
                    senderIP = "\(addr)"
                default:
                    senderIP = host.debugDescription
                }
            }

            self?.onPeerDiscovered?(beacon, senderIP)
        }
    }

    /// Generate a cryptographically secure 6-digit PIN
    public static func generate6DigitCode() -> String {
        let num = Int.random(in: 100000...999999)
        return String(num)
    }
}
