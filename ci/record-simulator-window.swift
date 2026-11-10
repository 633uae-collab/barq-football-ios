// Independent, original window capture for diagnosing simctl encoder omissions.
// macOS 15+, public ScreenCaptureKit APIs only. Does not request or change TCC.
import AppKit
import AVFoundation
import ScreenCaptureKit
import CoreMedia

final class CaptureObserver: NSObject, SCRecordingOutputDelegate, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var failure: String?
    private var samples: [[String: Any]] = []
    let readyFile: URL
    init(readyFile: URL) { self.readyFile = readyFile }
    var outcome: (Bool, String?) { lock.withLock { (finished, failure) } }
    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        try? Data("recording\n".utf8).write(to: readyFile)
    }
    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        lock.withLock { finished = true }
    }
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        lock.withLock { failure = error.localizedDescription; finished = true }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.withLock { failure = error.localizedDescription; finished = true }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid else { return }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]]
        let status = attachments?.first?[.status] as? Int ?? -1
        let row: [String: Any] = ["ptsSeconds": buffer.presentationTimeStamp.seconds,
                                  "status": status, "receivedUptimeSeconds": ProcessInfo.processInfo.systemUptime]
        lock.withLock { samples.append(row) }
    }
    func writeSamples(to url: URL) throws {
        let snapshot = lock.withLock { samples }
        let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }
}

@main enum WindowCapture {
    static func main() async {
        do {
            guard CommandLine.arguments.count == 3 else { throw CaptureError.message("Expected output.mp4 stop-file") }
            // Never bypass screen-recording permission or capture other windows.
            guard CGPreflightScreenCaptureAccess() else { throw CaptureError.message("Screen recording permission unavailable; no permission changes attempted") }
            let output = URL(fileURLWithPath: CommandLine.arguments[1])
            let stop = CommandLine.arguments[2]
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let candidates = content.windows.filter {
                $0.owningApplication?.bundleIdentifier == "com.apple.iphonesimulator"
                    && ($0.title?.contains("iPhone") ?? false) && $0.frame.height > 200
            }
            guard let window = candidates.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
                throw CaptureError.message("No visible iPhone Simulator window")
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale)) / 2 * 2
            config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale)) / 2 * 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.queueDepth = 8
            config.showsCursor = false
            config.capturesAudio = false
            let observer = CaptureObserver(readyFile: output.appendingPathExtension("ready"))
            let recordingConfig = SCRecordingOutputConfiguration()
            recordingConfig.outputURL = output
            recordingConfig.outputFileType = .mp4
            recordingConfig.videoCodecType = .h264
            let recording = SCRecordingOutput(configuration: recordingConfig, delegate: observer)
            let stream = SCStream(filter: filter, configuration: config, delegate: observer)
            try stream.addStreamOutput(observer, type: .screen, sampleHandlerQueue: DispatchQueue(label: "fotiq.window-capture"))
            try stream.addRecordingOutput(recording)
            print("Native Simulator window: \(window.title ?? "") \(config.width)x\(config.height); original ScreenCaptureKit recording")
            try await stream.startCapture()
            let start = ProcessInfo.processInfo.systemUptime
            while !FileManager.default.fileExists(atPath: stop), !observer.outcome.0,
                  ProcessInfo.processInfo.systemUptime - start < 60 {
                try await Task.sleep(for: .milliseconds(100))
            }
            try await stream.stopCapture()
            for _ in 0..<100 where !observer.outcome.0 { try await Task.sleep(for: .milliseconds(100)) }
            try observer.writeSamples(to: output.appendingPathExtension("samples.json"))
            if let error = observer.outcome.1 { throw CaptureError.message(error) }
            guard observer.outcome.0 else { throw CaptureError.message("Native recording did not finalize") }
            print("Native window recording finalized without retiming or frame replacement")
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(1)
        }
    }
    enum CaptureError: Error { case message(String) }
}

