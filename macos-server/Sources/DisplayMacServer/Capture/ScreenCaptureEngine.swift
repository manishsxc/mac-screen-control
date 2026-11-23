import Foundation
import ScreenCaptureKit
import CoreAudio
import CoreMedia
import CoreVideo
import AVFoundation

public protocol ScreenCaptureEngineDelegate: AnyObject {
    func captureEngine(_ engine: ScreenCaptureEngine, didCaptureSampleBuffer sampleBuffer: CMSampleBuffer)
    func captureEngine(_ engine: ScreenCaptureEngine, didCaptureAudioData data: Data)
}

public struct ShareableTarget: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let isDisplay: Bool
    public let displayID: CGDirectDisplayID?
    public let windowID: CGWindowID?
    public let appName: String?

    public init(id: String, name: String, isDisplay: Bool, displayID: CGDirectDisplayID? = nil, windowID: CGWindowID? = nil, appName: String? = nil) {
        self.id = id
        self.name = name
        self.isDisplay = isDisplay
        self.displayID = displayID
        self.windowID = windowID
        self.appName = appName
    }
}

public final class ScreenCaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate {
    public weak var delegate: ScreenCaptureEngineDelegate?

    private var stream: SCStream?
    private let videoQueue = DispatchQueue(label: "com.displaymac.capture.video", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "com.displaymac.capture.audio", qos: .userInteractive)
    public private(set) var isRunning: Bool = false

    /// Fetch available screens and windows for the picker (Google Meet style)
    public static func getShareableTargets() async throws -> [ShareableTarget] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var targets: [ShareableTarget] = []

        // Displays
        for (index, display) in content.displays.enumerated() {
            targets.append(ShareableTarget(
                id: "display_\(display.displayID)",
                name: "Entire Screen \(index + 1) (\(display.width)x\(display.height))",
                isDisplay: true,
                displayID: display.displayID
            ))
        }

        // Windows (only visible user windows with titles)
        for window in content.windows {
            guard let title = window.title, !title.isEmpty,
                  window.frame.width > 100, window.frame.height > 100,
                  let app = window.owningApplication,
                  app.bundleIdentifier != "com.apple.dock",
                  app.bundleIdentifier != "com.apple.controlcenter" else { continue }

            targets.append(ShareableTarget(
                id: "window_\(window.windowID)",
                name: "\(app.applicationName): \(title)",
                isDisplay: false,
                windowID: window.windowID,
                appName: app.applicationName
            ))
        }

        return targets
    }

    /// Start capturing either a full display or a specific window
    public func startCapture(
        target: ShareableTarget? = nil,
        displayID: CGDirectDisplayID? = nil,
        width: Int,
        height: Int,
        targetFps: Int = 60
    ) async throws {
        guard !isRunning else { return }

        if !CGPreflightScreenCaptureAccess() {
            print("[ScreenCapture] Requesting Screen Recording authorization...")
            _ = CGRequestScreenCaptureAccess()
        }

        let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let filter: SCContentFilter

        if let target = target {
            if target.isDisplay, let targetDisplayID = target.displayID ?? displayID {
                guard let display = shareableContent.displays.first(where: { $0.displayID == targetDisplayID }) else {
                    throw NSError(domain: "com.displaymac", code: -1, userInfo: [NSLocalizedDescriptionKey: "Display not found"])
                }
                filter = SCContentFilter(display: display, excludingWindows: [])
            } else if let windowID = target.windowID {
                guard let window = shareableContent.windows.first(where: { $0.windowID == windowID }) else {
                    throw NSError(domain: "com.displaymac", code: -1, userInfo: [NSLocalizedDescriptionKey: "Window not found"])
                }
                filter = SCContentFilter(desktopIndependentWindow: window)
            } else {
                guard let display = shareableContent.displays.first else {
                    throw NSError(domain: "com.displaymac", code: -1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
                }
                filter = SCContentFilter(display: display, excludingWindows: [])
            }
        } else if let displayID = displayID {
            // Virtual or specific display ID
            var targetDisplay: SCDisplay?
            for _ in 0..<30 {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                if let found = content.displays.first(where: { $0.displayID == displayID }) {
                    targetDisplay = found
                    break
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }

            guard let displayToCapture = targetDisplay ?? shareableContent.displays.first else {
                throw NSError(domain: "com.displaymac", code: -1, userInfo: [NSLocalizedDescriptionKey: "Target display not found"])
            }
            filter = SCContentFilter(display: displayToCapture, excludingWindows: [])
        } else {
            guard let display = shareableContent.displays.first else {
                throw NSError(domain: "com.displaymac", code: -1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
            }
            filter = SCContentFilter(display: display, excludingWindows: [])
        }

        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(targetFps, 24)))
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = true
        configuration.scalesToFit = true
        configuration.queueDepth = 3

        let scStream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try scStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)

        try await scStream.startCapture()
        self.stream = scStream
        self.isRunning = true
        print("[ScreenCapture] Active at \(width)x\(height) @ \(targetFps) FPS (NV12)")
    }

    public func stopCapture() async {
        guard isRunning, let stream = stream else { return }
        do {
            try await stream.stopCapture()
            print("[ScreenCapture] Stream stopped")
        } catch {
            print("[ScreenCapture] Error stopping stream: \(error.localizedDescription)")
        }
        self.stream = nil
        self.isRunning = false
    }

    // MARK: - SCStreamOutput
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }

        if type == .screen {
            delegate?.captureEngine(self, didCaptureSampleBuffer: sampleBuffer)
        } else {
            if #available(macOS 13.0, *) {
                if type == .audio {
                    if let pcm16Data = extractPCM16Data(from: sampleBuffer) {
                        delegate?.captureEngine(self, didCaptureAudioData: pcm16Data)
                    }
                }
            }
        }
    }

    private func extractPCM16Data(from sampleBuffer: CMSampleBuffer) -> Data? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee else {
            return nil
        }

        var audioBufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let numBuffers = Int(audioBufferList.mNumberBuffers)

        if isFloat {
            let buffers = UnsafeMutableAudioBufferListPointer(&audioBufferList)
            if isNonInterleaved && numBuffers >= 2 {
                guard let leftPtr = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                      let rightPtr = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return nil }
                let frameCount = Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size
                guard frameCount > 0 else { return nil }

                var pcmData = Data(count: frameCount * 4)
                pcmData.withUnsafeMutableBytes { rawOut in
                    let outPtr = rawOut.bindMemory(to: Int16.self).baseAddress!
                    for i in 0..<frameCount {
                        let l = max(-1.0, min(1.0, leftPtr[i]))
                        let r = max(-1.0, min(1.0, rightPtr[i]))
                        outPtr[i * 2] = Int16(l * 32767.0)
                        outPtr[i * 2 + 1] = Int16(r * 32767.0)
                    }
                }
                return pcmData
            } else if numBuffers >= 1 {
                guard let floatPtr = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return nil }
                let sampleCount = Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size
                guard sampleCount > 0 else { return nil }

                var pcmData = Data(count: sampleCount * 2)
                pcmData.withUnsafeMutableBytes { rawOut in
                    let outPtr = rawOut.bindMemory(to: Int16.self).baseAddress!
                    for i in 0..<sampleCount {
                        let s = max(-1.0, min(1.0, floatPtr[i]))
                        outPtr[i] = Int16(s * 32767.0)
                    }
                }
                return pcmData
            }
        } else {
            guard let mData = audioBufferList.mBuffers.mData else { return nil }
            return Data(bytes: mData, count: Int(audioBufferList.mBuffers.mDataByteSize))
        }

        return nil
    }

    // MARK: - SCStreamDelegate
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[ScreenCapture] Stream halted: \(error.localizedDescription)")
        self.isRunning = false
    }
}
