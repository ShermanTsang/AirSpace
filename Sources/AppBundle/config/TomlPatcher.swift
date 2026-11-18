import Foundation

/// Comment-preserving patcher for TOML config files.
///
/// Unlike a full TOML serializer it doesn't rebuild the document from a parsed model.
/// Instead it performs surgical, line-based edits: only the assignments being modified are
/// rewritten; every other byte of the file (comments, formatting, ordering, unknown keys,
/// advanced constructs) is preserved as is.
///
/// Supported TOML subset (enough for AeroSpace config files):
///  - comments (`#`) outside of strings;
///  - tables defined via `[dotted.header]` with bare keys. Headers with quoted keys and
///    arrays of tables (`[[header]]`) make the region opaque: assignments inside can't be
///    edited, but they are never corrupted;
///  - assignments with bare keys, dotted or plain, e.g. `inner.vertical = 8`;
///  - single-line and multi-line values (arrays, multiline strings). A replaced value is
///    always written back as a single line.
enum TomlPatcher {
    struct Edit: Equatable, Sendable {
        /// Dotted key path relative to the root table, e.g. `["gaps", "inner", "vertical"]`
        let path: [String]
        /// TOML literal for the new value, e.g. `true`, `42`, `"tiles"`
        let value: String

        static func bool(_ path: [String], _ value: Bool) -> Edit {
            .init(path: path, value: value ? "true" : "false")
        }

        static func int(_ path: [String], _ value: Int) -> Edit {
            .init(path: path, value: value.description)
        }

        static func string(_ path: [String], _ value: String) -> Edit {
            .init(path: path, value: formatTomlString(value))
        }

        static func stringArray(_ path: [String], _ values: [String]) -> Edit {
            .init(path: path, value: "[" + values.map(formatTomlString).joined(separator: ", ") + "]")
        }
    }

    enum PatcherError: Error, Equatable, Sendable {
        /// The file already contains several assignments for the same key
        case duplicateKey(path: [String])
        /// Several edits in a single `apply` batch target the same key
        case duplicateEdit(path: [String])
        case invalidEdit(reason: String)
    }

    // MARK: public API

    /// Applies the edits to the raw TOML text and returns the new text.
    /// The file on disk is not touched.
    static func apply(edits: [Edit], to rawToml: String) throws -> String {
        var seenPaths = Set<[String]>()
        for edit in edits {
            try validate(edit)
            if !seenPaths.insert(edit.path).inserted {
                throw PatcherError.duplicateEdit(path: edit.path)
            }
        }
        var doc = Document(rawToml)
        for edit in edits {
            doc = try apply(edit, to: doc)
        }
        return doc.render()
    }

    private static func validate(_ edit: Edit) throws {
        guard !edit.path.isEmpty else {
            throw PatcherError.invalidEdit(reason: "Key path must not be empty")
        }
        for component in edit.path where !isBareKey(component) {
            throw PatcherError.invalidEdit(reason: "'\(component)' can't be expressed as a bare TOML key")
        }
    }

    // MARK: document model

    private struct Document {
        /// Line contents without newline terminators
        var lines: [[Character]]
        /// Whether the original text ended with a newline
        var hasFinalNewline: Bool

        init(_ raw: String) {
            hasFinalNewline = raw.hasSuffix("\n")
            // An empty document has no lines. (Splitting "" would produce one phantom empty line)
            guard !raw.isEmpty else {
                lines = []
                return
            }
            var split = raw.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" }).map { Array($0) }
            // "a\n" splits into ["a", ""]; drop the phantom element produced by the final separator
            if hasFinalNewline, !split.isEmpty { split.removeLast() }
            lines = split
        }

        func render() -> String {
            lines.map { String($0) }.joined(separator: "\n") + (hasFinalNewline && !lines.isEmpty ? "\n" : "")
        }
    }

    // MARK: single edit application

    private struct AssignmentRecord {
        let path: [String]
        /// Index of the line with `key =`
        let line: Int
        /// Inclusive index of the last line occupied by the value (multi-line arrays/strings)
        let endLine: Int
    }

    private struct Classification {
        /// Full dotted path (table context + key) -> record
        var assignments: [[String]: AssignmentRecord] = [:]
        /// Table path -> header line index. Opaque headers are excluded
        var headers: [[String]: Int] = [:]
        /// Lines that are headers of any kind, including opaque ones
        var headerLines: Set<Int> = []
    }

    private static func apply(_ edit: Edit, to doc: Document) throws -> Document {
        var doc = doc
        let classification = try classify(doc.lines)
        if let record = classification.assignments[edit.path] {
            try replaceAssignment(record, with: edit.value, in: &doc)
        } else {
            try insertAssignment(for: edit, classification: classification, into: &doc)
        }
        return doc
    }

    private static func classify(_ lines: [[Character]]) throws -> Classification {
        var result = Classification()
        var context: [String]? = [] // Root table. `nil` inside an opaque region
        var i = 0
        while i < lines.count {
            if let headerScan = scanHeader(lines[i]) {
                result.headerLines.insert(i)
                switch headerScan {
                    case .header(let path):
                        if result.headers[path] != nil {
                            throw PatcherError.duplicateKey(path: path)
                        }
                        result.headers[path] = i
                        context = path
                    case .opaqueHeader:
                        context = nil
                }
                i += 1
            } else if context != nil, let record = scanAssignment(lines[i], context: context!, lineIndex: i, lines: lines) {
                if result.assignments[record.path] != nil {
                    throw PatcherError.duplicateKey(path: record.path)
                }
                result.assignments[record.path] = record
                i = record.endLine + 1
            } else {
                i += 1
            }
        }
        return result
    }

    private static func replaceAssignment(_ record: AssignmentRecord, with value: String, in doc: inout Document) throws {
        let chars = doc.lines[record.line]
        guard let (_, afterKey) = scanDottedBareKey(chars, from: 0) else {
            throw PatcherError.invalidEdit(reason: "Can't re-scan the assignment on line \(record.line + 1)")
        }
        let eqIndex = skipWhitespace(chars, from: afterKey)
        guard eqIndex < chars.count, chars[eqIndex] == "=" else {
            throw PatcherError.invalidEdit(reason: "Can't re-scan the assignment on line \(record.line + 1)")
        }
        var prefix = String(chars[..<eqIndex])
        while prefix.hasSuffix(" ") || prefix.hasSuffix("\t") { prefix.removeLast() }

        let valueScan = scanValue(doc.lines, valueLine: record.line, valueStart: eqIndex + 1)
        var newLine = prefix + " = " + value
        if let commentStart = valueScan.commentStart {
            let comment = String(doc.lines[valueScan.endLine][commentStart...])
            newLine += " " + comment
        }
        doc.lines[record.line] = Array(newLine)
        if valueScan.endLine > record.line {
            doc.lines.removeSubrange((record.line + 1)...valueScan.endLine)
        }
    }

    private static func insertAssignment(for edit: Edit, classification c: Classification, into doc: inout Document) throws {
        let path = edit.path
        let key = path.last!

        // 1. The exact parent table exists -> append a plain key assignment to its body
        if path.count >= 2, let headerLine = c.headers[Array(path.dropLast())] {
            let insertAt = insertionIndex(inBodyOf: Array(path.dropLast()), headerLine: headerLine, classification: c, doc: doc)
            doc.lines.insert(Array(bodyIndent(headerLine: headerLine, classification: c, doc: doc) + key + " = " + edit.value), at: insertAt)
            return
        }
        // 2. Some ancestor table exists -> append a dotted key assignment, e.g. `inner.vertical = 8` in `[gaps]`
        for prefixLength in stride(from: path.count - 2, through: 1, by: -1) {
            let prefix = Array(path.prefix(prefixLength))
            guard let headerLine = c.headers[prefix] else { continue }
            // A dotted key would implicitly (re)define the next path component. Bail out if it's already
            // defined as a plain value (e.g. an inline table) to never produce invalid TOML
            if c.assignments[prefix + [path[prefixLength]]] != nil {
                throw PatcherError.invalidEdit(
                    reason: "Can't insert '\(path.joined(separator: "."))' because '\((prefix + [path[prefixLength]]).joined(separator: "."))' is already defined as a value",
                )
            }
            let insertAt = insertionIndex(inBodyOf: prefix, headerLine: headerLine, classification: c, doc: doc)
            let dottedKey = path.suffix(from: prefixLength).joined(separator: ".")
            doc.lines.insert(Array(bodyIndent(headerLine: headerLine, classification: c, doc: doc) + dottedKey + " = " + edit.value), at: insertAt)
            return
        }
        // 3. No ancestor table exists
        if path.count == 1 {
            let insertAt = rootInsertionIndex(classification: c, doc: doc)
            doc.lines.insert(Array(key + " = " + edit.value), at: insertAt)
        } else {
            // Create a brand-new table at the end of the document.
            // (A root-level dotted key would implicitly define the table and forbid the user from
            // opening it with a regular `[header]` later, so a real header is created instead)
            if let last = doc.lines.last, !last.allSatisfy({ $0 == " " || $0 == "\t" }) {
                doc.lines.append([])
            }
            doc.lines.append(Array("[" + path.dropLast().joined(separator: ".") + "]"))
            doc.lines.append(Array(key + " = " + edit.value))
        }
    }

    // MARK: insertion positions

    /// Index just after the last assignment of the table body; falls back to right after the header
    /// (skipping comment lines that directly follow the header and belong to it)
    private static func insertionIndex(inBodyOf table: [String], headerLine: Int, classification c: Classification, doc: Document) -> Int {
        let bodyEnd = c.headerLines
            .filter { $0 > headerLine }
            .min() ?? doc.lines.count
        let lastAssignmentEnd = c.assignments.values
            .filter { $0.line > headerLine && $0.line < bodyEnd }
            .map { $0.endLine }
            .max()
        if let lastAssignmentEnd {
            return lastAssignmentEnd + 1
        }
        var i = headerLine + 1
        while i < bodyEnd, doc.lines[i].first(where: { $0 != " " && $0 != "\t" }) == "#" {
            i += 1
        }
        return i
    }

    private static func rootInsertionIndex(classification c: Classification, doc: Document) -> Int {
        let bodyEnd = c.headerLines.min() ?? doc.lines.count
        let lastAssignmentEnd = c.assignments.values
            .filter { $0.line < bodyEnd }
            .map { $0.endLine }
            .max()
        // When the root table has no assignments, insert at the very top of the file
        return (lastAssignmentEnd ?? -1) + 1
    }

    /// Indent to mirror for a new assignment: the indent of the first assignment in the body
    private static func bodyIndent(headerLine: Int, classification c: Classification, doc: Document) -> String {
        let bodyEnd = c.headerLines
            .filter { $0 > headerLine }
            .min() ?? doc.lines.count
        let firstAssignment = c.assignments.values
            .filter { $0.line > headerLine && $0.line < bodyEnd }
            .min { $0.line < $1.line }
        guard let firstAssignment else { return "" }
        let chars = doc.lines[firstAssignment.line]
        var indent = ""
        for char in chars {
            guard char == " " || char == "\t" else { break }
            indent.append(char)
        }
        return indent
    }

    // MARK: line scanners

    private enum HeaderScan {
        /// A regular `[a.b.c]` header
        case header(path: [String])
        /// A header whose path can't be modeled (quoted keys, `[[array-of-tables]]`).
        /// Assignments below it are ignored, and edits never go into its body
        case opaqueHeader
    }

    /// Outer `nil` means the line is not a header at all. Arrays of tables are reported opaque:
    /// several `[[t]]` headers share the same path, which the patcher doesn't model
    private static func scanHeader(_ chars: [Character]) -> HeaderScan? {
        var i = skipWhitespace(chars, from: 0)
        guard i < chars.count, chars[i] == "[" else { return nil }
        i += 1
        let isArray = i < chars.count && chars[i] == "["
        if isArray { i += 1 }
        i = skipWhitespace(chars, from: i)
        guard let (path, afterKey) = scanDottedBareKey(chars, from: i) else { return nil }
        i = skipWhitespace(chars, from: afterKey)
        guard i < chars.count, chars[i] == "]" else { return nil }
        i += 1
        if isArray {
            guard i < chars.count, chars[i] == "]" else { return nil }
            i += 1
        }
        i = skipWhitespace(chars, from: i)
        guard i >= chars.count || chars[i] == "#" else { return nil }
        return isArray ? .opaqueHeader : .header(path: path)
    }

    private static func scanAssignment(_ chars: [Character], context: [String], lineIndex: Int, lines: [[Character]]) -> AssignmentRecord? {
        guard let (keyComponents, afterKey) = scanDottedBareKey(chars, from: 0) else { return nil }
        var i = skipWhitespace(chars, from: afterKey)
        guard i < chars.count, chars[i] == "=" else { return nil }
        i += 1
        let valueScan = scanValue(lines, valueLine: lineIndex, valueStart: i)
        return AssignmentRecord(path: context + keyComponents, line: lineIndex, endLine: valueScan.endLine)
    }

    /// Scans a bare dotted key like `gaps.inner.vertical`. Whitespace around dots is tolerated
    private static func scanDottedBareKey(_ chars: [Character], from start: Int) -> ([String], Int)? {
        var components: [String] = []
        var i = skipWhitespace(chars, from: start)
        while true {
            let keyStart = i
            while i < chars.count, isBareKeyChar(chars[i]) { i += 1 }
            guard i > keyStart else { return nil }
            components.append(String(chars[keyStart..<i]))
            let afterKey = skipWhitespace(chars, from: i)
            if afterKey < chars.count, chars[afterKey] == "." {
                i = skipWhitespace(chars, from: afterKey + 1)
            } else {
                return (components, afterKey)
            }
        }
    }

    // MARK: value scanner

    /// Walks a value starting at (`valueLine`, `valueStart`) across lines until the value is
    /// complete. Returns the last line it occupies and, when the value is followed by an inline
    /// comment on that line, the comment's index on it
    private static func scanValue(_ lines: [[Character]], valueLine: Int, valueStart: Int) -> (endLine: Int, commentStart: Int?) {
        enum State { case code, basicString, literalString, multilineBasicString, multilineLiteralString }

        var state = State.code
        var line = valueLine
        var i = valueStart
        var arrayDepth = 0

        while line < lines.count {
            let chars = lines[line]
            // `true` once we're past this line, so the scanner can advance to the next line
            var finishLine = false

            charLoop: while i < chars.count {
                let char = chars[i]
                switch state {
                    case .code:
                        switch char {
                            case "#":
                                if arrayDepth == 0 {
                                    return (line, i)
                                }
                                finishLine = true // comment inside an unfinished array
                                break charLoop
                            case "[":
                                arrayDepth += 1
                            case "]":
                                arrayDepth = max(0, arrayDepth - 1)
                            case "\"":
                                if chars[i...].starts(with: ["\"", "\"", "\""]) {
                                    state = .multilineBasicString
                                    i += 2
                                } else {
                                    state = .basicString
                                }
                            case "'":
                                if chars[i...].starts(with: ["'", "'", "'"]) {
                                    state = .multilineLiteralString
                                    i += 2
                                } else {
                                    state = .literalString
                                }
                            default:
                                break
                        }
                    case .basicString:
                        switch char {
                            case "\\": i += 1 // skip the escaped character
                            case "\"": state = .code
                            default: break
                        }
                    case .literalString:
                        if char == "'" { state = .code }
                    case .multilineBasicString:
                        if char == "\"", chars[i...].starts(with: ["\"", "\"", "\""]) {
                            state = .code
                            i += 2
                        }
                    case .multilineLiteralString:
                        if char == "'", chars[i...].starts(with: ["'", "'", "'"]) {
                            state = .code
                            i += 2
                        }
                }
                i += 1
            }
            // End of line
            switch state {
                case .code where arrayDepth == 0 && !finishLine:
                    return (line, nil)
                default:
                    line += 1
                    i = 0
            }
        }
        return (max(0, line - 1), nil)
    }

    // MARK: primitives

    private static func skipWhitespace(_ chars: [Character], from index: Int) -> Int {
        var i = index
        while i < chars.count, chars[i] == " " || chars[i] == "\t" {
            i += 1
        }
        return i
    }

    private static func isBareKeyChar(_ char: Character) -> Bool {
        char.isLetter || char.isNumber || char == "-" || char == "_"
    }

    private static func isBareKey(_ key: String) -> Bool {
        !key.isEmpty && key.allSatisfy(isBareKeyChar)
    }

    private static func formatTomlString(_ string: String) -> String {
        var result = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
                case "\"": result += "\\\""
                case "\\": result += "\\\\"
                case "\n": result += "\\n"
                case "\r": result += "\\r"
                case "\t": result += "\\t"
                default:
                    if scalar.value < 0x20 {
                        let hex = String(scalar.value, radix: 16, uppercase: true)
                        result += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                    } else {
                        result.unicodeScalars.append(scalar)
                    }
            }
        }
        return result + "\""
    }
}
