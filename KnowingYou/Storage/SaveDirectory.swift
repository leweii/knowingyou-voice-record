import Foundation

/// Default path, writability, and disk-usage helpers for the recordings
/// folder (G9). File naming rules for individual recordings live in
/// `RecordingNaming` (S10), not here.
enum SaveDirectory {
    static func ensureExists(at path: String) throws {
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
            if !isDirectory.boolValue {
                throw KYError.saveDirectoryUnwritable(url)
            }
            return
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func isWritable(at path: String) -> Bool {
        FileManager.default.isWritableFile(atPath: path)
    }

    /// Sums file sizes recursively. Runs on a background thread; call from a `Task`.
    static func directorySize(at path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else {
                continue
            }
            total += Int64(size)
        }
        return total
    }

    static func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Middle-truncated for display next to the "更改…" button (G9), e.g.
    /// `/Users/jakob/.../知鱼录音`.
    static func displayPath(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
