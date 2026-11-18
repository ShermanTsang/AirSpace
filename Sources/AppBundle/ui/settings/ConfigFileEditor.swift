import Common
import Foundation
import SwiftUI

/// Writes the edited values to the user's config file (surgically, preserving comments and
/// advanced settings) and applies them via the regular config reload pipeline
@MainActor
enum ConfigFileEditor {
    enum EditError: LocalizedError {
        case ambiguousConfigLocation(candidates: [URL])
        case readFailure(URL, underlying: String)
        case writeFailure(URL, underlying: String)
        case patcherFailure(String)
        case reloadFailed(String)

        var errorDescription: String? {
            switch self {
                case .ambiguousConfigLocation(let candidates):
                    "AeroSpace can't decide which config file to edit: \(candidates.map(\.path).joined(separator: ", ")). Remove all but one of them."
                case .readFailure(let url, let underlying):
                    "Can't read \(url.path): \(underlying)"
                case .writeFailure(let url, let underlying):
                    "Can't write \(url.path): \(underlying)"
                case .patcherFailure(let description):
                    "Can't patch the config file: \(description)"
                case .reloadFailed(let description):
                    description.isEmpty ? "AeroSpace failed to apply the new config" : description
            }
        }
    }

    static func applyEdits(_ edits: [TomlPatcher.Edit]) async throws {
        let url = try resolveConfigUrl()
        let raw: String
        do {
            raw = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw EditError.readFailure(url, underlying: error.localizedDescription)
        }
        let patched: String
        do {
            patched = try TomlPatcher.apply(edits: edits, to: raw)
        } catch {
            throw EditError.patcherFailure("\(error)")
        }
        if patched != raw {
            do {
                try patched.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                throw EditError.writeFailure(url, underlying: error.localizedDescription)
            }
        }
        let reloadResult = await reloadConfig_nonCancellable()
        if !reloadResult.isOk {
            throw EditError.reloadFailed(reloadResult.stdout.trim())
        }
    }

    /// The config file that the user actually edits. When there is no custom config yet,
    /// the default one is copied to `~/.aerospace.toml`, exactly like "Open config in editor" does
    private static func resolveConfigUrl() throws -> URL {
        switch findCustomConfigUrl() {
            case .file(let url):
                return url
            case .noCustomConfigExists:
                let fallback = FileManager.default.homeDirectoryForCurrentUser
                    .appending(path: configDotfileName)
                do {
                    try FileManager.default.copyItem(at: defaultConfigUrl, to: fallback)
                } catch let error as CocoaError where error.code == .fileWriteFileExists {
                    // Someone created the file in the meantime. Use it as is
                } catch {
                    throw EditError.writeFailure(fallback, underlying: error.localizedDescription)
                }
                return fallback
            case .ambiguousConfigError(let candidates):
                throw EditError.ambiguousConfigLocation(candidates: candidates)
        }
    }
}

extension DynamicConfigValue {
    /// `nil` for a per-monitor value. Such values are too advanced for the visual editor
    /// and are left untouched in the config file
    var constantValue: Value? {
        if case .constant(let value) = self { return value }
        return nil
    }
}
