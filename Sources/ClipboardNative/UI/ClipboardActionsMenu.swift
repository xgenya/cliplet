import SwiftUI

enum ClipboardPanelFocus: Hashable {
    case history, actions
}

struct ClipboardMenuAction: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var keys: [String] = []
    var key: KeyEquivalent?
    var modifiers: EventModifiers = []
    let group: Int
    var destructive = false
    let perform: () -> Void
}

struct ClipboardActionsMenu: View {
    let actions: [ClipboardMenuAction]
    var focus: FocusState<ClipboardPanelFocus?>.Binding
    let onDismiss: () -> Void
    @State private var selectedID: String?
    @State private var didInvoke = false

    private var groups: [Int] { Array(Set(actions.map(\.group))).sorted() }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(groups, id: \.self) { group in
                            if group != groups.first { Divider().padding(.vertical, 8) }
                            ForEach(actions.filter { $0.group == group }) { action in
                                actionRow(action).id(action.id)
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(
                    height: min(
                        400, max(40, CGFloat(actions.count) * 40 + CGFloat(max(0, groups.count - 1)) * 17 + 16))
                )
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: selectedID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused(focus, equals: .actions)
        .onKeyPress(.return) {
            if let action = actions.first(where: { $0.id == selectedID }) { invoke(action) }
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(1); return .handled
        }
        .onKeyPress(.upArrow) {
            moveSelection(-1); return .handled
        }

        .onAppear {
            selectedID = actions.first?.id

        }
        .task {
            // Wait until the conditional overlay is in the focus tree.
            await Task.yield()
            focus.wrappedValue = .actions
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.tr("Actions"))
    }

    @ViewBuilder private func actionRow(_ action: ClipboardMenuAction) -> some View {
        if let key = action.key {
            button(action).keyboardShortcut(key, modifiers: action.modifiers)
        } else {
            button(action)
        }
    }

    private func button(_ action: ClipboardMenuAction) -> some View {
        Button {
            invoke(action)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: action.symbol)
                    .font(.system(size: 16))
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(action.title).font(.system(size: 13)).lineLimit(2)
                Spacer(minLength: 8)
                HStack(spacing: 3) {
                    ForEach(Array(action.keys.enumerated()), id: \.offset) { _, key in
                        Text(key)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 23, minHeight: 23)
                            .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .accessibilityHidden(true)
            }
            .foregroundStyle(action.destructive ? Color.red : .primary)
            .padding(.horizontal, 10)
            .frame(height: 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selectedID == action.id ? Color.primary.opacity(0.10) : .clear,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in if hovering { selectedID = action.id } }
        .accessibilityAddTraits(selectedID == action.id ? [.isSelected] : [])
    }

    private func moveSelection(_ offset: Int) {
        guard !actions.isEmpty else { return }
        let index = actions.firstIndex { $0.id == selectedID } ?? 0
        selectedID = actions[min(max(index + offset, 0), actions.count - 1)].id
    }

    private func invoke(_ action: ClipboardMenuAction) {
        guard !didInvoke else { return }
        didInvoke = true
        onDismiss()
        action.perform()
    }
}
