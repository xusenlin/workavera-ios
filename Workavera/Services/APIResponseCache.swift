import CryptoKit
import Foundation

enum DataLoadStrategy: Equatable {
    case cacheOnly
    case networkOnly
}

final class APIResponseCache: @unchecked Sendable {
    static let shared = APIResponseCache()

    private let directory: URL
    private let lock = NSLock()

    init(directory: URL? = nil) {
        let baseDirectory = directory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.directory = baseDirectory.appending(path: "WorkaveraAPIResponses", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(
            at: self.directory,
            withIntermediateDirectories: true
        )
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: self.directory.path
        )
    }

    func data(for key: String) -> Data? {
        lock.withLock {
            try? Data(contentsOf: fileURL(for: key), options: .mappedIfSafe)
        }
    }

    func store(_ data: Data, for key: String) {
        lock.withLock {
            try? data.write(to: fileURL(for: key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    func removeValue(for key: String) {
        lock.withLock {
            try? FileManager.default.removeItem(at: fileURL(for: key))
        }
    }

    private func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let fileName = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: fileName, directoryHint: .notDirectory)
    }
}
