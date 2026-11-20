import AppKit
import Common
import SwiftUI
import WebKit

public let supportWindowId = "\(aeroSpaceAppName).supportView"

@MainActor
public func getSupportWindow() -> some Scene {
    SwiftUI.Window(L("Support"), id: supportWindowId) {
        SupportView(model: SupportModel.shared)
            .frame(minWidth: 780, minHeight: 520)
            .onAppear {
                NSApp.setActivationPolicy(.accessory)
                NSApp.activate(ignoringOtherApps: true)
            }
    }
    .windowResizability(.contentMinSize)
    .defaultSize(width: 900, height: 620)
}

private struct SupportView: View {
    @ObservedObject var model: SupportModel
    @AppStorage("airspace.language") private var languagePreference = AppLanguage.system.rawValue

    var body: some View {
        TabView(selection: $model.section) {
            DocsView(model: model)
                .tabItem { Label(L("Help & Documentation"), systemImage: SupportModel.Section.docs.systemImage) }
                .tag(SupportModel.Section.docs)
            AnnouncementsView(model: model)
                .tabItem { Label(L("Announcements"), systemImage: SupportModel.Section.announcements.systemImage) }
                .tag(SupportModel.Section.announcements)
            AgreementsView(model: model)
                .tabItem { Label(L("Agreements"), systemImage: SupportModel.Section.agreements.systemImage) }
                .tag(SupportModel.Section.agreements)
            ContactsView(model: model)
                .tabItem { Label(L("Contact Support"), systemImage: SupportModel.Section.contacts.systemImage) }
                .tag(SupportModel.Section.contacts)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChangeCompat(of: languagePreference) { _ in
            Task.startUnstructured { await model.reloadForLocaleChange() }
        }
    }
}

// MARK: - Docs

private struct DocsView: View {
    @ObservedObject var model: SupportModel

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)
            detail
                .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await model.loadIfNeeded(.docs) }
        .onChangeCompat(of: model.selectedDocSlug) { slug in
            Task.startUnstructured { await model.loadDoc(slug) }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        if model.isLoading(.docs) {
            centered { ProgressView() }
        } else if let error = model.error(.docs) {
            ErrorStateView(message: error) { Task.startUnstructured { await model.reload(.docs) } }
        } else if model.docs.isEmpty {
            EmptyStateView(text: L("No documents yet"))
        } else {
            List(selection: $model.selectedDocSlug) {
                ForEach(model.docs, id: \.key) { doc in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(doc.name?.nilIfBlank ?? doc.slug ?? "")
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        if let description = doc.description?.nilIfBlank {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(doc.key)
                }
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if model.isDocLoading {
            centered { ProgressView() }
        } else if let error = model.docError {
            ErrorStateView(message: error) { Task.startUnstructured { await model.loadDoc(model.selectedDocSlug) } }
        } else if let doc = model.docDetail {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(doc.name?.nilIfBlank ?? doc.slug ?? "")
                        .font(.title2.weight(.semibold))
                    if let description = doc.description?.nilIfBlank {
                        Text(description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                Divider()
                if let content = doc.content?.nilIfBlank {
                    HTMLContentView(content: content)
                } else {
                    EmptyStateView(text: L("No details available."))
                }
            }
        } else {
            EmptyStateView(text: L("Select a document"))
        }
    }
}

// MARK: - Announcements

private struct AnnouncementsView: View {
    @ObservedObject var model: SupportModel

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)
            detail
                .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await model.loadIfNeeded(.announcements) }
    }

    @ViewBuilder
    private var sidebar: some View {
        if model.isLoading(.announcements) {
            centered { ProgressView() }
        } else if let error = model.error(.announcements) {
            ErrorStateView(message: error) { Task.startUnstructured { await model.reload(.announcements) } }
        } else if model.activities.isEmpty {
            EmptyStateView(text: L("No announcements yet"))
        } else {
            List(selection: $model.selectedActivityId) {
                ForEach(model.activities, id: \.key) { activity in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activity.name?.nilIfBlank ?? activity.slug ?? "")
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        if let subName = activity.subName?.nilIfBlank {
                            Text(subName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(activity.key)
                }
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let activity = model.selectedActivity {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(activity.name?.nilIfBlank ?? activity.slug ?? "")
                        .font(.title2.weight(.semibold))
                    if let subName = activity.subName?.nilIfBlank {
                        Text(subName)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if let externalUrl = activity.externalUrl?.nilIfBlank, let url = URL(string: externalUrl) {
                        Button(L("Open")) { NSWorkspace.shared.open(url) }
                    }
                }
                .padding(14)
                Divider()
                if let content = activity.content?.nilIfBlank {
                    HTMLContentView(content: content)
                } else if let description = activity.description?.nilIfBlank {
                    HTMLContentView(content: description)
                } else {
                    EmptyStateView(text: L("No details available."))
                }
            }
        } else {
            EmptyStateView(text: L("Select an announcement"))
        }
    }
}

// MARK: - Agreements

private struct AgreementsView: View {
    @ObservedObject var model: SupportModel

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)
            detail
                .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await model.loadIfNeeded(.agreements) }
    }

    @ViewBuilder
    private var sidebar: some View {
        if model.isLoading(.agreements) {
            centered { ProgressView() }
        } else if let error = model.error(.agreements) {
            ErrorStateView(message: error) { Task.startUnstructured { await model.reload(.agreements) } }
        } else if model.agreements.isEmpty {
            EmptyStateView(text: L("No agreements yet"))
        } else {
            List(selection: $model.selectedAgreementSlug) {
                ForEach(model.agreements, id: \.key) { agreement in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(agreement.name?.nilIfBlank ?? agreement.slug ?? "")
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        if let typeName = agreement.typeName?.nilIfBlank {
                            Text(typeName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(agreement.key)
                }
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let agreement = model.selectedAgreement {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(agreement.name?.nilIfBlank ?? agreement.slug ?? "")
                        .font(.title2.weight(.semibold))
                    if let description = agreement.description?.nilIfBlank {
                        Text(description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if let externalUrl = agreement.externalUrl?.nilIfBlank, let url = URL(string: externalUrl) {
                        Button(L("Open")) { NSWorkspace.shared.open(url) }
                    }
                }
                .padding(14)
                Divider()
                if let content = agreement.content?.nilIfBlank {
                    HTMLContentView(content: content)
                } else {
                    EmptyStateView(text: L("No details available."))
                }
            }
        } else {
            EmptyStateView(text: L("Select an agreement"))
        }
    }
}

// MARK: - Contacts

private struct ContactsView: View {
    @ObservedObject var model: SupportModel

    var body: some View {
        Group {
            if model.isLoading(.contacts) {
                centered { ProgressView() }
            } else if let error = model.error(.contacts) {
                ErrorStateView(message: error) { Task.startUnstructured { await model.reload(.contacts) } }
            } else if model.contacts.isEmpty {
                EmptyStateView(text: L("No contact channels yet"))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(model.contacts, id: \.key) { channel in
                            ContactCard(channel: channel)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .task { await model.loadIfNeeded(.contacts) }
    }
}

private struct ContactCard: View {
    let channel: WalnutClient.ContactChannel
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: channel.icon?.nilIfBlank ?? channel.defaultIcon)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name?.nilIfBlank ?? channel.code ?? L("Contact"))
                        .font(.headline)
                    if let sceneName = channel.sceneName?.nilIfBlank {
                        Text(sceneName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if copied {
                    Label(L("Copied"), systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let description = channel.description?.nilIfBlank {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let value = channel.value?.nilIfBlank {
                Text(value)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
            if let link = channel.linkUrl?.nilIfBlank, URL(string: link) != nil {
                Text(link)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if !channel.effectiveActions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(channel.effectiveActions, id: \.self) { action in
                        Button {
                            if SupportActions.perform(action, channel: channel) {
                                copied = true
                            }
                        } label: {
                            Label(channel.actionTitle(action), systemImage: channel.actionIcon(action))
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Shared views

private struct ErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(L("Unable to load content"))
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L("Retry"), action: retry)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmptyStateView: View {
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@ViewBuilder
private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    VStack {
        Spacer()
        content()
        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

// MARK: - HTML

private struct HTMLContentView: NSViewRepresentable {
    let content: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.underPageBackgroundColor = .textBackgroundColor
        webView.allowsMagnification = true
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let document = Self.document(content)
        guard context.coordinator.lastDocument != document else { return }
        context.coordinator.lastDocument = document
        webView.loadHTMLString(document, baseURL: WalnutClient.defaultBaseURL)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastDocument: String?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
        ) async -> WKNavigationActionPolicy {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url
            else { return .allow }
            NSWorkspace.shared.open(url)
            return .cancel
        }
    }

    private static func document(_ content: String) -> String {
        let body: String
        if content.contains("<") {
            body = content
        } else {
            let escaped = content
                .replacing("&", with: "&amp;")
                .replacing("<", with: "&lt;")
                .replacing(">", with: "&gt;")
            body = "<p>" + escaped.replacing("\n", with: "<br>") + "</p>"
        }

        return """
            <!doctype html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
            :root { color-scheme: light dark; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
                font-size: 14px;
                line-height: 1.55;
                margin: 16px 18px 28px;
                background: transparent;
                color: CanvasText;
            }
            h1, h2, h3 { line-height: 1.25; }
            h1 { font-size: 1.5em; }
            h2 { font-size: 1.25em; }
            h3 { font-size: 1.1em; }
            img { max-width: 100%; height: auto; }
            pre { white-space: pre-wrap; background: rgba(127, 127, 127, 0.12); padding: 10px; border-radius: 6px; }
            code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
            a { color: LinkText; }
            blockquote { border-left: 3px solid rgba(127, 127, 127, 0.4); margin-left: 0; padding-left: 12px; color: GrayText; }
            </style>
            </head>
            <body>\(body)</body>
            </html>
            """
    }
}
