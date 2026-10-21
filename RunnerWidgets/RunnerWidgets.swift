import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

// Widget-extensie van Runner. Bevat voorlopig enkel de Live Activity tijdens het lopen;
// later komt hier ook de widget "training van vandaag" bij.
//
// Ontwerp 20 okt (canvas "Runner loopscherm", rij Live Activity), goedgekeurd door Louis:
// - elk getal maar één keer, bloklabel in de kleur van het blok;
// - workout: groot wat er nog rest, tempo in de kleur van op tempo / te snel / te traag met doelzone,
//   voortgangsbalk, Pauze en Blok overslaan;
// - vrij lopen: tijd, afstand en tempo even groot naast elkaar;
// - pauze: oranje rand, Hervat en Stop; afgerond: samenvatting die 15 minuten blijft staan.
// Maximaal 160 punten hoog (grens van iOS op het vergrendelscherm).

@main
struct RunnerWidgetBundle: WidgetBundle {
    var body: some Widget {
        RunLiveActivity()
    }
}

private enum W {
    static let background = Color(hex: 0x0B0D10)
    static let card = Color(hex: 0x22272F)
    static let sunken = Color(hex: 0x15181D)
    static let outline = Color(hex: 0x4A5262)
    static let track = Color(hex: 0x3A4250)
    static let text = Color(hex: 0xF3F5F8)
    static let secondary = Color(hex: 0x98A2B3)
    static let accent = Color(hex: 0xFF7A1A)
    static let good = Color(hex: 0x4CC38A)
    static let warn = Color(hex: 0xF2B32A)

    /// Kleur van het tempo: 1 op tempo, 2 te snel, 3 te traag.
    static func pace(_ status: Int) -> Color {
        switch status {
        case 1: return good
        case 2: return accent
        case 3: return warn
        default: return text
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

private extension RunActivityAttributes.ContentState {
    var color: Color { Color(hex: blockColor) }
    /// Een workout die nu loopt (niet vrij, niet gepauzeerd, niet klaar, niet aan het aftellen).
    var isWorkoutRunning: Bool { !isFreeRun && !paused && !finished && !isCountdown }
}

struct RunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            LockScreenRunView(state: context.state)
                .activityBackgroundTint(W.background)
                .activitySystemActionForegroundColor(W.text)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        TitleText(state: s, size: 11)
                        BigValue(state: s, size: 30)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("TEMPO")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1)
                            .foregroundStyle(W.secondary)
                        Text(s.paceValue ?? "-:--")
                            .font(.system(size: 24, weight: .heavy))
                            .monospacedDigit()
                            .foregroundStyle(W.pace(s.paceStatus))
                        if let target = s.targetText {
                            Text(target)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(W.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        if s.isWorkoutRunning { BlockBar(state: s) }
                        HStack {
                            Text("\(s.distanceText) · \(s.elapsedText)")
                            Spacer()
                            if let next = s.nextTitle, !s.finished { Text(next).lineLimit(1) }
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(W.secondary)
                        .monospacedDigit()
                        if !s.finished && !s.isCountdown { Controls(state: s) }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                HStack(spacing: 5) {
                    Circle().fill(s.paused ? W.accent : s.color).frame(width: 8, height: 8)
                    CompactValue(state: s)
                        .frame(maxWidth: 64, alignment: .leading)
                }
            } compactTrailing: {
                Text(s.paused ? "pauze" : (s.paceValue ?? "-:--"))
                    .font(.system(size: 14, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(s.paused ? W.accent : W.pace(s.paceStatus))
            } minimal: {
                MinimalRing(state: s)
            }
            .keylineTint(s.color)
        }
    }
}

// MARK: - Vergrendelscherm

struct LockScreenRunView: View {
    let state: RunActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TitleText(state: state, size: 12)
                Spacer(minLength: 4)
                if let info = rightText {
                    Text(info)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(W.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            if state.isWorkoutRunning || state.isCountdown {
                HStack(alignment: .bottom) {
                    BigValue(state: state, size: 40)
                    Spacer(minLength: 8)
                    if state.isCountdown {
                        Text("Vergrendel gerust je scherm")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(W.secondary)
                    } else {
                        VStack(alignment: .trailing, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(state.paceValue ?? "-:--")
                                    .font(.system(size: 26, weight: .heavy))
                                    .monospacedDigit()
                                    .foregroundStyle(W.pace(state.paceStatus))
                                Text("/km")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(W.secondary)
                            }
                            if let target = state.targetText {
                                Text(target)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(W.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                    }
                }
                if state.isWorkoutRunning { BlockBar(state: state) }
            } else {
                ThreeStats(state: state)
            }

            if state.finished {
                HStack {
                    Text("Open Runner om af te sluiten")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(W.secondary)
                }
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(W.card, in: Capsule())
            } else if !state.isCountdown {
                Controls(state: state)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .foregroundStyle(W.text)
        .overlay {
            if state.paused && !state.finished {
                ContainerRelativeShape().stroke(W.accent, lineWidth: 3)
            }
        }
    }

    private var rightText: String? {
        if state.finished || state.paused || state.isFreeRun { return state.infoText }
        return state.nextTitle?.lowercased()
    }
}

/// Bloklabel met stip, pauze-icoon of vinkje.
struct TitleText: View {
    let state: RunActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            if state.finished {
                Image(systemName: "checkmark").font(.system(size: size, weight: .black)).foregroundStyle(W.good)
            } else if state.paused {
                Image(systemName: "pause.fill").font(.system(size: size - 1, weight: .bold)).foregroundStyle(W.accent)
            } else {
                Circle().fill(state.color).frame(width: 8, height: 8)
            }
            Text(title)
                .font(.system(size: size, weight: .heavy))
                .tracking(1)
                .foregroundStyle(state.finished ? W.good : (state.paused ? W.accent : state.color))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var title: String {
        if state.finished { return "LOOP AFGEROND" }
        if state.paused { return "GEPAUZEERD" }
        return state.blockTitle
    }
}

/// Het grote getal: wat er nog rest van het blok (telt zelf af bij tijdsblokken),
/// bij vrij lopen de totale tijd.
struct BigValue: View {
    let state: RunActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        Group {
            if state.finished || state.paused {
                Text(state.blockRemainingText ?? state.elapsedText)
            } else if let end = state.blockEnd {
                Text(end, style: .timer)
            } else if let left = state.blockRemainingText, !state.isFreeRun {
                Text(left)
            } else {
                Text(state.runStart, style: .timer)
            }
        }
        .font(.system(size: size, weight: .black))
        .monospacedDigit()
        .foregroundStyle(W.text)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// Klein getal links in het Dynamic Island.
struct CompactValue: View {
    let state: RunActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.paused || state.finished {
                Text(state.blockRemainingText ?? state.elapsedText)
            } else if let end = state.blockEnd {
                Text(end, style: .timer)
            } else if let left = state.blockRemainingText, !state.isFreeRun {
                Text(left)
            } else {
                Text(state.runStart, style: .timer)
            }
        }
        .font(.system(size: 14, weight: .heavy))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// Voortgang van het blok: loopt zelf bij tijdsblokken, anders ververst om de paar seconden.
struct BlockBar: View {
    let state: RunActivityAttributes.ContentState

    var body: some View {
        Group {
            if let start = state.blockStart, let end = state.blockEnd, start < end {
                ProgressView(timerInterval: start...end, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            } else {
                ProgressView(value: min(max(state.progress ?? 0, 0), 1))
            }
        }
        .progressViewStyle(.linear)
        .tint(state.color)
    }
}

/// Minimaal (als een andere app het eiland deelt): ringetje met de voortgang van het blok.
struct MinimalRing: View {
    let state: RunActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.paused {
                Image(systemName: "pause.fill").foregroundStyle(W.accent)
            } else if let start = state.blockStart, let end = state.blockEnd, start < end {
                ProgressView(timerInterval: start...end, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
                .tint(state.color)
            } else if let p = state.progress, !state.isFreeRun {
                ProgressView(value: min(max(p, 0), 1))
                    .progressViewStyle(.circular)
                    .tint(state.color)
            } else {
                Image(systemName: "figure.run").foregroundStyle(W.accent)
            }
        }
    }
}

/// Drie cijfers naast elkaar: vrij lopen, pauze en de samenvatting op het einde.
struct ThreeStats: View {
    let state: RunActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if state.finished {
                stat("AFSTAND") { Text(state.distanceText) }
                stat("TIJD") { Text(state.elapsedText) }
                stat(state.summaryLabel) { Text(state.summaryValue ?? "–") }
            } else {
                stat("TIJD") {
                    if state.paused {
                        Text(state.elapsedText)
                    } else {
                        Text(state.runStart, style: .timer)
                    }
                }
                stat("AFSTAND") { Text(state.distanceText) }
                if state.paused {
                    stat(state.summaryLabel) { Text(state.summaryValue ?? "–") }
                } else {
                    stat("TEMPO") { Text(state.paceValue ?? "-:--") }
                }
            }
        }
        .opacity(state.paused ? 0.8 : 1)
    }

    private func stat<V: View>(_ label: String, @ViewBuilder value: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .tracking(1)
                .foregroundStyle(W.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            value()
                .font(.system(size: 24, weight: .black))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Knoppen: tijdens het lopen Pauze en Blok overslaan, tijdens een pauze Hervat en Stop.
/// Stop staat enkel bij een pauze, zodat je niet per ongeluk stopt in je zak.
struct Controls: View {
    let state: RunActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            if state.paused {
                Button(intent: ResumeRunIntent()) {
                    pill("Hervat", icon: "play.fill", primary: true)
                }
                .buttonStyle(.plain)
                .layoutPriority(1)
                Button(intent: StopRunIntent()) {
                    pill("Stop", icon: "stop.fill", primary: false)
                }
                .buttonStyle(.plain)
            } else {
                Button(intent: PauseRunIntent()) {
                    pill("Pauze", icon: "pause.fill", primary: true)
                }
                .buttonStyle(.plain)
                if state.canSkip {
                    Button(intent: SkipBlockIntent()) {
                        pill("Blok overslaan", icon: "forward.end.fill", primary: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func pill(_ title: String, icon: String, primary: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 14, weight: .heavy))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(primary ? W.background : W.text)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(primary ? W.text : W.card, in: Capsule())
            .overlay(Capsule().strokeBorder(primary ? Color.clear : W.outline, lineWidth: 1))
    }
}
