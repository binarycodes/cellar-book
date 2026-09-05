import SwiftUI

// MARK: - Buttons

/// The design's primary action: 50pt tall, 9pt radius, burgundy.
struct PrimaryButton: View {
    let title: String
    var icon: String?
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let icon { Image(systemName: icon).font(.system(size: 17, weight: .medium)) }
                Text(title).font(Typo.sans(15, 600))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(enabled ? Palette.burgundy : Palette.rose(0.14))
            .foregroundStyle(enabled ? Palette.ink : Palette.textMuted)
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .disabled(!enabled)
    }
}

/// The outlined secondary action used for "Dictate a note" and sheet cancels.
struct OutlineButton: View {
    let title: String
    var icon: String?
    var height: CGFloat = 46
    var fillsWidth: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            OutlineLabel(title: title, icon: icon, height: height, fillsWidth: fillsWidth)
        }
    }
}

/// The outline button's look, for callers that must supply their own control
/// (a `PhotosPicker`, say) rather than a `Button`.
struct OutlineLabel: View {
    let title: String
    var icon: String?
    var height: CGFloat = 46
    var fillsWidth: Bool = true

    var body: some View {
        HStack(spacing: 9) {
            if let icon { Image(systemName: icon).font(.system(size: 17, weight: .medium)) }
            Text(title).font(Typo.sans(14, 500))
        }
        .frame(maxWidth: fillsWidth ? CGFloat.infinity : nil)
        .frame(height: height)
        .padding(.horizontal, fillsWidth ? 0 : 14)
        .foregroundStyle(Palette.textPrimary)
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.border, lineWidth: 1))
    }
}

/// Round 44pt glass button over the detail hero.
struct CircleGlassButton: View {
    let systemName: String
    var size: CGFloat = 20
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.35), in: Circle())
                .background(.ultraThinMaterial, in: Circle())
        }
    }
}

// MARK: - Chips and tags

/// The underlined filter tab across the cellar and search screens.
struct FilterChip: View {
    let label: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(label)
                    .font(Typo.sans(13, 500))
                    .tracking(-13 * 0.005)
                    .foregroundStyle(active ? Palette.textPrimary : Palette.textFaint)
                    .fixedSize()
                Spacer(minLength: 0)
                Rectangle()
                    .fill(active ? Color.white : .clear)
                    .frame(height: 2)
            }
            .frame(height: 26)
        }
        .buttonStyle(.plain)
    }
}

/// The pill used for status and verdict.
struct TagPill: View {
    let text: String
    var foreground: Color = Palette.rose(0.7)
    var background: Color = Palette.rose(0.08)

    var body: some View {
        Text(text)
            .font(Typo.sans(11, 500))
            .tracking(11 * 0.02)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .frame(height: 23)
            .background(background, in: Capsule())
            .overlay(Capsule().stroke(foreground.opacity(0.30), lineWidth: 1))
            .fixedSize()
    }
}

/// The keenness segmented control on the detail screen.
struct SegmentButton: View {
    let title: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typo.sans(13, 500))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .foregroundStyle(active ? Palette.ink : Palette.rose(0.7))
                .background(active ? Palette.burgundy : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(active ? Palette.burgundy : Palette.border, lineWidth: 1)
                )
        }
    }
}

/// A coloured dot — status rails, timeline nodes, verdict markers.
struct Dot: View {
    let color: Color
    var size: CGFloat = 7
    var body: some View { Circle().fill(color).frame(width: size, height: size) }
}

// MARK: - Fields

/// The design's boxed input: 44pt, 9pt radius, hairline border, 6% fill.
struct BoxedField: View {
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var monospacedDigits = false
    var height: CGFloat = 44

    /// A `TextField` only occupies its intrinsic line height, so inside a 44pt
    /// box the bands above and below it are dead space — taps there land on the
    /// container and focus nothing. Focus is forwarded explicitly so the whole
    /// box behaves like the control it looks like.
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, prompt:
            Text(placeholder).foregroundStyle(Palette.rose(0.40))
        )
        .font(monospacedDigits ? Typo.sans(16).monospacedDigit() : Typo.sans(16))
        .foregroundStyle(.white)
        .keyboardType(keyboard)
        .autocorrectionDisabled()
        .focused($focused)
        .padding(.horizontal, 11)
        .frame(height: height)
        .background(Palette.fieldFill)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.border, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onTapGesture { focused = true }
    }
}

/// The underlined field used for producer and cuvée on the Review screen.
struct UnderlineField: View {
    let placeholder: String
    @Binding var text: String
    var font: Font
    var bottomPadding: CGFloat

    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, prompt:
            Text(placeholder).foregroundStyle(Palette.rose(0.40))
        )
        .font(font)
        .foregroundStyle(.white)
        .autocorrectionDisabled()
        .focused($focused)
        .padding(.bottom, bottomPadding)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.borderSoft).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}

/// Multi-line note entry.
struct NoteEditor: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 86

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(Typo.sans(16))
                    .foregroundStyle(Palette.rose(0.40))
                    .lineSpacing(16 * 0.5)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 19)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(Typo.sans(16))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 7)
                .padding(.vertical, 11)
        }
        .frame(minHeight: minHeight)
        .background(Palette.fieldFill)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.border, lineWidth: 1))
    }
}

// MARK: - Notes

/// A note with its left rule, icon and timestamp.
struct NoteBlock: View {
    let icon: String
    let label: String
    let text: String
    var rule: Color = Palette.rose(0.2)
    var textOpacity: Double = 0.9

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11))
                Text(label).font(Typo.sans(11))
            }
            .foregroundStyle(Palette.textMuted)

            Text(text)
                .font(Typo.sans(15))
                .lineSpacing(15 * 0.6)
                .foregroundStyle(Palette.rose(textOpacity))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle().fill(rule).frame(width: 2)
        }
    }
}

// MARK: - Toast

struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold))
            Text(message).font(Typo.sans(14, 500))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.ground)
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background(Palette.ink)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .shadow(color: .black.opacity(0.6), radius: 14, y: 8)
    }
}

// MARK: - Sheet chrome

/// The grab handle every bottom sheet carries.
struct SheetHandle: View {
    var body: some View {
        Capsule()
            .fill(Palette.rose(0.25))
            .frame(width: 38, height: 4)
            .frame(maxWidth: .infinity)
    }
}

/// Shared bottom-sheet container: surface fill, top corners, hairline top edge.
struct BottomSheet<Content: View>: View {
    var horizontalPadding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            SheetHandle().padding(.top, 18).padding(.bottom, 18)
            content
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity)
        .background(Palette.surface)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 15, topTrailingRadius: 15))
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.borderHair).frame(height: 1)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// The design's paired sheet actions: a secondary at `flex:1` beside a
/// primary at `flex:2`. SwiftUI has no flex-grow — `layoutPriority` starves
/// the low-priority sibling to zero rather than splitting 1:2 — so the widths
/// are measured and divided explicitly.
struct SplitActionRow: View {
    let secondaryTitle: String
    let primaryTitle: String
    var height: CGFloat = 48
    let secondary: () -> Void
    let primary: () -> Void

    var body: some View {
        GeometryReader { geo in
            let unit = (geo.size.width - 8) / 3
            HStack(spacing: 8) {
                Button(action: secondary) {
                    Text(secondaryTitle)
                        .font(Typo.sans(15, 500))
                        .frame(width: unit, height: height)
                        .foregroundStyle(.white)
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.border, lineWidth: 1))
                }
                Button(action: primary) {
                    Text(primaryTitle)
                        .font(Typo.sans(15, 600))
                        .frame(width: unit * 2, height: height)
                        .background(Palette.burgundy)
                        .foregroundStyle(Palette.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }
            }
        }
        .frame(height: height)
    }
}
