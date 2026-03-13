import SwiftUI

struct ForgieStatusGlyph: View {
    let active: Bool

    var body: some View {
        ForgieMark(size: 56, active: active)
    }
}

struct ForgieMark: View {
    let size: CGFloat
    let active: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            forgeGlow.opacity(active ? 0.42 : 0.18),
                            appAccent.opacity(active ? 0.26 : 0.10),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: size * 0.55
                    )
                )
                .overlay(
                    Circle()
                        .fill(Color(red: 0.23, green: 0.13, blue: 0.08))
                        .padding(size * 0.08)
                )
                .overlay(
                    Circle()
                        .stroke(borderColor, lineWidth: 1.2)
                )
            FoxEarShape()
                .fill(appAccent)
                .frame(width: size * 0.24, height: size * 0.24)
                .offset(x: -size * 0.16, y: -size * 0.24)
            FoxEarShape()
                .fill(appAccent)
                .frame(width: size * 0.24, height: size * 0.24)
                .offset(x: size * 0.16, y: -size * 0.24)
            FoxEarShape()
                .fill(forgeGlow.opacity(0.82))
                .frame(width: size * 0.12, height: size * 0.12)
                .offset(x: -size * 0.16, y: -size * 0.22)
            FoxEarShape()
                .fill(forgeGlow.opacity(0.82))
                .frame(width: size * 0.12, height: size * 0.12)
                .offset(x: size * 0.16, y: -size * 0.22)
            Circle()
                .fill(forgeGlow.opacity(0.92))
                .frame(width: size * 0.42, height: size * 0.30)
                .offset(y: size * 0.14)
            HStack(spacing: size * 0.15) {
                Circle()
                    .fill(Color.black.opacity(0.72))
                    .frame(width: size * 0.06, height: size * 0.06)
                Circle()
                    .fill(Color.black.opacity(0.72))
                    .frame(width: size * 0.06, height: size * 0.06)
            }
            .offset(y: -size * 0.02)
            Circle()
                .fill(Color.black.opacity(0.65))
                .frame(width: size * 0.08, height: size * 0.08)
                .offset(y: size * 0.10)
        }
        .frame(width: size, height: size)
    }
}

struct FoxEarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct FlowWrap: View {
    let items: [String]
    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(panelBackground, in: Capsule())
            }
        }
    }
}

struct PanelCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(16)
        .background(forgePanelFill, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(borderColor, lineWidth: 1)
        )
        .shadow(color: appAccent.opacity(0.10), radius: 18, x: 0, y: 10)
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(16)
        .background(forgePanelFill, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(borderColor, lineWidth: 1)
        )
    }
}

struct LabeledRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}

struct LabeledTextEditor: View {
    let label: String
    @Binding var text: String
    let minHeight: CGFloat
    let font: Font

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(font)
                .frame(minHeight: minHeight)
                .padding(10)
                .background(inputBackground, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(borderColor, lineWidth: 1)
                )
        }
    }
}

struct LabeledReadOnlyCode: View {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(inputBackground, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(borderColor, lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LabeledField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(label, text: $text)
                .textFieldStyle(.plain)
                .padding(10)
                .background(inputBackground, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(borderColor, lineWidth: 1)
                )
        }
    }
}

struct ChatMessageBubble: View {
    let entry: TranscriptEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if entry.role != .user {
                Text(entry.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(entry.body)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(entry.role == .user ? appAccent.opacity(0.20) : inputBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(entry.role == .user ? appAccent.opacity(0.26) : borderColor, lineWidth: 1)
        )
        .frame(maxWidth: 420, alignment: entry.role == .user ? .trailing : .leading)
    }
}

struct SoftBadge: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(inputBackground, in: Capsule())
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: 1)
        )
    }
}
