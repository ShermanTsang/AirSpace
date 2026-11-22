import Testing
@testable import AppBundle

@Suite struct TomlPatcherTest {
    @Test func rewriteWindowRulesDoesNotTouchNeighboringTables() throws {
        let prefix = "config-version = 2\n# Keep this comment\n"
        let rules = """
            [["on-window-detected"]]
            'if'.app-id = 'com.example.App'
            run = ['layout floating']

            [[on-window-detected]]
            if = 'true'
            run = 'layout tiling'

            """
        let suffix = "[mode.main.binding]\nalt-h = 'focus left' # existing binding\n"
        let raw = prefix + rules + suffix
        let oldRules = try #require(TomlPatcher.configTable(raw)["on-window-detected"]?.asArrayOrNil)
        let updated = OrderedJson.array(Array(oldRules.reversed()))
        let patched = try TomlPatcher.replaceRoot("on-window-detected", with: updated, in: raw)
        #expect(patched.hasPrefix(prefix))
        #expect(patched.hasSuffix(suffix))
        #expect(try TomlPatcher.configTable(patched)["on-window-detected"] == updated)
    }

    @Test func rewriteModeTableSupportsQuotedKeysAndEmptyBindings() throws {
        let raw = "mode.main.binding = { alt-h = 'focus left' }\n[gaps]\ninner.vertical = 8\n"
        let updated = OrderedJson.dict(["main": .dict(["binding": .dict([:])]), "my.mode": .dict(["binding": .dict([:])])])
        let patched = try TomlPatcher.replaceRoot("mode", with: updated, in: raw)
        #expect(patched.contains("[mode.\"my.mode\".binding]"))
        #expect(patched.contains("[gaps]\ninner.vertical = 8\n"))
        #expect(try TomlPatcher.configTable(patched)["mode"] == updated)
        let removed = try TomlPatcher.replaceRoot("mode", with: nil, in: patched)
        #expect(try TomlPatcher.configTable(removed)["mode"] == nil)
    }

    @Test func rewriteGapsPreservesCRLFAndUnrelatedMultilineString() throws {
        let untouched = "after-startup-command = '''\r\n[gaps]\r\nnot-a-header\r\n'''\r\n"
        let raw = untouched + "[gaps]\r\ninner.vertical = 8\r\n"
        let updated = OrderedJson.dict([
            "inner": .dict(["vertical": .array([.dict(["monitor": .dict(["Built-in.*": .int(12)])]), .int(4)])]),
        ])
        let patched = try TomlPatcher.replaceRoot("gaps", with: updated, in: raw)
        #expect(patched.hasPrefix(untouched))
        #expect(patched.allSatisfy { $0 != "\n" })
        #expect(try TomlPatcher.configTable(patched)["gaps"] == updated)
    }

    @MainActor @Test func structuredSectionsProduceValidAeroSpaceConfiguration() throws {
        var raw = "config-version = 2\n"
        let edits: [(String, OrderedJson)] = [
            ("on-window-detected", .array([.dict([
                "if": .dict(["app-id": .string("com.apple.Safari")]),
                "run": .string("layout floating"),
            ])])),
            ("mode", .dict(["main": .dict(["binding": .dict(["alt-h": .string("focus left")])])])),
            ("persistent-workspaces", .array([.string("Web")])),
            ("workspace-to-monitor-force-assignment", .dict(["Web": .array([.int(2), .string("main")])])),
            ("on-focus-changed", .array([.string("move-mouse window-lazy-center")])),
        ]
        for (key, value) in edits {
            raw = try TomlPatcher.replaceRoot(key, with: value, in: raw)
        }
        let parsed = parseConfig(raw)
        #expect(parsed.errors.isEmpty)
        #expect(parsed.config.onWindowDetected.count == 1)
        #expect(parsed.config.modes["main"]?.bindings["alt-h"] != nil)
    }

    @Test func replaceRootBoolPreservesInlineComment() throws {
        let result = try TomlPatcher.apply(
            edits: [.bool(["start-at-login"], true)],
            to: "start-at-login = false # my comment",
        )
        #expect(result == "start-at-login = true # my comment")
    }

    @Test func replaceValueInTable() throws {
        let result = try TomlPatcher.apply(
            edits: [.int(["gaps", "inner", "vertical"], 12)],
            to: "[gaps]\ninner.vertical = 8\n",
        )
        #expect(result == "[gaps]\ninner.vertical = 12\n")
    }

    @Test func replaceValueInNestedTable() throws {
        let result = try TomlPatcher.apply(
            edits: [.bool(["focus-follows-mouse", "enabled"], true)],
            to: "[focus-follows-mouse]\nenabled = false\n",
        )
        #expect(result == "[focus-follows-mouse]\nenabled = true\n")
    }

    @Test func replaceValuePreservesIndent() throws {
        let result = try TomlPatcher.apply(
            edits: [.int(["gaps", "inner", "vertical"], 12)],
            to: "[gaps]\n    inner.vertical = 8\n",
        )
        #expect(result == "[gaps]\n    inner.vertical = 12\n")
    }

    @Test func insertRootKeyAfterLastRootAssignment() throws {
        let result = try TomlPatcher.apply(
            edits: [.bool(["auto-reload-config"], true)],
            to: "gaps.inner.vertical = 8\n\n[key-mapping]\nh = 'focus left'\n",
        )
        #expect(result == "gaps.inner.vertical = 8\nauto-reload-config = true\n\n[key-mapping]\nh = 'focus left'\n")
    }

    @Test func insertRootKeyIntoEmptyFile() throws {
        let result = try TomlPatcher.apply(
            edits: [.bool(["auto-reload-config"], true)],
            to: "",
        )
        #expect(result == "auto-reload-config = true")
    }

    @Test func insertDottedKeyIntoExistingTable() throws {
        let result = try TomlPatcher.apply(
            edits: [.int(["gaps", "outer", "left"], 10)],
            to: "[gaps]\ninner.vertical = 8\n",
        )
        #expect(result == "[gaps]\ninner.vertical = 8\nouter.left = 10\n")
    }

    @Test func insertKeyIntoExistingNestedTable() throws {
        let result = try TomlPatcher.apply(
            edits: [.int(["gaps", "inner", "horizontal"], 8)],
            to: "[gaps]\ninner.vertical = 8\n",
        )
        #expect(result == "[gaps]\ninner.vertical = 8\ninner.horizontal = 8\n")
    }

    @Test func createNewTableAtEndOfFile() throws {
        let result = try TomlPatcher.apply(
            edits: [.bool(["focus-follows-mouse", "enabled"], true)],
            to: "start-at-login = false\n",
        )
        #expect(result == "start-at-login = false\n\n[focus-follows-mouse]\nenabled = true\n")
    }

    @Test func insertSkipsCommentsThatFollowTableHeader() throws {
        let result = try TomlPatcher.apply(
            edits: [.int(["gaps", "inner", "vertical"], 8)],
            to: "[gaps] # my gaps\n# comment about gaps\n",
        )
        #expect(result == "[gaps] # my gaps\n# comment about gaps\ninner.vertical = 8\n")
    }

    @Test func appendRespectsMissingFinalNewline() throws {
        let result = try TomlPatcher.apply(
            edits: [.bool(["auto-reload-config"], true)],
            to: "start-at-login = false",
        )
        #expect(result == "start-at-login = false\nauto-reload-config = true")
    }

    @Test func replaceMultiLineArrayWithSingleLine() throws {
        let result = try TomlPatcher.apply(
            edits: [.stringArray(["persistent-workspaces"], ["w", "x"])],
            to: "persistent-workspaces = [\n  'a',\n  'b',\n]\nafter-login-command = 'x'\n",
        )
        #expect(result == "persistent-workspaces = [\"w\", \"x\"]\nafter-login-command = 'x'\n")
    }

    @Test func hashInsideStringIsNotAComment() throws {
        let result = try TomlPatcher.apply(
            edits: [.string(["after-login-command"], "echo hi")],
            to: "after-login-command = 'echo \"#1\"' # note\n",
        )
        #expect(result == "after-login-command = \"echo hi\" # note\n")
    }

    @Test func assignmentInsideMultiLineStringIsNotTouched() throws {
        let result = try TomlPatcher.apply(
            edits: [.bool(["auto-reload-config"], true)],
            to: "after-login-command = '''\nfoo = 1\n'''\nauto-reload-config = false\n",
        )
        #expect(result == "after-login-command = '''\nfoo = 1\n'''\nauto-reload-config = true\n")
    }

    @Test func preservesUnrelatedContent() throws {
        let raw = """
            # AeroSpace config
            start-at-login = false

            [key-mapping]
            preset = 'qwerty'

            [gaps]
            inner.vertical = 8

            [mode.main.binding]
            alt-h = 'focus left'
            """
        let result = try TomlPatcher.apply(
            edits: [.int(["gaps", "inner", "vertical"], 10), .bool(["start-at-login"], true)],
            to: raw + "\n",
        )
        #expect(result == raw.replacing("inner.vertical = 8", with: "inner.vertical = 10")
            .replacing("start-at-login = false", with: "start-at-login = true") + "\n")
    }

    @Test func duplicateKeyInFileThrows() {
        #expect(throws: TomlPatcher.PatcherError.duplicateKey(path: ["start-at-login"])) {
            _ = try TomlPatcher.apply(
                edits: [.bool(["start-at-login"], true)],
                to: "start-at-login = false\nstart-at-login = true\n",
            )
        }
    }

    @Test func duplicateEditInBatchThrows() {
        #expect(throws: TomlPatcher.PatcherError.duplicateEdit(path: ["start-at-login"])) {
            _ = try TomlPatcher.apply(
                edits: [.bool(["start-at-login"], true), .bool(["start-at-login"], false)],
                to: "start-at-login = false\n",
            )
        }
    }

    @Test func nonBareKeyEditThrows() {
        #expect(throws: TomlPatcher.PatcherError.self) {
            _ = try TomlPatcher.apply(
                edits: [.bool(["not a bare key"], true)],
                to: "",
            )
        }
    }
}

/// The edits that the visual settings editor applies must produce a config that AeroSpace parses
@MainActor
@Suite struct SettingsEditsTest {
    private var settingsEdits: [TomlPatcher.Edit] {
        [
            .bool(["start-at-login"], true),
            .bool(["auto-reload-config"], true),
            .bool(["automatically-unhide-macos-hidden-apps"], true),
            .string(["default-root-container-layout"], Layout.accordion.rawValue),
            .string(["default-root-container-orientation"], DefaultContainerOrientation.horizontal.rawValue),
            .int(["accordion-padding"], 42),
            .bool(["enable-normalization-flatten-containers"], false),
            .bool(["enable-normalization-opposite-orientation-for-nested-containers"], false),
            .int(["gaps", "inner", "vertical"], 7),
            .int(["gaps", "inner", "horizontal"], 9),
            .int(["gaps", "outer", "left"], 11),
            .int(["gaps", "outer", "top"], 13),
            .int(["gaps", "outer", "bottom"], 15),
            .int(["gaps", "outer", "right"], 17),
            .bool(["focus-follows-mouse", "enabled"], true),
        ]
    }

    private func assertSettings(_ config: Config) {
        #expect(config.startAtLogin)
        #expect(config.autoReloadConfig)
        #expect(config.automaticallyUnhideMacosHiddenApps)
        #expect(config.defaultRootContainerLayout == .accordion)
        #expect(config.defaultRootContainerOrientation == .horizontal)
        #expect(config.accordionPadding == 42)
        #expect(!config.enableNormalizationFlattenContainers)
        #expect(!config.enableNormalizationOppositeOrientationForNestedContainers)
        #expect(config.gaps.inner.vertical.constantValue == 7)
        #expect(config.gaps.inner.horizontal.constantValue == 9)
        #expect(config.gaps.outer.left.constantValue == 11)
        #expect(config.gaps.outer.top.constantValue == 13)
        #expect(config.gaps.outer.bottom.constantValue == 15)
        #expect(config.gaps.outer.right.constantValue == 17)
        #expect(config.focusFollowsMouse.enabled)
    }

    @Test func patchedDefaultConfigParses() throws {
        let url = projectRoot.appending(component: "docs/config-examples/default-config.toml")
        let raw = try String(contentsOf: url, encoding: .utf8)
        let result = parseConfig(try TomlPatcher.apply(edits: settingsEdits, to: raw))
        #expect(result.errors == [])
        #expect(result.warnings == [])
        assertSettings(result.config)
    }

    @Test func patchedMinimalConfigParses() throws {
        let result = parseConfig(try TomlPatcher.apply(edits: settingsEdits, to: "config-version = 2\n"))
        #expect(result.errors == [])
        assertSettings(result.config)
    }
}
