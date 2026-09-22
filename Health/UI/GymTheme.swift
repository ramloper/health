import SwiftUI
import UIKit

final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    @Published var isDark: Bool {
        didSet { UserDefaults.standard.set(isDark, forKey: "gym.isDark") }
    }
    @Published var restSeconds: Int {
        didSet { UserDefaults.standard.set(restSeconds, forKey: "gym.restSeconds") }
    }

    init() {
        if UserDefaults.standard.object(forKey: "gym.isDark") == nil {
            isDark = true
        } else {
            isDark = UserDefaults.standard.bool(forKey: "gym.isDark")
        }
        let rest = UserDefaults.standard.integer(forKey: "gym.restSeconds")
        restSeconds = rest == 0 ? 90 : rest
    }

    var palette: GymPalette { isDark ? .dark : .light }
}

struct GymPalette {
    var bg: Color
    var card: Color
    var elevated: Color
    var text: Color
    var muted: Color
    var faint: Color
    var accent: Color
    var accentSoft: Color
    var hairline: Color
    var onAccent: Color
    var tabIdle: Color
    var isDark: Bool

    static let dark = GymPalette(
        bg: Color(hex: 0x17171C),
        card: Color(hex: 0x202027),
        elevated: Color(hex: 0x2C2C35),
        text: Color(hex: 0xF2F4F6),
        muted: Color(hex: 0xB0B8C1),
        faint: Color(hex: 0x8B95A1),
        accent: Color(hex: 0xE82127),
        accentSoft: Color(hex: 0xE82127).opacity(0.16),
        hairline: Color(hex: 0x202027),
        onAccent: .white,
        tabIdle: Color(hex: 0x6B7684),
        isDark: true
    )

    static let light = GymPalette(
        bg: Color(hex: 0xF2F4F6),
        card: .white,
        elevated: Color(hex: 0xF2F4F6),
        text: Color(hex: 0x191F28),
        muted: Color(hex: 0x4E5968),
        faint: Color(hex: 0x8B95A1),
        accent: Color(hex: 0xE82127),
        accentSoft: Color(hex: 0xE82127).opacity(0.12),
        hairline: Color(hex: 0xE5E8EB),
        onAccent: .white,
        tabIdle: Color(hex: 0x6B7684),
        isDark: false
    )
}

enum Gym {
    static var p: GymPalette { ThemeStore.shared.palette }

    static var bg: Color { p.bg }
    static var card: Color { p.card }
    static var elevated: Color { p.elevated }
    static var text: Color { p.text }
    static var muted: Color { p.muted }
    static var faint: Color { p.faint }
    static var accent: Color { p.accent }
    static var lime: Color { p.accent }
    static var limeDim: Color { p.accentSoft }
    static var accentSoft: Color { p.accentSoft }
    static var hairline: Color { p.hairline }
    static var onAccent: Color { p.onAccent }
    static var tabIdle: Color { p.tabIdle }
    static var cardStroke: Color { p.isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.04) }
    static let radius: CGFloat = 20

    static func applyChrome(isDark: Bool = ThemeStore.shared.isDark) {
        let bgUI = UIColor(hex: isDark ? 0x17171C : 0xF2F4F6)
        let textUI = UIColor(hex: isDark ? 0xF2F4F6 : 0x191F28)
        let accentUI = UIColor(hex: 0xE82127)

        if #unavailable(iOS 18.0) {
            let idleUI = UIColor(hex: 0x6B7684)
            let hairUI = UIColor(hex: isDark ? 0x202027 : 0xE5E8EB)
            let tab = UITabBarAppearance()
            tab.configureWithOpaqueBackground()
            tab.backgroundColor = bgUI
            tab.shadowColor = hairUI
            let item = UITabBarItemAppearance()
            item.normal.iconColor = idleUI
            item.normal.titleTextAttributes = [.foregroundColor: idleUI]
            item.selected.iconColor = textUI
            item.selected.titleTextAttributes = [.foregroundColor: textUI]
            tab.stackedLayoutAppearance = item
            tab.inlineLayoutAppearance = item
            tab.compactInlineLayoutAppearance = item
            UITabBar.appearance().standardAppearance = tab
            UITabBar.appearance().scrollEdgeAppearance = tab
            UITabBar.appearance().tintColor = textUI
            UITabBar.appearance().unselectedItemTintColor = idleUI
        }

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = bgUI
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: textUI]
        nav.largeTitleTextAttributes = [.foregroundColor: textUI]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().tintColor = accentUI
    }
}

struct GymCard<Content: View>: View {
    var padding: CGFloat = 16
    var content: Content
    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Gym.card)
            .clipShape(RoundedRectangle(cornerRadius: Gym.radius, style: .continuous))
            .shadow(color: ThemeStore.shared.isDark ? .clear : .black.opacity(0.06), radius: 10, y: 2)
    }
}

struct GymCTA: View {
    var title: String
    var enabled: Bool = true
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Gym.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(enabled ? Gym.accent : Gym.accent.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct GymIndexBadge: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Gym.muted)
            .frame(width: 36, height: 36)
            .background(Gym.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct NudgeButton: View {
    var system: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.body.weight(.bold))
                .foregroundStyle(Gym.text)
                .frame(width: 36, height: 36)
                .background(Gym.elevated)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

extension UIColor {
    convenience init(hex: UInt, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

extension Double {
    var gymKg: String {
        truncatingRemainder(dividingBy: 1) == 0 ? String(Int(self)) : String(format: "%g", self)
    }
}

extension ProgramSchedule {
    var kindLabel: String {
        if isCustom { return "커스텀" }
        switch id {
        case FiveThreeOneBBBEngine.id, NSuns5DayEngine.id, StartingStrengthEngine.id:
            return "스트렝스"
        default:
            return "근비대"
        }
    }
}
