import SwiftUI
import LoopCore

// Stijl D (goedgekeurd 15 okt): donker, kaarten, witte primaire knop, oranje accent spaarzaam.

enum Theme {
    static let background = Color(hex: 0x0B0D10)
    static let panel = Color(hex: 0x1C2027)
    static let card = Color(hex: 0x22272F)
    static let cardBorder = Color(hex: 0x2E3440)
    static let sunken = Color(hex: 0x15181D)
    static let text = Color(hex: 0xF3F5F8)
    static let muted = Color(hex: 0xB4BCC8)
    static let secondary = Color(hex: 0x98A2B3)
    static let tertiary = Color(hex: 0x7C8696)
    static let track = Color(hex: 0x3A4250)
    static let outline = Color(hex: 0x4A5262)
    static let accent = Color(hex: 0xFF7A1A)
    static let good = Color(hex: 0x4CC38A)
    static let warn = Color(hex: 0xF2B32A)

    static let margin: CGFloat = 16
    static let radius: CGFloat = 22
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - Kleur en naam per type

extension WorkoutType {
    /// Typekleur als hex, ook doorgegeven aan de Live Activity (die geen SwiftUI-kleuren deelt).
    var hex: UInt32 {
        switch self {
        case .easy, .recovery: return 0x4CC38A
        case .long: return 0x5B8CFF
        case .tempo: return 0xF2B32A
        case .interval: return 0xFF6B3D
        case .fartlek: return 0xE05BA0
        case .progression: return 0x9B7BFF
        case .test: return 0xF0524F
        }
    }

    var color: Color { Color(hex: hex) }

    var label: String {
        switch self {
        case .easy: return "RUSTIG"
        case .long: return "LANG"
        case .tempo: return "TEMPO"
        case .interval: return "INTERVAL"
        case .fartlek: return "FARTLEK"
        case .progression: return "PROGRESSIE"
        case .recovery: return "HERSTEL"
        case .test: return "TIJDRIT"
        }
    }
}

extension PaceZone {
    var color: Color {
        switch self {
        case .recovery, .easy: return Theme.good
        case .marathon: return Color(hex: 0x9B7BFF)
        case .threshold: return Color(hex: 0xF2B32A)
        case .interval: return Color(hex: 0xFF6B3D)
        case .repetition: return Color(hex: 0xF0524F)
        }
    }
}

// MARK: - Tekst

enum Fmt {
    /// 4.6 -> "4,6"
    static func decimal(_ x: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f", x).replacingOccurrences(of: ".", with: ",")
    }

    /// Meters -> "4,62 km"
    static func km2(_ meters: Double) -> String {
        decimal(meters / 1000, digits: 2) + " km"
    }

    /// Seconden -> "± 29 min"
    static func minutes(_ seconds: Double) -> String {
        "± \(Int((seconds / 60).rounded())) min"
    }
}

enum DateText {
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "nl_BE")
        f.calendar = PlanCalendar.default
        f.timeZone = .current
        f.dateFormat = format
        return f
    }

    private static let shortF = formatter("EEE d MMM")
    private static let longF = formatter("EEEE d MMMM")
    private static let yearF = formatter("EEE d MMM yyyy")
    private static let dayF = formatter("d")
    private static let timeF = formatter("HH:mm")
    private static let monthF = formatter("LLLL yyyy")

    /// "ma 19 okt"
    static func short(_ d: Date) -> String { clean(shortF.string(from: d)) }
    /// "maandag 19 oktober"
    static func long(_ d: Date) -> String { longF.string(from: d) }
    /// "Maandag 19 oktober"
    static func longCapitalized(_ d: Date) -> String {
        let s = long(d)
        return s.prefix(1).uppercased() + s.dropFirst()
    }
    /// "zo 10 jan 2027"
    static func withYear(_ d: Date) -> String { clean(yearF.string(from: d)) }
    /// "19"
    static func dayNumber(_ d: Date) -> String { dayF.string(from: d) }
    /// "18:42"
    static func time(_ d: Date) -> String { timeF.string(from: d) }
    /// "oktober 2026"
    static func monthYear(_ d: Date) -> String { monthF.string(from: d) }

    private static func clean(_ s: String) -> String { s.replacingOccurrences(of: ".", with: "") }
}

// MARK: - Bouwstenen

/// Kaart met radius 22 en dunne rand.
struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.cardBorder, lineWidth: 1))
    }
}

/// Klein label in hoofdletters met letterspatiëring.
struct SectionLabel: View {
    let text: String
    var color: Color = Theme.secondary

    init(_ text: String, color: Color = Theme.secondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy))
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

/// Type-label met gekleurd blokje, bv. "■ FARTLEK".
struct TypeTag: View {
    let type: WorkoutType
    var extra = false

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(type.color).frame(width: 10, height: 10)
            Text(extra ? "EXTRA · \(type.label)" : type.label)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(type.color)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Groot cijfer met label erboven.
struct StatBlock: View {
    let label: String
    let value: String
    var size: CGFloat = 19

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(1)
                .foregroundStyle(Theme.secondary)
            Text(value)
                .font(.system(size: size, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 56

    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration, height: height)
    }
}

private struct PrimaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let height: CGFloat
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(size: height >= 52 ? 17 : 15, weight: .heavy))
            .foregroundStyle(Theme.background)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Theme.text.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
            .opacity(isEnabled ? 1 : 0.35)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 46

    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonBody(configuration: configuration, height: height)
    }
}

private struct SecondaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let height: CGFloat
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Theme.sunken.opacity(configuration.isPressed ? 0.6 : 1), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.outline, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.35)
    }
}

/// Keuzechip: gekozen = wit met zwarte tekst.
struct Chip: View {
    let title: String
    let selected: Bool
    var height: CGFloat = 48
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(selected ? Theme.background : Theme.text)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(selected ? Theme.text : Theme.sunken, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? Theme.text : Theme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Rond vinkje: gevuld wit als gekozen.
struct CheckCircle: View {
    let on: Bool

    var body: some View {
        ZStack {
            Circle().fill(on ? Theme.text : Color.clear)
            Circle().strokeBorder(on ? Theme.text : Theme.outline, lineWidth: 2)
            if on {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Theme.background)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

/// Grote keuzekaart met icoon, titel en uitleg.
struct ChoiceCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
                    .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .heavy))
                    Text(subtitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
                CheckCircle(on: selected)
            }
            .foregroundStyle(Theme.text)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(selected ? Theme.text : Theme.cardBorder, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Twee of drie opties naast elkaar in een pil.
struct Segmented<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    var height: CGFloat = 44

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let on = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.system(size: 14, weight: on ? .heavy : .bold))
                        .foregroundStyle(on ? Theme.background : Theme.text)
                        .frame(maxWidth: .infinity, minHeight: height)
                        .background(on ? Theme.text : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.sunken, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.cardBorder, lineWidth: 1))
    }
}

/// Schakelaar: aan = wit spoor met zwart bolletje, uit = grijs.
struct LoopToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? Theme.text : Theme.track)
                        .frame(width: 51, height: 31)
                    Circle()
                        .fill(configuration.isOn ? Theme.background : Theme.secondary)
                        .frame(width: 25, height: 25)
                        .padding(3)
                }
                .animation(.easeOut(duration: 0.15), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "aan" : "uit")
    }
}

/// Grote stepper met − en + (onboarding).
struct BigStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String
    var step = 1

    var body: some View {
        HStack {
            roundButton("minus", label: "Minder") { value = max(range.lowerBound, value - step) }
            Spacer()
            VStack(spacing: 2) {
                Text("\(value)")
                    .font(.system(size: 64, weight: .black))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer()
            roundButton("plus", label: "Meer") { value = min(range.upperBound, value + step) }
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
        .animation(.snappy, value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unit)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }

    private func roundButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.text)
                .frame(width: 56, height: 56)
                .background(Theme.sunken, in: Circle())
                .overlay(Circle().strokeBorder(Theme.outline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Ring rond het weeknummer bovenaan Vandaag.
struct ProgressRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0.02, min(fraction, 1)))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}

/// Dun voortgangsbalkje.
struct Bar: View {
    let fraction: Double
    var color: Color = Theme.accent
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(color).frame(width: geo.size.width * max(0, min(fraction, 1)))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Standaard achtergrond en titel bovenaan, gecentreerd zoals in de tekeningen.
    func screenTitle(_ title: String) -> some View {
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title).font(.system(size: 16, weight: .heavy)).foregroundStyle(Theme.text)
                }
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .background(Theme.background.ignoresSafeArea())
    }
}

extension Binding where Value == Bool {
    /// True zolang de optionele waarde gezet is. Op false zetten maakt ze nil.
    init<T>(present value: Binding<T?>) {
        self.init(get: { value.wrappedValue != nil },
                  set: { if !$0 { value.wrappedValue = nil } })
    }
}
