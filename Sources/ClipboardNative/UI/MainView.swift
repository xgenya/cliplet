import AppKit
import SwiftUI

private enum OverlayMetrics {
    // A compact command panel is a non-standard canvas, so its structural sizes live here.
    static let minimumWidth: CGFloat = 860
    static let minimumHeight: CGFloat = 560
    static let cornerRadius = OverlayPanel.cornerRadius
    static let sidebarWidth: CGFloat = 380
    static let thumbnailSize: CGFloat = 22
    static let sourceIconSize: CGFloat = 18
    static let actionPanelWidth: CGFloat = 350
}

struct MainView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var viewState: ClipboardViewState
    @ObservedObject var settings: AppSettings
    let onPaste: (ClipboardItem) -> Void
    let onCopy: (ClipboardItem) -> Void
    let onCopyText: (String) -> Void
    let onRename: (ClipboardItem) -> Void
    let onSettings: () -> Void

    @FocusState private var focusedField: ClipboardPanelFocus?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .overlay(alignment: .bottomTrailing) {
            ZStack(alignment: .bottomTrailing) {
                if viewState.showActions, let item = viewState.selectedItem {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { viewState.showActions = false }
                        .transition(.identity)
                    ClipboardActionsMenu(
                        actions: actions(for: item), focus: $focusedField, onDismiss: { viewState.showActions = false }
                    )
                    .id(item.id)
                    .id(viewState.actionPresentationID)
                    .frame(width: OverlayMetrics.actionPanelWidth)
                    .floatingPanelSurface(cornerRadius: OverlayMetrics.cornerRadius)
                    .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
                    .padding(.trailing, 10)
                    .padding(.bottom, 52)
                    .transition(
                        reduceMotion ? .opacity : .scale(scale: 0.96, anchor: .bottomTrailing).combined(with: .opacity))
                }
            }
            .allowsHitTesting(viewState.showActions)
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.24, dampingFraction: 0.88),
                value: viewState.showActions)
        }
        .frame(minWidth: OverlayMetrics.minimumWidth, minHeight: OverlayMetrics.minimumHeight)
        .environment(\.locale, L10n.locale)
        .onAppear {
            focusedField = .history
            viewState.selectFirstIfNeeded()
        }
        .onChange(of: viewState.showActions) { _, presented in
            focusedField = presented ? .actions : .history
        }
        .onChange(of: viewState.query) { _, _ in viewState.selectFirstIfNeeded() }
        .onChange(of: viewState.filter) { _, _ in viewState.selectFirstIfNeeded() }
        .confirmationDialog(L10n.tr("Clear Clipboard History?"), isPresented: $showDeleteConfirmation) {
            Button(L10n.tr("Clear Unpinned History"), role: .destructive) { store.clearUnpinned() }
            Button(L10n.tr("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.tr("Pinned items will be kept."))
        }
    }

    private var searchHeader: some View {
        HStack {
            TextField(L10n.tr("Search Clipboard History"), text: $viewState.query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($focusedField, equals: .history)
                .accessibilityLabel(L10n.tr("Search clipboard history"))
            Menu {
                Button {
                    viewState.filter = nil
                } label: {
                    Label(L10n.tr("All Types"), systemImage: "square.grid.2x2")
                }
                Divider()
                ForEach(ClipboardKind.allCases) { kind in
                    Button {
                        viewState.filter = kind
                    } label: {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                }
            } label: {
                Label(
                    viewState.filter?.title ?? L10n.tr("All Types"),
                    systemImage: viewState.filter?.symbol ?? "line.3.horizontal.decrease")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .frame(minWidth: 94)
            .accessibilityHint(L10n.tr("Filters clipboard entries by content type"))
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
    }

    @ViewBuilder private var content: some View {
        if viewState.visibleItems.isEmpty {
            ContentUnavailableView {
                Label(
                    viewState.query.isEmpty ? L10n.tr("No Clipboard History") : L10n.tr("No Results"),
                    systemImage: viewState.query.isEmpty ? "clipboard" : "magnifyingglass")
            } description: {
                if settings.isPaused {
                    Text(L10n.tr("Clipboard recording is paused. Resume it from the menu bar or Settings."))
                } else if viewState.query.isEmpty {
                    Text(L10n.tr("Copy text, links, images, or files to see them here."))
                } else {
                    Text(L10n.tr("Try another search or content filter."))
                }
            }
        } else {
            HStack(spacing: 0) {
                itemList.id(settings.language).frame(width: OverlayMetrics.sidebarWidth)
                Divider()
                preview.frame(maxWidth: .infinity)
            }
        }
    }

    private var itemGroups: [(title: String, items: [ClipboardItem])] {
        let calendar = Calendar.current
        let items = viewState.visibleItems
        return [
            (L10n.tr("Pinned"), items.filter(\.isPinned)),
            (L10n.tr("Today"), items.filter { !$0.isPinned && calendar.isDateInToday($0.createdAt) }),
            (L10n.tr("Yesterday"), items.filter { !$0.isPinned && calendar.isDateInYesterday($0.createdAt) }),
            (
                L10n.tr("Earlier"),
                items.filter {
                    !$0.isPinned && !calendar.isDateInToday($0.createdAt) && !calendar.isDateInYesterday($0.createdAt)
                }
            ),
        ].filter { !$0.1.isEmpty }
    }

    private var listRows: [HistoryListRow] {
        itemGroups.flatMap { group in [.header(group.title)] + group.items.map(HistoryListRow.item) }
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(listRows) { row in
                        switch row {
                        case .header(let title):
                            Text(title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.top, 12)
                                .padding(.bottom, 5)
                        case .item(let item):
                            ClipboardRow(item: item, language: settings.language)
                                .padding(.horizontal, 10)
                                .frame(height: 36)
                                .background(
                                    viewState.selectedID == item.id
                                        ? Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.07) : .clear,
                                    in: RoundedRectangle(cornerRadius: 7)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture { viewState.selectedID = item.id }
                                // Selection must not wait for the double-click timeout.
                                .simultaneousGesture(TapGesture(count: 2).onEnded { onPaste(item) })
                                .contextMenu { contextMenu(for: item) }
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(
                                    viewState.selectedID == item.id ? [.isSelected, .isButton] : [.isButton]
                                )
                                .accessibilityAction { viewState.selectedID = item.id }
                                .accessibilityHint(L10n.tr("Double-click to paste"))
                                .id(item.id)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
            .onChange(of: viewState.selectedID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
            .onChange(of: viewState.selectedItem?.isPinned) { _, _ in
                Task { @MainActor in
                    await Task.yield()
                    if let id = viewState.selectedID { proxy.scrollTo(id) }
                }
            }
        }
    }

    @ViewBuilder private var preview: some View {
        if let item = viewState.selectedItem {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    switch item.kind {
                    case .image:
                        if let data = item.resolvedImageData, let image = NSImage(data: data) {
                            Image(nsImage: image).resizable().scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding()
                                .accessibilityLabel(item.customName ?? L10n.tr("Clipboard image"))
                        }
                    case .color:
                        ColorPreview(value: item.text ?? "")
                    case .file:
                        FilePreview(urls: item.fileURLs)
                    default:
                        ScrollView {
                            Text(item.text ?? "")
                                .font(.system(size: 13))
                                .lineSpacing(5)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding(24)
                        }
                        .scrollEdgeEffectSoftIfAvailable()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                metadata(item)
            }
            .background(.primary.opacity(0.015))
        }
    }

    private func metadata(_ item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("Information")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            HStack {
                Text(L10n.tr("Copied From")).foregroundStyle(.secondary)
                Spacer()
                SourceAppIcon(bundleIdentifier: item.sourceBundleIdentifier)
                    .frame(width: 14, height: 14).accessibilityHidden(true)
                Text(item.sourceApplicationName ?? L10n.tr("Unknown App"))
            }
            metadataRow("Content Type", value: item.kind.title)
            if item.kind == .file {
                if let url = item.fileURLs.first, item.fileURLs.count == 1 {
                    metadataRow("Path", value: (url.path as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(2).truncationMode(.middle).help(url.path)
                } else {
                    metadataRow("Files", value: item.fileURLs.count.formatted(.number.locale(L10n.locale)))
                }
            }
            if let text = item.text, item.kind != .image && item.kind != .file {
                metadataRow("Characters", value: text.count.formatted(.number.locale(L10n.locale)))
            }
            metadataRow("First Copied", value: L10n.date(item.createdAt))
            if item.useCount > 0 { metadataRow("Last Used", value: L10n.relativeDate(item.lastUsedAt)) }
        }
        .font(.system(size: 12))
        .padding(20)
    }

    private func metadataRow(_ key: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.tr(key)).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Image(systemName: settings.isPaused ? "pause.circle.fill" : "clipboard")
                .foregroundStyle(settings.isPaused ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            Text(L10n.tr("Clipboard History")).foregroundStyle(.secondary)
            Spacer()
            Button {
                if let item = viewState.selectedItem { onPaste(item) }
            } label: {
                HStack(spacing: 8) {
                    Text(L10n.tr(settings.pasteAutomatically ? "Paste to Active App" : "Copy to Clipboard"))
                    KeyCap(value: "↵")
                }
            }
            .buttonStyle(.plain)
            .disabled(viewState.selectedItem == nil)
            Divider().frame(height: 16)
            Button {
                viewState.toggleActions()
            } label: {
                HStack(spacing: 8) {
                    Text(L10n.tr("Actions"))
                    KeyCap(value: "⌘")
                    KeyCap(value: "K")
                }
            }
            .buttonStyle(.plain)
            .disabled(viewState.selectedItem == nil)
            .help(L10n.tr("Actions (⌘K)"))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                viewState.showActions ? Color.primary.opacity(0.08) : .clear,
                in: RoundedRectangle(cornerRadius: 10))
            if viewState.selectedItem == nil {
                Button(action: onSettings) { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).help(L10n.tr("Settings…"))
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(.primary.opacity(0.025))
    }

    @ViewBuilder private func contextMenu(for item: ClipboardItem) -> some View {
        Button {
            onPaste(item)
        } label: {
            Label(L10n.tr("Paste to Active App"), systemImage: "arrow.turn.down.left")
        }
        Button {
            onCopy(item)
        } label: {
            Label(L10n.tr("Copy to Clipboard"), systemImage: "doc.on.doc")
        }
        if item.kind == .link {
            Button {
                open(item)
            } label: {
                Label(L10n.tr("Open Link"), systemImage: "safari")
            }
        }
        if item.kind == .file {
            Button {
                open(item)
            } label: {
                Label(L10n.tr("Show in Finder"), systemImage: "folder")
            }
        }
        Divider()
        Button {
            onRename(item)
        } label: {
            Label(L10n.tr("Rename"), systemImage: "pencil")
        }
        Button {
            store.togglePin(item.id)
        } label: {
            Label(item.isPinned ? L10n.tr("Unpin") : L10n.tr("Pin"), systemImage: item.isPinned ? "pin.slash" : "pin")
        }
        Button(role: .destructive) {
            store.delete(item.id)
        } label: {
            Label(L10n.tr("Delete"), systemImage: "trash")
        }
        Divider()
        Button {
            onSettings()
        } label: {
            Label(L10n.tr("Settings…"), systemImage: "gearshape")
        }
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Label(L10n.tr("Clear Unpinned History…"), systemImage: "trash.slash")
        }
    }

    private func actions(for item: ClipboardItem) -> [ClipboardMenuAction] {
        var actions: [ClipboardMenuAction] = [
            .init(
                id: "paste", title: L10n.tr("Paste to Active App"), symbol: "arrow.turn.down.left",
                keys: ["↵"], group: 0, perform: { onPaste(item) }),
            .init(
                id: "copy", title: L10n.tr("Copy to Clipboard"), symbol: "clipboard",
                keys: ["⌘", "↵"], key: .return, modifiers: .command, group: 0, perform: { onCopy(item) }),
        ]
        if item.kind == .link || item.kind == .file {
            actions.append(
                .init(
                    id: "open", title: L10n.tr(item.kind == .file ? "Show in Finder" : "Open Link"),
                    symbol: item.kind == .file ? "folder" : "safari", keys: ["⌘", "O"],
                    key: "o", modifiers: .command, group: 0, perform: { open(item) }))
        }
        if item.kind == .image, let recognized = item.text, !recognized.isEmpty {
            actions.append(
                .init(
                    id: "ocr", title: L10n.tr("Copy Text from Image or QR"), symbol: "text.viewfinder",
                    group: 0, perform: { onCopyText(recognized) }))
        }
        actions += [
            .init(
                id: "rename", title: L10n.tr("Rename Entry"), symbol: "pencil", keys: ["⌘", "E"],
                key: "e", modifiers: .command, group: 1, perform: { onRename(item) }),
            .init(
                id: "pin", title: L10n.tr(item.isPinned ? "Unpin Entry" : "Pin Entry"),
                symbol: item.isPinned ? "pin.slash" : "pin", keys: ["⌘", "."],
                key: ".", modifiers: .command, group: 1, perform: { store.togglePin(item.id) }),
            .init(
                id: "delete", title: L10n.tr("Delete Entry"), symbol: "trash", keys: ["⌃", "X"],
                key: "x", modifiers: .control, group: 1, destructive: true, perform: { store.delete(item.id) }),
            .init(
                id: "settings", title: L10n.tr("Settings…"), symbol: "gearshape", keys: ["⌘", ","],
                key: ",", modifiers: .command, group: 2, perform: onSettings),
        ]
        return actions
    }

    private func open(_ item: ClipboardItem) {
        if item.kind == .link, let text = item.text, let url = URL(string: text) {
            NSWorkspace.shared.open(url)
        } else if item.kind == .file, let url = item.fileURLs.first {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        viewState.showActions = false
    }
}

private enum HistoryListRow: Identifiable {
    case header(String)
    case item(ClipboardItem)

    var id: String {
        switch self {
        case .header(let title): return "section-" + title
        case .item(let item): return item.id.uuidString
        }
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    let language: AppLanguage

    var body: some View {
        HStack {
            thumbnail.frame(width: OverlayMetrics.thumbnailSize, height: OverlayMetrics.thumbnailSize)
                .accessibilityHidden(true)
            Text(item.displayTitle).font(.system(size: 13)).lineLimit(1)
            Spacer()
            if item.isPinned {
                Image(systemName: "pin.fill").symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary).accessibilityLabel(L10n.tr("Pinned"))
            }
            SourceAppIcon(bundleIdentifier: item.sourceBundleIdentifier)
                .frame(width: OverlayMetrics.sourceIconSize, height: OverlayMetrics.sourceIconSize)
                .accessibilityHidden(true)
        }

    }

    @ViewBuilder private var thumbnail: some View {
        if item.kind == .image, let data = item.resolvedImageData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: OverlayMetrics.thumbnailSize, height: OverlayMetrics.thumbnailSize)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else if item.kind == .file {
            FileIconStack(urls: item.fileURLs, maximumIconSize: OverlayMetrics.thumbnailSize)
        } else if item.kind == .color {
            RoundedRectangle(cornerRadius: 6).fill(Color(hex: item.text ?? "") ?? .clear)
                .overlay { RoundedRectangle(cornerRadius: 6).stroke(.separator) }
        } else {
            Image(systemName: item.kind.symbol).symbolRenderingMode(.hierarchical).font(.system(size: 15))
                .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)

        }
    }
}

private struct ColorPreview: View {
    let value: String
    var body: some View {
        VStack {
            RoundedRectangle(cornerRadius: 20).fill(Color(hex: value) ?? .clear)
                .frame(width: 180, height: 180).overlay { RoundedRectangle(cornerRadius: 20).stroke(.separator) }
            Text(value.uppercased()).font(.title2.monospaced().weight(.semibold)).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine).accessibilityLabel(L10n.format("Color %@", value.uppercased()))
    }
}

private extension View {
    @ViewBuilder func scrollEdgeEffectSoftIfAvailable() -> some View {
        if #available(macOS 26.0, *) { scrollEdgeEffectStyle(.soft, for: .all) } else { self }
    }
}

private extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard [3, 6, 8].contains(cleaned.count), let value = UInt64(cleaned, radix: 16) else { return nil }
        let r, g, b, a: Double
        if cleaned.count == 3 {
            r = Double((value >> 8) & 0xF) / 15; g = Double((value >> 4) & 0xF) / 15
            b = Double(value & 0xF) / 15; a = 1
        } else {
            r = Double((value >> (cleaned.count == 8 ? 24 : 16)) & 0xFF) / 255
            g = Double((value >> (cleaned.count == 8 ? 16 : 8)) & 0xFF) / 255
            b = Double((value >> (cleaned.count == 8 ? 8 : 0)) & 0xFF) / 255
            a = cleaned.count == 8 ? Double(value & 0xFF) / 255 : 1
        }
        self.init(red: r, green: g, blue: b, opacity: a)
    }
}

// Raycast-style command-panel rhythm: compact rows, restrained surfaces and visible keycaps.
private struct KeyCap: View {
    let value: String
    var body: some View {
        Text(value).font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5).frame(height: 20)
            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
            .overlay { RoundedRectangle(cornerRadius: 4).stroke(.primary.opacity(0.05)) }
            .accessibilityHidden(true)
    }
}
