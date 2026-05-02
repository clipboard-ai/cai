import SwiftUI

/// Settings sub-screen for toggling visibility of built-in actions.
/// Mirrors the row layout of `ConnectorsSettingsView`:
/// `[icon] [label + scope subtitle] [Spacer] [toggle]` inside a rounded card.
/// Single section — scope info lives in the per-row subtitle so the user sees
/// at a glance which actions are universal vs. type-specific.
///
/// Hidden actions stay reachable via type-to-filter in the main action list
/// (see `ActionGenerator.generateAllActions`).
struct BuiltInActionsView: View {
    @ObservedObject var settings = CaiSettings.shared
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.caiPrimary)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Built-in Actions")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.caiTextPrimary)

                    Text("\(visibleCount) of \(BuiltInActionID.allCases.count) visible")
                        .font(.system(size: 11))
                        .foregroundColor(.caiTextSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
                .background(Color.caiDivider)

            // Content — one row per action, Connectors-style cards
            ScrollView {
                VStack(spacing: 6) {
                    Text("Hidden actions remain accessible by typing to filter in the action list.")
                        .font(.system(size: 10))
                        .foregroundColor(.caiTextSecondary.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)

                    ForEach(BuiltInActionID.allCases, id: \.rawValue) { action in
                        actionRow(action)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }

            Spacer(minLength: 0)

            Divider()
                .background(Color.caiDivider)

            // Footer
            HStack(spacing: 12) {
                KeyboardHint(key: "Esc", label: "Back")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Helpers

    private var visibleCount: Int {
        BuiltInActionID.allCases.filter { !settings.hiddenBuiltInActions.contains($0.rawValue) }.count
    }

    /// Single row mirroring `ConnectorsSettingsView`'s connector row:
    /// 20pt-frame leading icon, label + subtitle, indigo switch on the right.
    /// No chevron — toggling is the only interaction.
    private func actionRow(_ action: BuiltInActionID) -> some View {
        let isVisible = !settings.hiddenBuiltInActions.contains(action.rawValue)

        return HStack(spacing: 10) {
            Image(systemName: action.iconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isVisible ? .caiPrimary : .caiTextSecondary.opacity(0.5))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(action.displayLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.caiTextPrimary)

                Text(action.scopeDescription)
                    .font(.system(size: 10))
                    .foregroundColor(.caiTextSecondary.opacity(0.7))
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { !settings.hiddenBuiltInActions.contains(action.rawValue) },
                set: { newVisible in
                    if newVisible {
                        settings.hiddenBuiltInActions.remove(action.rawValue)
                    } else {
                        settings.hiddenBuiltInActions.insert(action.rawValue)
                    }
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(.caiPrimary)
            .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.caiSurface.opacity(0.3))
        )
    }
}
