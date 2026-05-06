import SwiftUI

// MARK: - ChipToggle
//
// Linear-style chip that toggles between "outlined" (off) and
// "indigo-filled" (on) states. Used in the action / destination editors
// for Pin / Background / Auto-replace / "Show in action list" affordances.
//
// Visual rule (locked in DESIGN.md): outlined when off, `caiPrimary` at
// 12% opacity fill + `caiPrimary` border + `caiPrimary` icon/label when on.
// Hover highlights with a subtle wash, click flips state. Tooltip on hover
// surfaces a short (under 8 words) explanation.

struct ChipToggle: View {
    let label: String
    let icon: String
    let isOn: Bool
    let tooltip: String
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(isOn ? .caiPrimary : .caiTextSecondary)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isOn ? .caiPrimary : .caiTextSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(borderColor, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private var backgroundFill: Color {
        // Visible base even when off — matches `DestinationChip` and
        // `ChipButton` so the off-state still reads as a chip (not as
        // floating text). Hover brightens; on flips to indigo.
        if isOn { return Color.caiPrimary.opacity(0.12) }
        if isHovered { return Color.caiSurface.opacity(0.8) }
        return Color.caiSurface.opacity(0.5)
    }

    private var borderColor: Color {
        if isOn { return Color.caiPrimary.opacity(0.4) }
        return Color(nsColor: .separatorColor).opacity(0.5)
    }
}

// MARK: - ChipButton
//
// Disclosure / action chip. Distinct from `ChipToggle` (on/off boolean)
// — this one is for "click to do something" affordances like the
// "Then run" expand/collapse chip in the action editor.
//
// **Visual alignment with `ChipToggle` (2026-05-06 feedback):** when
// inactive, ChipButton renders with the same fill + border + label
// colors as ChipToggle's off-state, so a row of mixed chips
// ("Then run · 4" + "Silent" + "Auto-replace") reads as one visual
// vocabulary. When active (chain has steps), ChipButton uses a subtle
// indigo wash + lighter indigo border — softer than ChipToggle's bold
// on-state so the user can still tell "engaged disclosure" apart from
// "boolean ON."

struct ChipButton: View {
    let label: String
    let icon: String
    /// Whether the chip's underlying disclosure is "engaged" (e.g., chain
    /// has steps so the chip carries a count). Brightens label/icon to
    /// `caiTextPrimary` and adds a subtle indigo tint + border. Distinct
    /// from `ChipToggle`'s bolder "on" state.
    let isActive: Bool
    let tooltip: String
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(isActive ? .caiPrimary : .caiTextSecondary)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isActive ? .caiTextPrimary : .caiTextSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(borderColor, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private var backgroundFill: Color {
        if isActive {
            return isHovered
                ? Color.caiPrimary.opacity(0.10)
                : Color.caiPrimary.opacity(0.06)
        }
        return isHovered
            ? Color.caiSurface.opacity(0.8)
            : Color.caiSurface.opacity(0.5)
    }

    private var borderColor: Color {
        if isActive { return Color.caiPrimary.opacity(0.25) }
        return Color(nsColor: .separatorColor).opacity(0.5)
    }
}
