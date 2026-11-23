import Foundation
import CoreMedia
import ApplicationServices
import IOKit.pwr_mgt
import DisplayMacProtocol
import SwiftUI

public final class DisplayMacCoordinator: ScreenCaptureEngineDelegate, HardwareVideoEncoderDelegate, NetworkServerDelegate {
    private let displayManager = VirtualDisplayManager.shared
    private let captureEngine = ScreenCaptureEngine()
    private let videoEncoder = HardwareVideoEncoder()
    private let networkServer = NetworkServer()

    private var isStreaming = false
    private var encodedFrameCount: Int = 0
    private var lastStatsTime = Date()
    private var powerAssertionID: IOPMAssertionID = 0
    private var selectedTarget: ShareableTarget?

    public init() {
        captureEngine.delegate = self
        videoEncoder.delegate = self
        networkServer.delegate = self
    }

    private func preventSleep() {
        guard powerAssertionID == 0 else { return }
        let reason = "DisplayMac Active Streaming" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &powerAssertionID
        )
        if result == kIOReturnSuccess {
            print("[Power] Idle system sleep prevention enabled while streaming")
        }
    }

    private func allowSleep() {
        guard powerAssertionID != 0 else { return }
        IOPMAssertionRelease(powerAssertionID)
        powerAssertionID = 0
        print("[Power] Idle system sleep prevention released")
    }

    public func start(usbOnly: Bool = false, target: ShareableTarget? = nil) {
        self.selectedTarget = target
        do {
            try networkServer.start(bindLocalhostOnly: usbOnly)
        } catch {
            print("[Host] Fatal: Failed to bind network server: \(error)")
        }

        USBLinkManager.shared.startAutoBridge()
        AudioManager.shared.setActive(false)
        AudioManager.shared.setDynamicDeviceName("DisplayMac Audio")
        checkAccessibilityPermissions()
    }

    public func stop() {
        allowSleep()
        networkServer.stop()
        VirtualDisplayManager.shared.releaseVirtualDisplay()
        AudioManager.shared.stopCapturing()
        AudioManager.shared.restorePreviousOutputDevice()
        AudioManager.shared.restorePhysicalMacAudio()
        Task {
            await captureEngine.stopCapture()
        }
        isStreaming = false
    }

    // MARK: - NetworkServerDelegate
    public func networkServer(_ server: NetworkServer, didConnectClient hello: ClientHello, isLoopback: Bool) {
        print("\n[Coordinator] Client connected: \(hello.displayWidth)x\(hello.displayHeight) @ \(hello.maxRefreshRate)Hz")

        let targetWidth = Int(hello.displayWidth)
        let targetHeight = Int(hello.displayHeight)
        let targetFps = Int(hello.maxRefreshRate)
        let targetDpi = Int(hello.dpi)
        let targetBitrateMbps = isLoopback ? 60 : 35

        var activeDisplayID: CGDirectDisplayID?

        if let target = selectedTarget {
            if target.isDisplay {
                activeDisplayID = target.displayID
            }
        }

        // If no existing display selected, spawn virtual display
        if activeDisplayID == nil && selectedTarget?.windowID == nil {
            if displayManager.setupVirtualDisplay(
                width: targetWidth,
                height: targetHeight,
                refreshRate: targetFps,
                dpi: targetDpi
            ) {
                activeDisplayID = displayManager.activeDisplayID
            }
        }

        preventSleep()

        if let displayID = activeDisplayID {
            InputInjector.shared.updateActiveDisplay(displayID: displayID)
            let bounds = CGDisplayBounds(displayID)
            InputInjector.shared.updateScreenBounds(
                originX: bounds.origin.x,
                originY: bounds.origin.y,
                width: bounds.width,
                height: bounds.height
            )
        }

        let config = ServerConfig(
            selectedCodec: .hevc,
            activeFps: UInt8(min(targetFps, 255)),
            streamWidth: UInt32(targetWidth),
            streamHeight: UInt32(targetHeight),
            targetBitrateKbps: UInt32(targetBitrateMbps * 1000)
        )
        server.sendServerConfig(config)
        _ = videoEncoder.setupSession(width: targetWidth, height: targetHeight, fps: targetFps, bitrateMbps: targetBitrateMbps)

        Task {
            if captureEngine.isRunning {
                await captureEngine.stopCapture()
            }
            do {
                try await captureEngine.startCapture(
                    target: selectedTarget,
                    displayID: activeDisplayID,
                    width: targetWidth,
                    height: targetHeight,
                    targetFps: targetFps
                )
                self.isStreaming = true
                self.videoEncoder.requestImmediateKeyframe()
            } catch {
                print("[Coordinator] Error starting screen capture: \(error.localizedDescription)")
            }
        }
    }

    public func networkServerDidDisconnectClient(_ server: NetworkServer) {
        print("\n[Coordinator] Client disconnected; pausing capture")
        allowSleep()
        AudioManager.shared.setActive(false)
        AudioManager.shared.stopCapturing()
        AudioManager.shared.setDynamicDeviceName("DisplayMac Audio")
        AudioManager.shared.restorePreviousOutputDevice()
        Task {
            await captureEngine.stopCapture()
        }
        isStreaming = false
    }

    public func networkServerDidRequestKeyframe(_ server: NetworkServer) {
        videoEncoder.requestImmediateKeyframe()
    }

    public func shutdown() {
        stop()
    }

    // MARK: - ScreenCaptureEngineDelegate
    public func captureEngine(_ engine: ScreenCaptureEngine, didCaptureSampleBuffer sampleBuffer: CMSampleBuffer) {
        videoEncoder.encode(sampleBuffer: sampleBuffer)
    }

    public func captureEngine(_ engine: ScreenCaptureEngine, didCaptureAudioData data: Data) {}

    // MARK: - HardwareVideoEncoderDelegate
    public func videoEncoder(_ encoder: HardwareVideoEncoder, didEncodePacket data: Data, isKeyframe: Bool, pts: CMTime) {
        networkServer.broadcastVideoFrame(naluData: data, isKeyframe: isKeyframe, pts: pts)

        encodedFrameCount += 1
        let now = Date()
        let interval = now.timeIntervalSince(lastStatsTime)
        if interval >= 2.0 {
            let fps = Double(encodedFrameCount) / interval
            print(String(format: "[Stats] %.1f FPS | HEVC packets: %d", fps, encodedFrameCount))
            encodedFrameCount = 0
            lastStatsTime = now
        }
    }
}

public func getLocalIPs() -> [String] {
    var addresses = [String]()
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return [] }
    defer { freeifaddrs(ifaddr) }

    for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
        let flags = Int32(ptr.pointee.ifa_flags)
        let addr = ptr.pointee.ifa_addr.pointee
        if (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING),
           addr.sa_family == UInt8(AF_INET) {
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                let name = String(cString: hostname)
                let ifName = String(cString: ptr.pointee.ifa_name)
                if ifName.hasPrefix("en") || ifName.hasPrefix("bridge") {
                    addresses.append("\(name) (\(ifName))")
                }
            }
        }
    }
    return addresses
}

public func checkAccessibilityPermissions() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    let isTrusted = AXIsProcessTrustedWithOptions(options)
    if !isTrusted {
        print("[Input] Accessibility permission required; authorize DisplayMac in System Settings > Privacy & Security > Accessibility")
    } else {
        print("[Input] Accessibility permission verified")
    }
}

// AppKit Application Entry Point
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: AppWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let wc = AppWindowController()
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.windowController = wc
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
