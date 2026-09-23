import SwiftUI

enum NextCueStyle {
    static let background = Color(red: 0.965, green: 0.961, blue: 0.941)
    static let surface = Color.white
    static let ink = Color(red: 0.145, green: 0.192, blue: 0.204)
    static let secondary = Color(red: 0.392, green: 0.443, blue: 0.451)
    static let accent = Color(red: 0.216, green: 0.431, blue: 0.443)
    static let accentWash = Color(red: 0.882, green: 0.929, blue: 0.918)
    static let warm = Color(red: 0.886, green: 0.663, blue: 0.420)
    static let line = Color(red: 0.867, green: 0.878, blue: 0.855)
    static let success = Color(red: 0.333, green: 0.506, blue: 0.412)
    static let danger = Color(red: 0.647, green: 0.322, blue: 0.278)
}

struct NextCueCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NextCueStyle.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(NextCueStyle.line.opacity(0.7), lineWidth: 1)
            }
    }
}

struct NextCuePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(NextCueStyle.accent.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct NextCueSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(NextCueStyle.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(NextCueStyle.accentWash.opacity(configuration.isPressed ? 0.65 : 1), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

struct NextCueSectionTitle: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(NextCueStyle.ink)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(NextCueStyle.secondary)
            }
        }
    }
}

struct NextCueIcon: View {
    let symbol: String
    var tint: Color = NextCueStyle.accent

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 42, height: 42)
            .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityHidden(true)
    }
}

enum NextCueWeekday: Int, CaseIterable, Identifiable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    var id: Int { rawValue }
    var shortName: String {
        switch self {
        case .sunday: "S"
        case .monday: "M"
        case .tuesday: "T"
        case .wednesday: "W"
        case .thursday: "T"
        case .friday: "F"
        case .saturday: "S"
        }
    }
    var fullName: String {
        Calendar.current.weekdaySymbols[rawValue - 1]
    }
}
