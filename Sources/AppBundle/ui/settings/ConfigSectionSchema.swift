import Foundation

struct ConfigSection: Identifiable, Sendable {
    let id: String
    let title: String
    let help: String
    let schema: ConfigFieldSchema

    static let windowRules = ConfigSection(
        id: "on-window-detected", title: "Application Window Rules",
        help: "Rules run in order when a new window is detected. Move more specific rules above broader rules.",
        schema: .list("Rule", .fields([
            .init("if", "Match", .choice([
                .init("Application and window filters", .fields([
                    .init("app-id", "Application bundle ID", .applicationID),
                    .init("app-name-regex-substring", "Application name pattern", .text("")),
                    .init("window-title-regex-substring", "Window title pattern", .text("")),
                    .init("workspace", "Workspace", .text("")),
                    .init("during-aerospace-startup", "During AeroSpace startup", .toggle(true)),
                ], defaults: ["app-id"])),
                .init("Condition command", .text("true")),
            ])),
            .init("run", "Action", .commands("layout floating")),
            .init("check-further-callbacks", "Continue matching rules", .toggle(false)),
        ], defaults: ["if", "run"])),
    )

    static let shortcuts: [ConfigSection] = [
        .init(id: "mode", title: "Keyboard Shortcuts", help: "The main mode is required. Add bindings using key names such as alt-h and AirSpace commands such as focus left.",
              schema: .map("Mode name", .fields([
                  .init("binding", "Bindings", .map("Shortcut", .commands("focus left"), initialKey: "alt-h")),
              ], defaults: ["binding"]), initialKey: "main")),
        .init(id: "key-mapping", title: "Keyboard Layout", help: "Select a keyboard layout preset or override individual key names.",
              schema: .fields([
                  .init("preset", "Preset", .options(KeyMapping.Preset.allCases.map(\.rawValue))),
                  .init("key-notation-to-key-code", "Key overrides", .map("Key name", .text(""), initialKey: "key")),
              ], defaults: ["preset"])),
    ]

    static let workspaces: [ConfigSection] = [
        .init(id: "persistent-workspaces", title: "Persistent Workspaces", help: "Keep these workspaces even when empty. Requires config version 2.", schema: .list("Workspace", .text(""))),
        .init(id: "workspace-to-monitor-force-assignment", title: "Workspace Monitor Assignments", help: "Use a monitor number, main, secondary, or a name pattern. For multiple choices, the first matching monitor is used.",
              schema: .map("Workspace", .choice([
                  .init("Monitor name or pattern", .text("main")),
                  .init("Monitor number", .integer(1)),
                  .init("Ordered fallback list", .list("Monitor", .choice([
                      .init("Name or pattern", .text("main")),
                      .init("Number", .integer(1)),
                  ]))),
              ]), initialKey: "1")),
    ]

    static let automation: [ConfigSection] = [
        .init(id: "after-startup-command", title: "After Startup", help: "AirSpace commands run after the app starts.", schema: .commands("")),
        .init(id: "on-focus-changed", title: "On Focus Change", help: "AirSpace commands run when focus changes.", schema: .commands("")),
        .init(id: "on-focused-monitor-changed", title: "On Focused Monitor Change", help: "AirSpace commands run when the focused monitor changes.", schema: .commands("")),
        .init(id: "on-mode-changed", title: "On Mode Change", help: "AirSpace commands run when the binding mode changes.", schema: .commands("")),
        .init(id: "exec-on-workspace-change", title: "On Workspace Change", help: "Enter the absolute executable path first, then one argument per entry.", schema: .list("Argument", .text(""))),
        .init(id: "exec", title: "Command Environment", help: "Set environment variables for commands launched by AirSpace.", schema: .fields([
            .init("inherit-env-vars", "Inherit environment variables", .toggle(true)),
            .init("env-vars", "Variable overrides", .map("Variable name", .text(""), initialKey: "VARIABLE")),
        ], defaults: ["inherit-env-vars"])),
    ]

    static let gaps = ConfigSection(id: "gaps", title: "Gaps by Monitor", help: "Each gap can use a single value or an ordered list of monitor overrides and a fallback, in pixels.", schema: .fields([
        .init("inner", "Inner gaps", .fields([
            .init("vertical", "Vertical", .gap), .init("horizontal", "Horizontal", .gap),
        ], defaults: ["vertical", "horizontal"])),
        .init("outer", "Outer gaps", .fields([
            .init("left", "Left", .gap), .init("top", "Top", .gap),
            .init("bottom", "Bottom", .gap), .init("right", "Right", .gap),
        ], defaults: ["left", "top", "bottom", "right"])),
    ], defaults: ["inner", "outer"]))

    static let version = ConfigSection(id: "config-version", title: "Configuration Version", help: "Changing the version changes how AirSpace interprets existing settings. It does not migrate existing settings.", schema: .integer(2))
}

indirect enum ConfigFieldSchema: Sendable {
    case text(String)
    case applicationID
    case integer(Int64)
    case toggle(Bool)
    case options([String])
    case fields([Field], defaults: [String])
    case map(String, ConfigFieldSchema, initialKey: String)
    case list(String, ConfigFieldSchema)
    case choice([Choice])
    case gap

    struct Field: Identifiable, Sendable {
        let id: String
        let title: String
        let schema: ConfigFieldSchema

        init(_ id: String, _ title: String, _ schema: ConfigFieldSchema) {
            self.id = id
            self.title = title
            self.schema = schema
        }
    }

    struct Choice: Sendable {
        let title: String
        let schema: ConfigFieldSchema

        init(_ title: String, _ schema: ConfigFieldSchema) {
            self.title = title
            self.schema = schema
        }
    }

    static func commands(_ example: String) -> Self {
        .choice([.init("Single command", .text(example)), .init("Command list", .list("Command", .text(example)))])
    }

    var initial: OrderedJson {
        switch self {
            case .text(let value): .string(value)
            case .applicationID: .string("")
            case .integer(let value): .int(value)
            case .toggle(let value): .bool(value)
            case .options(let options): .string(options.first ?? "")
            case .fields(let fields, let defaults): .dict(.init(uniqueKeysWithValues: fields.filter { defaults.contains($0.id) }.map { ($0.id, $0.schema.initial) }))
            case .map(_, let schema, let key): .dict([key: schema.initial])
            case .list: .array([])
            case .choice(let choices): choices.first?.schema.initial ?? .null
            case .gap: .int(0)
        }
    }

    func matches(_ value: OrderedJson) -> Bool {
        switch (self, value) {
            case (.text, .string), (.options, .string), (.applicationID, .string), (.integer, .int), (.toggle, .bool),
                 (.fields, .dict), (.map, .dict), (.list, .array), (.gap, .int), (.gap, .array): true
            case (.choice(let choices), _): choices.contains { $0.schema.matches(value) }
            default: false
        }
    }
}
