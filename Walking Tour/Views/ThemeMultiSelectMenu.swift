import SwiftUI

struct ThemeMultiSelectMenu: View {
    @Binding var themes: [TourTheme]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Menu {
            ForEach(TourTheme.allCases) { theme in
                Button {
                    toggle(theme)
                } label: {
                    Label {
                        Text(theme.label)
                    } icon: {
                        if themes.contains(theme) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(themes.displayLabel)
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.accentText(for: colorScheme))
                    Text(themes.count == 1 ? "1 theme selected" : "\(themes.count) themes selected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.primary(for: colorScheme))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppTheme.fieldBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppTheme.cardBorder(for: colorScheme), lineWidth: 1)
            }
        }
    }

    private func toggle(_ theme: TourTheme) {
        if let index = themes.firstIndex(of: theme) {
            themes.remove(at: index)
            if themes.isEmpty {
                themes = [.highlights]
            }
        } else if theme == .highlights {
            themes = [.highlights]
        } else {
            themes.removeAll { $0 == .highlights }
            themes.append(theme)
        }
    }
}
