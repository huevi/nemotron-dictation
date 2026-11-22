import CryptoKit
import Foundation

final class ModelAssets: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let filename = "nemotron-labs-unified-asr-0.6b-q8_0.gguf"
    static let source = URL(string: "https://huggingface.co/mudler/parakeet-cpp-gguf/resolve/07a08a3a405d20c5434b9a1442f6e6cf571f57ad/" + filename)!
    private static let byteCount: Int64 = 939_228_800
    private static let sha256 = "655b4cd140d82f78d5aede71a0342cb92207a80c543ab8dc646c2d3edaaf0c09"

    private static var cacheFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nemotron Dictation/Models", isDirectory: true)
            .appendingPathComponent(filename)
    }

    static var installedModel: URL? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("model.gguf")
        if let bundled, hasExpectedSize(bundled) { return bundled }
        return hasExpectedSize(cacheFile) ? cacheFile : nil
    }

    private static func hasExpectedSize(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        return values?.isRegularFile == true && values?.fileSize == Int(byteCount)
    }

    enum State: Sendable {
        case downloading(Double)
        case verifying
        case finished
        case failed(String)
    }

    private enum DownloadError: LocalizedError {
        case server(Int), invalidFile
        var errorDescription: String? {
            switch self {
            case .server(let status): return "The model server returned HTTP \(status)."
            case .invalidFile: return "The model download did not match the expected size or checksum."
            }
        }
    }

    private let report: @MainActor @Sendable (State) -> Void

    init(report: @escaping @MainActor @Sendable (State) -> Void) {
        self.report = report
    }

    private func emit(_ state: State) {
        DispatchQueue.main.async { self.report(state) }
    }

    func start() {
        emit(.downloading(0))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        session.downloadTask(with: Self.source).resume()
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        emit(.downloading(min(1, Double(totalBytesWritten) / Double(Self.byteCount))))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw DownloadError.server(status) }
            emit(.verifying)
            guard Self.hasExpectedSize(location) else { throw DownloadError.invalidFile }
            let handle = try FileHandle(forReadingFrom: location)
            defer { try? handle.close() }
            var digest = SHA256()
            while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
                digest.update(data: data)
            }
            let hex = digest.finalize().map { String(format: "%02x", $0) }.joined()
            guard hex == Self.sha256 else { throw DownloadError.invalidFile }

            let files = FileManager.default
            let target = Self.cacheFile
            let directory = target.deletingLastPathComponent()
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            let pending = directory.appendingPathComponent(".\(UUID().uuidString).download")
            defer { try? files.removeItem(at: pending) }
            try files.moveItem(at: location, to: pending)
            if files.fileExists(atPath: target.path) {
                _ = try files.replaceItemAt(target, withItemAt: pending)
            } else {
                try files.moveItem(at: pending, to: target)
            }
            emit(.finished)
        } catch {
            emit(.failed(error.localizedDescription))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { emit(.failed(error.localizedDescription)) }
    }
}
