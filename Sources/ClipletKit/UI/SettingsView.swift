import AppKit
import ApplicationServices
import Carbon
import SwiftUI
import UniformTypeIdentifiers

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, clipboard, history, privacy, about

    var id: Self { self }
    @MainActor var title: String {
        switch self {
        case .general: return L10n.tr("General")
        case .clipboard: return L10n.tr("Clipboard")
        case .history: return L10n.tr("History")
        case .privacy: return L10n.tr("Privacy")
        case .about: return L10n.tr("About")
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .clipboard: return "doc.on.clipboard"
        case .history: return "clock.arrow.circlepath"
        case .privacy: return "hand.raised"
        case .about: return "info.circle"
        }
    }

}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: ClipboardStore
    @State private var selectedTab: SettingsTab? = .general
    @State private var history: [SettingsTab] = [.general]
    @State private var historyIndex = 0
    @State private var navigatingHistory = false

    private var activeTab: SettingsTab { selectedTab ?? .general }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    sidebarRow(tab).tag(tab)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle(L10n.tr("Settings"))
            .toolbar(removing: .sidebarToggle)
            .settingsScrollEdgeIfAvailable()
            // Match the reference's 180-point Xcode category column.
            .navigationSplitViewColumnWidth(min: 180, ideal: 180, max: 180)
        } detail: {
            detail(for: activeTab)
                .id(settings.language)
                .navigationTitle(activeTab.title)
                .settingsToolbarTitleIfAvailable()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle(L10n.tr("Settings"))
        // The split view supplies the full-height surfaces. A separate toolbar
        // background creates an inset edge above the native sidebar divider.
        .toolbarBackground(.hidden, for: .windowToolbar)
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, minHeight: 520)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                // A native navigation group supplies one shared glass capsule on
                // macOS 26, and the system segmented appearance on macOS 14–15.
                ControlGroup {
                    Button(action: goBack) {
                        Label(L10n.tr("Back"), systemImage: "chevron.left")
                    }
                    .disabled(historyIndex == 0)
                    .keyboardShortcut("[", modifiers: .command)
                    .help(L10n.tr("Back"))
                    Button(action: goForward) {
                        Label(L10n.tr("Forward"), systemImage: "chevron.right")
                    }
                    .disabled(historyIndex >= history.count - 1)
                    .keyboardShortcut("]", modifiers: .command)
                    .help(L10n.tr("Forward"))
                }
                .controlGroupStyle(.navigation)
                .labelStyle(.iconOnly)
            }
            if #available(macOS 26.0, *) {
                ToolbarItem(placement: .navigation) {
                    Text(activeTab.title)
                        .font(.system(size: 16, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .environment(\.locale, L10n.locale)
        .onChange(of: selectedTab) { _, newValue in record(newValue) }
    }

    private func sidebarRow(_ tab: SettingsTab) -> some View {
        HStack(spacing: 8) {
            Image(systemName: tab.symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(activeTab == tab ? Color.white : Color.blue)
                .frame(width: 20, height: 22)
                .accessibilityHidden(true)
            Text(tab.title)
                .font(.system(size: 13, weight: activeTab == tab ? .semibold : .regular))
        }
        .padding(.leading, 3)
        .padding(.vertical, 1)
    }

    @ViewBuilder private func detail(for tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettingsPane(settings: settings)
        case .clipboard: ClipboardSettingsPane(settings: settings)
        case .history: HistorySettingsPane(settings: settings, store: store)
        case .privacy: PrivacySettingsPane(settings: settings)
        case .about: AboutSettingsPane(version: appVersion)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return L10n.format("Version %@ (%@)", version, build)
    }

    private func goBack() {
        guard historyIndex > 0 else { return }
        navigatingHistory = true
        historyIndex -= 1
        selectedTab = history[historyIndex]
        DispatchQueue.main.async { navigatingHistory = false }
    }

    private func goForward() {
        guard historyIndex < history.count - 1 else { return }
        navigatingHistory = true
        historyIndex += 1
        selectedTab = history[historyIndex]
        DispatchQueue.main.async { navigatingHistory = false }
    }

    private func record(_ tab: SettingsTab?) {
        guard !navigatingHistory, let tab, history[historyIndex] != tab else { return }
        if historyIndex < history.count - 1 { history = Array(history.prefix(historyIndex + 1)) }
        history.append(tab)
        historyIndex = history.count - 1
    }
}

private struct GeneralSettingsPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section(L10n.tr("Language")) {
                Picker(selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                } label: {
                    settingLabel(L10n.tr("Language"), description: L10n.tr("Changes apply immediately."))
                }
                .pickerStyle(.menu)
            }

            Section(L10n.tr("System")) {
                Toggle(isOn: Binding(get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) })) {
                    settingLabel(
                        L10n.tr("Launch at Login"),
                        description: L10n.tr("Keep clipboard history available after you sign in."))
                }
                .toggleStyle(.switch)
                HStack(spacing: 12) {
                    settingLabel(
                        L10n.tr("Global Shortcut"),
                        description: L10n.tr("Click the shortcut, then press a key combination.")
                    )
                    Spacer()
                    HStack(spacing: 8) {
                        ShortcutRecorder(shortcut: $settings.globalHotkey)
                        Button {
                            settings.globalHotkey = .defaultValue
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderless)
                        .disabled(settings.globalHotkey == .defaultValue)
                        .help(L10n.tr("Restore Default Shortcut"))
                        .accessibilityLabel(L10n.tr("Restore Default Shortcut"))
                    }
                }
                if !settings.hotkeyRegistrationSucceeded {
                    Label(
                        L10n.tr("This shortcut is unavailable. Choose another combination."),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            Section(L10n.tr("Panel")) {
                VStack(alignment: .leading, spacing: 8) {
                    settingLabel(
                        L10n.tr("Liquid Glass"),
                        description: L10n.tr("Choose between a clearer panel and more legible content."))
                    PanelGlassPreview(
                        look: PanelGlass.look(
                            legibility: settings.panelLegibility, unrestricted: settings.panelUnrestrictedGlass))
                    Slider(value: $settings.panelLegibility, in: 0...1) {
                        Text(L10n.tr("Liquid Glass"))
                    } minimumValueLabel: {
                        Text(L10n.tr("Clear")).font(.caption).foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text(L10n.tr("Legible")).font(.caption).foregroundStyle(.secondary)
                    }
                    .labelsHidden()
                }
                Toggle(isOn: $settings.panelUnrestrictedGlass) {
                    settingLabel(
                        L10n.tr("Unrestricted Adjustment"),
                        description: L10n.tr(
                            "Allows clearer and fully opaque settings. Content may be hard to read over busy backgrounds."
                        ))
                }
                .toggleStyle(.switch)
                Picker(selection: $settings.panelAnimation) {
                    ForEach(PanelAnimation.allCases) { animation in
                        Text(animation.title).tag(animation)
                    }
                } label: {
                    settingLabel(
                        L10n.tr("Open Animation"),
                        description: L10n.tr("Reduce Motion in Accessibility settings replaces movement with a fade."))
                }
                .pickerStyle(.menu)
            }
        }
        .settingsFormStyle()
    }
}

/// A miniature panel over the current wallpaper, rendered with the same glass
/// and tint mapping as the real panel.
private struct PanelGlassPreview: View {
    let look: PanelGlass.Look
    @State private var wallpaper: NSImage? = {
        guard let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    private static let panelSize = CGSize(width: 860, height: 560)
    private let samples: [(symbol: String, title: String)] = [
        ("text.alignleft", "Less, but better."),
        ("link", "https://developer.apple.com/design/"),
        ("paintpalette", "#E85D75"),
        ("text.alignleft", "Stay curious. Keep creating."),
        ("terminal", "swift build -c release"),
        ("envelope", "hello@example.com"),
    ]

    var body: some View {
        GeometryReader { proxy in
            let scale = min(
                (proxy.size.width - 48) / Self.panelSize.width, (proxy.size.height - 40) / Self.panelSize.height)
            ZStack {
                background
                // Laid out at the real panel size, then scaled, so proportions and
                // type weight match what the panel shows.
                panel
                    .frame(width: Self.panelSize.width, height: Self.panelSize.height)
                    .scaleEffect(scale)
                    .frame(width: Self.panelSize.width * scale, height: Self.panelSize.height * scale)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }

    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: OverlayPanel.cornerRadius, style: .continuous)
        return VStack(spacing: 0) {
            HStack {
                Text(L10n.tr("Search Clipboard History")).font(.system(size: 16)).foregroundStyle(.secondary)
                Spacer()
                Label(L10n.tr("All Types"), systemImage: "line.3.horizontal.decrease").font(.system(size: 13))
            }
            .padding(.horizontal, 16)
            .frame(height: 64)
            Divider()
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.tr("Today")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 5)
                    ForEach(samples.indices, id: \.self) { index in
                        Label(samples[index].title, systemImage: samples[index].symbol)
                            .font(.system(size: 13)).lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                            .background(
                                index == 0 ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 7)
                            )
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(width: 380)
                Divider()
                Text(samples[0].title)
                    .font(.system(size: 13))
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Divider()
            HStack(spacing: 12) {
                Image(systemName: "clipboard").foregroundStyle(.secondary)
                Text(L10n.tr("Clipboard History")).foregroundStyle(.secondary)
                Spacer()
                Text(L10n.tr("Paste to Active App"))
                Text(L10n.tr("Actions"))
            }
            .font(.system(size: 12))
            .padding(.horizontal, 16)
            .frame(height: 42)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(look.tint))
        .clipShape(shape)
        .panelPreviewGlass(clear: look.clear, in: shape)
        .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
    }

    @ViewBuilder private var background: some View {
        if let wallpaper {
            Image(nsImage: wallpaper).resizable().aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
        } else {
            LinearGradient(colors: [.orange, .pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

private extension View {
    @ViewBuilder func panelPreviewGlass(clear: Bool, in shape: some Shape) -> some View {
        if #available(macOS 26.0, *) {
            background { Color.clear.glassEffect(clear ? .clear : .regular, in: shape) }
        } else {
            background(.regularMaterial, in: shape)
        }
    }
}

private struct ShortcutRecorder: View {
    @Binding var shortcut: GlobalHotkey
    @StateObject private var recorder = ShortcutRecorderController()

    var body: some View {
        Button {
            recorder.toggle { shortcut = $0 }
        } label: {
            Text(recorder.isRecording ? L10n.tr("Press Shortcut…") : shortcut.displayString)
                .font(.body.monospaced())
                .frame(minWidth: 88)
        }
        .buttonStyle(.bordered)
        .tint(recorder.isRecording ? .accentColor : nil)
        .help(L10n.tr(recorder.isRecording ? "Press Escape to cancel." : "Click to record a shortcut."))
        .accessibilityLabel(L10n.tr("Global Shortcut"))
        .accessibilityValue(recorder.isRecording ? L10n.tr("Press Shortcut…") : shortcut.displayString)
        .onDisappear { recorder.stop() }
    }
}

@MainActor
private final class ShortcutRecorderController: ObservableObject {
    @Published private(set) var isRecording = false
    private var monitor: Any?

    func toggle(onCapture: @escaping (GlobalHotkey) -> Void) {
        if isRecording {
            stop()
            return
        }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                self.stop()
                return nil
            }
            guard let shortcut = GlobalHotkey(event: event) else {
                NSSound.beep()
                return nil
            }
            onCapture(shortcut)
            self.stop()
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}

private struct ClipboardSettingsPane: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Form {
            Section(L10n.tr("Clipboard")) {
                Toggle(isOn: Binding(get: { !settings.isPaused }, set: { settings.isPaused = !$0 })) {
                    settingLabel(
                        L10n.tr("Record Clipboard History"),
                        description: L10n.tr("Save supported clipboard content locally on this Mac."))
                }
                .toggleStyle(.switch)
                Toggle(isOn: $settings.pasteAutomatically) {
                    settingLabel(
                        L10n.tr("Paste to Active App"),
                        description: L10n.tr("Return to the previous app and paste the selected entry."))
                }
                .toggleStyle(.switch)
                Toggle(isOn: $settings.preferPlainText) {
                    settingLabel(
                        L10n.tr("Prefer Plain Text"),
                        description: L10n.tr("Remove rich formatting when pasting text entries."))
                }
                .toggleStyle(.switch)
            }

        }
        .settingsFormStyle()
    }
}

private struct HistorySettingsPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: ClipboardStore
    @State private var confirmClear = false
    @State private var maximumItemsDraft = "10000"
    @FocusState private var maximumItemsFieldFocused: Bool

    var body: some View {
        Form {
            Section(L10n.tr("Retention")) {
                Picker(L10n.tr("Keep History For"), selection: $settings.retentionDays) {
                    Text(L10n.tr("1 Day")).tag(1); Text(L10n.tr("1 Week")).tag(7); Text(L10n.tr("1 Month")).tag(30)
                    Text(L10n.tr("3 Months")).tag(90); Text(L10n.tr("1 Year")).tag(365)
                }
                .pickerStyle(.menu)
                Toggle(isOn: unlimitedEntries) {
                    settingLabel(
                        L10n.tr("Unlimited Entries"),
                        description: L10n.tr("Keep every entry without a count limit.")
                    )
                }
                .toggleStyle(.switch)
                LabeledContent(L10n.tr("Maximum Entries")) {
                    HStack(spacing: 8) {
                        TextField("", text: $maximumItemsDraft, prompt: Text("10000"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(width: 110)
                            .focused($maximumItemsFieldFocused)
                            .onSubmit(commitMaximumItems)
                            .accessibilityLabel(L10n.tr("Maximum Entries"))
                        Text(L10n.tr("entries"))
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(settings.maximumItems == 0)
            }

            Section(L10n.tr("Storage")) {
                LabeledContent {
                    Button(L10n.tr("Clear History…"), role: .destructive) { confirmClear = true }
                } label: {
                    settingLabel(
                        L10n.tr("Unpinned Entries"),
                        description: L10n.tr("Pinned entries are preserved when clearing history."))
                }
            }
        }
        .settingsFormStyle()
        .onAppear {
            if settings.maximumItems > 0 {
                maximumItemsDraft = String(settings.maximumItems)
            }
        }
        .onChange(of: maximumItemsFieldFocused) { _, isFocused in
            if !isFocused { commitMaximumItems() }
        }
        .confirmationDialog(L10n.tr("Clear Clipboard History?"), isPresented: $confirmClear) {
            Button(L10n.tr("Clear Unpinned History"), role: .destructive) { store.clearUnpinned() }
            Button(L10n.tr("Cancel"), role: .cancel) {}
        }
    }

    private var unlimitedEntries: Binding<Bool> {
        Binding(
            get: { settings.maximumItems == 0 },
            set: { isUnlimited in
                if isUnlimited {
                    if settings.maximumItems > 0 {
                        maximumItemsDraft = String(settings.maximumItems)
                    }
                    settings.maximumItems = 0
                } else {
                    settings.maximumItems = parsedMaximumItems ?? 10_000
                    maximumItemsDraft = String(settings.maximumItems)
                }
            }
        )
    }

    private var parsedMaximumItems: Int? {
        guard let value = Int(maximumItemsDraft), value > 0 else { return nil }
        return value
    }

    private func commitMaximumItems() {
        guard settings.maximumItems != 0 else { return }
        guard let value = parsedMaximumItems else {
            maximumItemsDraft = String(settings.maximumItems)
            return
        }
        settings.maximumItems = value
        maximumItemsDraft = String(value)
    }
}

private struct PrivacySettingsPane: View {
    @ObservedObject var settings: AppSettings
    @State private var accessibilityGranted = AXIsProcessTrusted()

    var body: some View {
        Form {
            Section {
                LabeledContent(L10n.tr("Automatic Paste Permission")) {
                    Label(
                        L10n.tr(accessibilityGranted ? "Allowed" : "Not Allowed"),
                        systemImage: accessibilityGranted ? "checkmark.circle.fill" : "circle"
                    )
                    .foregroundStyle(accessibilityGranted ? Color.green : Color.secondary)
                }
                Button(L10n.tr("Open Accessibility Settings…")) {
                    PasteService.requestAccessibility()
                }
            } header: {
                Text(L10n.tr("Accessibility"))
            } footer: {
                Text(L10n.tr("Required only to send Command–V to another app."))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                ForEach(settings.excludedBundleIDs.sorted(), id: \.self) { identifier in
                    HStack {
                        SourceAppIcon(bundleIdentifier: identifier).frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(applicationName(identifier)).lineLimit(1)
                            Text(identifier).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button {
                            settings.excludedBundleIDsText = settings.excludedBundleIDs.subtracting([identifier])
                                .sorted().joined(separator: "\n")
                        } label: {
                            Image(systemName: "minus.circle").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(L10n.tr("Remove Exclusion") + ": " + applicationName(identifier))
                    }
                    .padding(.vertical, 3)
                }
                Button(action: addApplications) { Label(L10n.tr("Add Application…"), systemImage: "plus") }
            } header: {
                Text(L10n.tr("Disabled Applications"))
            } footer: {
                Text(L10n.tr("Clipboard content from these apps is never recorded."))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                DisclosureGroup(L10n.tr("Advanced")) {
                    Text(
                        L10n.tr(
                            "Clipboard changes from these bundle identifiers are never recorded. Enter one identifier per line."
                        )
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $settings.excludedBundleIDsText)
                        .font(.body.monospaced()).frame(minHeight: 160)
                        .accessibilityLabel(L10n.tr("Disabled application bundle identifiers"))
                }
            }
        }
        .settingsFormStyle()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityGranted = AXIsProcessTrusted()
        }
    }

    private func applicationName(_ identifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else {
            let knownNames = [
                "com.agilebits.onepassword7": "1Password 7", "com.bitwarden.desktop": "Bitwarden",
                "com.lastpass.LastPass": "LastPass",
            ]
            return knownNames[identifier] ?? identifier
        }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func addApplications() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = L10n.tr("Add")
        guard panel.runModal() == .OK else { return }
        let identifiers = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        settings.excludedBundleIDsText = settings.excludedBundleIDs.union(identifiers).sorted().joined(separator: "\n")
    }
}

private struct AboutSettingsPane: View {
    let version: String
    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    AppBrandIcon(size: 80)
                    Text(AppBrand.name).font(.title2.bold())
                    Text(version).font(.callout).foregroundStyle(.secondary)
                    Text(L10n.tr("A private, native clipboard history for macOS."))
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24)
            }
            Section {
                Label(L10n.tr("On-device Storage"), systemImage: "internaldrive")
                Label(L10n.tr("No Analytics"), systemImage: "hand.raised")
            } header: {
                Text(L10n.tr("Privacy"))
            } footer: {
                Text(
                    L10n.tr(
                        "Clipboard history stays on this Mac. The app does not upload clipboard content or analytics.")
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .settingsFormStyle()
    }
}

private func settingLabel(_ title: String, description: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title)
        Text(description).font(.system(size: 12)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .combine)
}

private extension View {
    @ViewBuilder func settingsToolbarTitleIfAvailable() -> some View {
        if #available(macOS 26.0, *) { toolbar(removing: .title) } else { self }
    }

    func settingsFormStyle() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            // Form already contributes 20 points of inset. Add 20 to match
            // the reference's 40-point margins, with no extra top inset.
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .contentMargins(.top, 0, for: .scrollContent)
            .settingsScrollEdgeIfAvailable()
    }

    @ViewBuilder func settingsScrollEdgeIfAvailable() -> some View {
        if #available(macOS 26.0, *) { scrollEdgeEffectStyle(.soft, for: .all) } else { self }
    }
}
