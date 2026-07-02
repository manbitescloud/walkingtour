import SwiftUI

enum AppTheme {
    static func primary(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.45, green: 0.68, blue: 1.0)
            : Color(red: 0.12, green: 0.35, blue: 0.82)
    }

    static func secondary(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.30, green: 0.55, blue: 0.95)
            : Color(red: 0.28, green: 0.52, blue: 0.92)
    }

    static func accentText(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white
            : Color(red: 0.04, green: 0.10, blue: 0.24)
    }

    static func cardBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.14, green: 0.17, blue: 0.24)
            : Color.white
    }

    static func cardBorder(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.12)
            : Color(red: 0.12, green: 0.35, blue: 0.82).opacity(0.18)
    }

    static func fieldBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.10, green: 0.13, blue: 0.20)
            : Color(red: 0.94, green: 0.96, blue: 0.99)
    }

    static func summaryBarBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.12, green: 0.16, blue: 0.24)
            : Color(red: 0.90, green: 0.94, blue: 1.0)
    }

    static func backgroundGradient(for scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.09, blue: 0.14),
                    Color(red: 0.10, green: 0.14, blue: 0.22),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color(red: 0.92, green: 0.95, blue: 1.0),
                Color(red: 0.97, green: 0.98, blue: 1.0),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func buttonGradient(for scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [primary(for: scheme), secondary(for: scheme)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // Legacy static accessors for map markers etc.
    static var primary: Color { primary(for: .light) }
    static var secondary: Color { secondary(for: .light) }
}

struct ThemedBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AppTheme.backgroundGradient(for: colorScheme)
            .ignoresSafeArea()
    }
}

struct ThemedSectionHeader: View {
    let title: String
    let icon: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Label(title, systemImage: icon)
            .font(.subheadline.bold())
            .foregroundStyle(AppTheme.accentText(for: colorScheme))
    }
}

struct ThemedCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .background(AppTheme.cardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AppTheme.cardBorder(for: colorScheme), lineWidth: 1)
            }
    }
}

struct PrimaryActionButton: View {
    let title: String
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack {
                Spacer()
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .padding(.trailing, 8)
                }
                Text(title)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(
                AppTheme.buttonGradient(for: colorScheme)
                    .opacity(isEnabled ? 1 : 0.45),
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
        .disabled(!isEnabled || isLoading)
    }
}
