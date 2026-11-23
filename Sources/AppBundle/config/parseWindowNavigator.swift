private let menuBarParserTable: [String: any ParserProtocol<MenuBarConfig>] = [
    "compact": Parser(\.compact, parseBool),
]

func parseMenuBar(_ rawConfig: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> MenuBarConfig {
    parseNonEmptyTable(rawConfig, MenuBarConfig(), menuBarParserTable, backtrace, &c)
}

private let windowNavigatorParserTable: [String: any ParserProtocol<WindowNavigatorConfig>] = [
    "enabled": Parser(\.enabled, parseBool),
    "size": Parser(\.size, parseWindowNavigatorSize),
    "position": Parser(\._position, parseDeprecatedWindowNavigatorPosition),
]

func parseWindowNavigator(_ rawConfig: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> WindowNavigatorConfig {
    parseNonEmptyTable(rawConfig, WindowNavigatorConfig(), windowNavigatorParserTable, backtrace, &c)
}

private func parseWindowNavigatorSize(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<WindowNavigatorSize> {
    parseString(raw, backtrace).flatMap {
        WindowNavigatorSize(rawValue: $0)
            .toResult(.init(backtrace, "Can't parse window navigator size '\($0)'. Possible values: small, medium, large"))
    }
}

/// The navigator is always floating now. Accept the legacy `position = 'floating'` silently
/// so existing configs keep loading, and point users at the removal for docked values.
private func parseDeprecatedWindowNavigatorPosition(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<Void> {
    parseString(raw, backtrace).flatMap {
        switch $0 {
            case "floating": .success(())
            default: .failure(.init(
                backtrace,
                "The window navigator is always floating. Please remove 'window-navigator.position' from the config",
            ))
        }
    }
}
