import SwiftUI
import UIKit

/// Light and dark values for every color. Evening routines happen in the dark, so dark mode is first class.
enum NextCueStyle {
    static let background = adaptive(light: (0.965, 0.961, 0.941), dark: (0.075, 0.086, 0.090))
    static let surface = adaptive(light: (1, 1, 1), dark: (0.125, 0.141, 0.145))
    static let ink = adaptive(light: (0.145, 0.192, 0.204), dark: (0.925, 0.937, 0.925))
    static let secondary = adaptive(light: (0.392, 0.443, 0.451), dark: (0.620, 0.667, 0.667))
    static let accent = adaptive(light: (0.216, 0.431, 0.443), dark: (0.439, 0.718, 0.710))
    /// Text and symbols drawn on top of `accent`.
    static let onAccent = adaptive(light: (1, 1, 1), dark: (0.047, 0.110, 0.118))
    static let accentWash = adaptive(light: (0.882, 0.929, 0.918), dark: (0.137, 0.212, 0.212))
    static let warm = adaptive(light: (0.769, 0.463, 0.180), dark: (0.910, 0.690, 0.451))
    static let warmWash = adaptive(light: (0.980, 0.925, 0.867), dark: (0.231, 0.180, 0.129))
    static let line = adaptive(light: (0.867, 0.878, 0.855), dark: (0.216, 0.243, 0.247))
    static let success = adaptive(light: (0.333, 0.506, 0.412), dark: (0.525, 0.745, 0.604))
    static let danger = adaptive(light: (0.647, 0.322, 0.278), dark: (0.902, 0.553, 0.502))

    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: value.0, green: value.1, blue: value.2, alpha: 1)
        })
    }
}

enum NextCueFormat {
    static func time(hour: Int, minute: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
        return time(date)
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func minutes(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }

    /// "4:07" for time on a step.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func steps(_ count: Int) -> String {
        "\(count) \(count == 1 ? "step" : "steps")"
    }
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
    var height: CGFloat = 56
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.bold))
            .foregroundStyle(NextCueStyle.onAccent)
            .frame(maxWidth: .infinity, minHeight: height)
            .opacity(isEnabled ? 1 : 0.6)
            .background(NextCueStyle.accent.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// Cards that act as buttons: a soft press instead of the default highlight.
struct NextCuePressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
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
    var shortName: String { Calendar.current.veryShortWeekdaySymbols[rawValue - 1] }
    var fullName: String { Calendar.current.weekdaySymbols[rawValue - 1] }

    /// Weekdays in the order the user's calendar starts the week.
    static var ordered: [NextCueWeekday] {
        let first = Calendar.current.firstWeekday
        return allCases.sorted { ($0.rawValue - first + 7) % 7 < ($1.rawValue - first + 7) % 7 }
    }
}
