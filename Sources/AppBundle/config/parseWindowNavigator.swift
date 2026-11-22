private let menuBarParserTable: [String: any ParserProtocol<MenuBarConfig>] = [
    "compact": Parser(\.compact, parseBool),
]

func parseMenuBar(_ rawConfig: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> MenuBarConfig {
    parseNonEmptyTable(rawConfig, MenuBarConfig(), menuBarParserTable, backtrace, &c)
}

private let windowNavigatorParserTable: [String: any ParserProtocol<WindowNavigatorConfig>] = [
    "enabled": Parser(\.enabled, parseBool),
    "position": Parser(\.position, parseWindowNavigatorPosition),
]

func parseWindowNavigator(_ rawConfig: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> WindowNavigatorConfig {
    parseNonEmptyTable(rawConfig, WindowNavigatorConfig(), windowNavigatorParserTable, backtrace, &c)
}

private func parseWindowNavigatorPosition(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<WindowNavigatorPosition> {
    parseString(raw, backtrace).flatMap {
        WindowNavigatorPosition(rawValue: $0)
            .toResult(.init(backtrace, "Can't parse window navigator position '\($0)'"))
    }
}
