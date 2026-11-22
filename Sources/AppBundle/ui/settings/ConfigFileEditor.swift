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
        case configChanged

        var errorDescription: String? {
            switch self {
                case .ambiguousConfigLocation(let candidates):
                    "AirSpace can't decide which config file to edit: \(candidates.map(\.path).joined(separator: ", ")). Remove all but one of them."
                case .readFailure(let url, let underlying):
                    "Can't read \(url.path): \(underlying)"
                case .writeFailure(let url, let underlying):
                    "Can't write \(url.path): \(underlying)"
                case .patcherFailure(let description):
                    "Can't patch the config file: \(description)"
                case .reloadFailed(let description):
                    description.isEmpty ? "AirSpace failed to apply the new config" : description
                case .configChanged:
                    "This section or the config file location changed while you were editing it. Reopen the editor to load the latest version."
            }
        }
    }

    struct SectionSnapshot {
        let url: URL
        let value: OrderedJson?
    }

    static func readSection(_ key: String) throws -> SectionSnapshot {
        let url = try sourceUrl()
        return SectionSnapshot(url: url, value: try TomlPatcher.configTable(read(url))[key])
    }

    static func saveSection(_ key: String, value: OrderedJson?, original: SectionSnapshot) async throws {
        let url = try sourceUrl()
        guard url == original.url else { throw EditError.configChanged }
        let raw = try read(url)
        guard try TomlPatcher.configTable(raw)[key] == original.value else { throw EditError.configChanged }
        let patched = try TomlPatcher.replaceRoot(key, with: value, in: raw)
        try await validateWriteAndReload(patched, original: raw, source: url)
    }

    static func applyEdits(_ edits: [TomlPatcher.Edit]) async throws {
        let url = try sourceUrl()
        let raw = try read(url)
        let patched: String
        do {
            patched = try TomlPatcher.apply(edits: edits, to: raw)
        } catch {
            throw EditError.patcherFailure("\(error)")
        }
        try await validateWriteAndReload(patched, original: raw, source: url)
    }

    private static func read(_ url: URL) throws -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw EditError.readFailure(url, underlying: error.localizedDescription)
        }
    }

    private static func sourceUrl() throws -> URL {
        switch findCustomConfigUrl() {
            case .file(let url): return url
            case .noCustomConfigExists: return defaultConfigUrl
            case .ambiguousConfigError(let candidates): throw EditError.ambiguousConfigLocation(candidates: candidates)
        }
    }

    private static func validateWriteAndReload(_ patched: String, original: String, source: URL) async throws {
        guard patched != original else { return }
        let errors = parseConfig(patched).errors
        guard errors.isEmpty else {
            throw EditError.patcherFailure(errors.lazy.map { $0.description(.error) }.joined(separator: "\n\n"))
        }
        guard try sourceUrl() == source else { throw EditError.configChanged }
        let url = try resolveConfigUrl()
        guard try read(url) == original else { throw EditError.configChanged }
        do {
            try patched.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw EditError.writeFailure(url, underlying: error.localizedDescription)
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
