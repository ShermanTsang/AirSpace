public struct MoveNodeToWorkspaceCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public static let parser: CmdParser<Self> = .init(
        kind: .moveNodeToWorkspace,
        help: move_node_to_workspace_help_generated,
        flags: [
            "--wrap-around": ArgParser(\._wrapAround, constSubArgParserFun(true)),
            "--create-on": singleValueSubArgParser(\._createOn, WorkspaceCreationTarget.unionLiteral, parseWorkspaceCreationTarget),
            "--fail-if-noop": trueBoolFlag(\.failIfNoop),
            "--window-id": windowIdSubArgParser(),
            "--focus-follows-window": ArgParser(\.focusFollowsWindow, constSubArgParserFun(true)),

            "--stdin": ArgParser(\.commonState.explicitStdinFlag, constSubArgParserFun(true)),
            "--no-stdin": ArgParser(\.commonState.explicitStdinFlag, constSubArgParserFun(false)),
        ],
        posArgs: [
            doubleDashArg(mandatory: false),
            newMandatoryPosArgParser(\.target, parseWorkspaceTarget, placeholder: workspaceTargetPlaceholder),
        ],
        conflictingFlags: [
            ["--stdin", "--no-stdin"],
        ],
    )

    public var _wrapAround: Bool?
    public var _createOn: WorkspaceCreationTarget?
    public var failIfNoop: Bool = false
    public var focusFollowsWindow: Bool = false
    public var target: Lateinit<WorkspaceTarget> = .uninitialized

    public init(rawArgs: StrArrSlice) {
        self.commonState = .init(rawArgs)
    }
}

extension MoveNodeToWorkspaceCmdArgs {
    public var wrapAround: Bool { _wrapAround ?? false }
    public var useStdin: Bool { commonState.explicitStdinFlag ?? false }

    /// Where to place the target workspace. A workspace that doesn't exist yet is created there;
    /// an existing workspace that is still effectively empty and hidden is moved there before the
    /// window is bound. Only affects `<workspace-name>`; `(next|prev)` never creates or moves workspaces.
    public var createOn: WorkspaceCreationTarget { _createOn ?? .focused }
}

func parseMoveNodeToWorkspaceCmdArgs(_ args: StrArrSlice) -> ParsedCmd<MoveNodeToWorkspaceCmdArgs> {
    parseSpecificCmdArgs(MoveNodeToWorkspaceCmdArgs(rawArgs: args), args)
        .filter("--wrapAround requires using (prev|next) argument") { ($0._wrapAround != nil).implies($0.target.val.isRelatve) }
        .filterNot("--fail-if-noop is incompatible with (next|prev)") { $0.failIfNoop && $0.target.val.isRelatve }
        .filterNot("--window-id is incompatible with (next|prev)") { $0.windowId != nil && $0.target.val.isRelatve }
        .filterNot("--create-on is incompatible with \(NextPrev.unionLiteral)") { $0._createOn != nil && $0.target.val.isRelatve }
        .filter("--stdin and --no-stdin require using \(NextPrev.unionLiteral) argument") { ($0.commonState.explicitStdinFlag != nil).implies($0.target.val.isRelatve) }
}
