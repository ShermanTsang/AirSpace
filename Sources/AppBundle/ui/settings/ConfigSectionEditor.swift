import AppKit
import SwiftUI

struct ConfigSectionButton: View {
    let section: ConfigSection
    @State private var isPresented = false

    var body: some View {
        Button(section.title + "…") { isPresented = true }
            .sheet(isPresented: $isPresented) { ConfigSectionEditor(section: section) }
    }
}

private struct ConfigSectionEditor: View {
    let section: ConfigSection
    @Environment(\.dismiss) private var dismiss
    @State private var original: ConfigFileEditor.SectionSnapshot?
    @State private var draft: OrderedJson?
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title).font(.title2.bold())
            Text(section.help).foregroundStyle(.secondary)
            Form {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                if original != nil {
                    Toggle("Set this option", isOn: Binding(
                        get: { draft != nil },
                        set: { draft = $0 ? original?.value ?? section.schema.initial : nil },
                    ))
                    if draft != nil {
                        ConfigFieldEditor(title: section.title, schema: section.schema, value: Binding(
                            get: { draft ?? section.schema.initial }, set: { draft = $0 },
                        ))
                    }
                    Text("Saving may reformat this section and remove comments attached to its values. Other sections are left untouched.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .disabled(isSaving)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(isSaving)
                Button("Save & Apply", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving || original == nil || draft == original?.value)
            }
        }
        .padding(20)
        .frame(minWidth: 560, idealWidth: 680, minHeight: 440, idealHeight: 560)
        .interactiveDismissDisabled(isSaving)
        .task {
            do {
                let snapshot = try ConfigFileEditor.readSection(section.id)
                original = snapshot
                draft = snapshot.value
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func save() {
        guard let original, !isSaving else { return }
        isSaving = true
        let value = draft
        Task {
            defer { isSaving = false }
            do {
                try await ConfigFileEditor.saveSection(section.id, value: value, original: original)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct ConfigFieldEditor: View {
    let title: String
    let schema: ConfigFieldSchema
    @Binding var value: OrderedJson

    var body: some View {
        if schema.matches(value) {
            editor
        } else {
            LabeledContent(title, value: "Unexpected value type: \(value.tomlType.rawValue)")
            Button("Replace with default value") { value = schema.initial }
        }
    }

    @ViewBuilder private var editor: some View {
        switch schema {
            case .text:
                TextField(title, text: Binding(get: { value.asStringOrNil ?? "" }, set: { value = .string($0) }))
            case .applicationID:
                TextField(title, text: Binding(get: { value.asStringOrNil ?? "" }, set: { value = .string($0) }))
                Menu("Choose Running Application") {
                    ForEach(runningApplications, id: \.id) { app in
                        Button(app.name) { value = .string(app.id) }
                    }
                }
            case .integer:
                TextField(title, value: Binding(get: { value.asInt64OrNil ?? 0 }, set: { value = .int($0) }), format: .number.grouping(.never))
            case .toggle:
                Toggle(title, isOn: Binding(get: { value.asBoolOrNil ?? false }, set: { value = .bool($0) }))
            case .options(let options):
                Picker(title, selection: Binding(get: { value.asStringOrNil ?? "" }, set: { value = .string($0) })) {
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                    if let current = value.asStringOrNil, !options.contains(current) { Text(current).tag(current) }
                }
            case .fields(let fields, _):
                ForEach(fields) { field in
                    if value.asDictOrNil?[field.id] != nil {
                        ConfigFieldEditor(title: field.title, schema: field.schema, value: dictionaryBinding(field.id, fallback: field.schema.initial))
                    }
                }
                Menu("Optional Fields") {
                    ForEach(fields) { field in
                        Toggle(field.title, isOn: Binding(
                            get: { value.asDictOrNil?[field.id] != nil },
                            set: { setKey(field.id, to: $0 ? field.schema.initial : nil) },
                        ))
                    }
                }
            case .map(let keyLabel, let item, let initialKey):
                let keys = value.asDictOrNil.map { Array($0.keys) } ?? []
                ForEach(keys, id: \.self) { key in
                    DisclosureGroup(key) {
                        ConfigFieldEditor(title: "Value", schema: item, value: dictionaryBinding(key, fallback: item.initial))
                        ConfigMapRenameButton(keyLabel: keyLabel, key: key, usedKeys: Set(keys)) { newKey in
                            guard let old = value.asDictOrNil?[key] else { return }
                            setKey(key, to: nil)
                            setKey(newKey, to: old)
                        }
                        Button("Remove \(keyLabel)", role: .destructive) { setKey(key, to: nil) }
                    }
                }
                Button("Add \(keyLabel)") {
                    var key = initialKey
                    var suffix = 2
                    while keys.contains(key) {
                        key = "\(initialKey)\(suffix)"
                        suffix += 1
                    }
                    setKey(key, to: item.initial)
                }
            case .list(let itemTitle, let item):
                ConfigListEditor(itemTitle: itemTitle, item: item, items: Binding(
                    get: { value.asArrayOrNil ?? [] }, set: { value = .array($0) },
                ))
            case .choice(let choices):
                let index = choices.firstIndex { $0.schema.matches(value) } ?? 0
                Picker(title, selection: Binding(get: { index }, set: { value = choices[$0].schema.initial })) {
                    ForEach(choices.indices, id: \.self) { Text(choices[$0].title).tag($0) }
                }
                if choices.indices.contains(index) {
                    let choice = choices[index]
                    ConfigFieldEditor(title: choice.title, schema: choice.schema, value: $value)
                }
            case .gap:
                ConfigGapEditor(title: title, value: $value)
        }
    }

    private var runningApplications: [(id: String, name: String)] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier, seen.insert(id).inserted else { return nil }
            return (id: id, name: app.localizedName ?? id)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func setKey(_ key: String, to newValue: OrderedJson?) {
        guard var dict = value.asDictOrNil else { return }
        dict[key] = newValue
        value = .dict(dict)
    }

    private func dictionaryBinding(_ key: String, fallback: OrderedJson) -> Binding<OrderedJson> {
        Binding(get: { value.asDictOrNil?[key] ?? fallback }, set: { setKey(key, to: $0) })
    }
}

private struct ConfigListEditor: View {
    let itemTitle: String
    let item: ConfigFieldSchema
    @Binding var items: [OrderedJson]

    var body: some View {
        ForEach(items.indices, id: \.self) { index in
            DisclosureGroup("\(itemTitle) \(index + 1)") {
                ConfigFieldEditor(title: itemTitle, schema: item, value: Binding(
                    get: { items.indices.contains(index) ? items[index] : item.initial },
                    set: { if items.indices.contains(index) { items[index] = $0 } },
                ))
                HStack {
                    Button("Move Up") { move(index, to: index - 1) }.disabled(index == items.startIndex)
                    Button("Move Down") { move(index, to: index + 1) }.disabled(index + 1 == items.endIndex)
                    Spacer()
                    Button("Remove", role: .destructive) {
                        if items.indices.contains(index) { items.remove(at: index) }
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        Button("Add \(itemTitle)") { items.append(item.initial) }
    }

    private func move(_ index: Int, to destination: Int) {
        guard items.indices.contains(index), items.indices.contains(destination) else { return }
        items.swapAt(index, destination)
    }
}

private struct ConfigMapRenameButton: View {
    let keyLabel: String
    let key: String
    let usedKeys: Set<String>
    let rename: (String) -> Void
    @State private var isPresented = false
    @State private var newKey = ""

    var body: some View {
        Button("Rename \(keyLabel)…") {
            newKey = key
            isPresented = true
        }
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading) {
                TextField(keyLabel, text: $newKey)
                Button("Rename") {
                    isPresented = false
                    rename(newKey)
                }
                .disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || usedKeys.contains(newKey))
            }
            .padding()
            .frame(width: 260)
        }
    }
}

private struct ConfigGapEditor: View {
    let title: String
    @Binding var value: OrderedJson

    private let override = ConfigFieldSchema.fields([
        .init("monitor", "Monitor selector", .map("Monitor pattern", .integer(0), initialKey: "main")),
    ], defaults: ["monitor"])

    var body: some View {
        DisclosureGroup(title) {
            Toggle("Use monitor overrides", isOn: Binding(
                get: { value.asArrayOrNil != nil },
                set: { enabled in
                    let fallback = fallbackValue
                    value = enabled ? .array([override.initial, fallback]) : fallback
                },
            ))
            ConfigFieldEditor(title: value.asArrayOrNil == nil ? "Pixels" : "Fallback (pixels)", schema: .integer(0), value: Binding(
                get: { fallbackValue },
                set: { newValue in
                    if let array = value.asArrayOrNil { value = .array(Array(array.dropLast()) + [newValue]) } else { value = newValue }
                },
            ))
            if value.asArrayOrNil != nil {
                ConfigListEditor(itemTitle: "Monitor Override", item: override, items: Binding(
                    get: { Array((value.asArrayOrNil ?? []).dropLast()) },
                    set: { value = .array($0 + [fallbackValue]) },
                ))
            }
        }
    }

    private var fallbackValue: OrderedJson { value.asArrayOrNil?.last ?? (value.asInt64OrNil == nil ? .int(0) : value) }
}
