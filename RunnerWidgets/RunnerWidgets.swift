import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

// Widget-extensie van Runner. Bevat voorlopig enkel de Live Activity tijdens het lopen;
// later komt hier ook de widget "training van vandaag" bij.

@main
struct RunnerWidgetBundle: WidgetBundle {
    var body: some Widget {
        RunLiveActivity()
    }
}

private enum W {
    static let panel = Color(red: 0x1C / 255, green: 0x20 / 255, blue: 0x27 / 255)
    static let sunken = Color(red: 0x15 / 255, green: 0x18 / 255, blue: 0x1D / 255)
    static let text = Color(red: 0xF3 / 255, green: 0xF5 / 255, blue: 0xF8 / 255)
    static let secondary = Color(red: 0x98 / 255, green: 0xA2 / 255, blue: 0xB3 / 255)
    static let accent = Color(red: 0xFF / 255, green: 0x7A / 255, blue: 0x1A / 255)
}

struct RunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            LockScreenRunView(name: context.attributes.workoutName, state: context.state)
                .activityBackgroundTint(W.panel)
                .activitySystemActionForegroundColor(W.text)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.blockTitle)
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(W.accent)
                            .lineLimit(1)
                        BlockClock(state: s, size: 26)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(s.distanceText)
                            .font(.system(size: 15, weight: .heavy))
                            .monospacedDigit()
                        Text(s.paceText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(W.secondary)
                            .monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Controls(state: s)
                }
            } compactLeading: {
                Image(systemName: s.paused ? "pause.fill" : "figure.run")
                    .foregroundStyle(W.accent)
            } compactTrailing: {
                BlockClock(state: s, size: 14)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: s.paused ? "pause.fill" : "figure.run")
                    .foregroundStyle(W.accent)
            }
        }
    }
}

/// Resterende tijd van het blok; telt zelf af. Zonder einde (vrij lopen) toont hij de totale tijd.
struct BlockClock: View {
    let state: RunActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        Group {
            if state.finished {
                Text(state.elapsedText)
            } else if state.paused {
                Text(state.blockRemainingText ?? state.elapsedText)
            } else if let end = state.blockEnd {
                Text(end, style: .timer)
            } else {
                Text(state.runStart, style: .timer)
            }
        }
        .font(.system(size: size, weight: .heavy))
        .monospacedDigit()
        .foregroundStyle(W.text)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

struct LockScreenRunView: View {
    let name: String
    let state: RunActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "figure.run")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(W.accent)
                Text("RUNNER · \(name.uppercased())")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(W.secondary)
                Spacer()
                if state.paused && !state.finished {
                    Text("GEPAUZEERD")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(W.accent)
                }
            }

            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.finished ? "KLAAR" : state.blockTitle)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(W.text)
                        .lineLimit(1)
                    if let next = state.nextTitle, !state.finished {
                        Text(next)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(W.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                BlockClock(state: state, size: 34)
                    .frame(maxWidth: 130, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
            }

            HStack(spacing: 0) {
                stat("TIJD") {
                    if state.paused || state.finished {
                        Text(state.elapsedText)
                    } else {
                        Text(state.runStart, style: .timer)
                    }
                }
                stat("AFSTAND") { Text(state.distanceText) }
                stat("TEMPO") { Text(state.paceText) }
            }

            if !state.finished {
                Controls(state: state)
            }
        }
        .padding(16)
        .foregroundStyle(W.text)
    }

    private func stat<V: View>(_ label: String, @ViewBuilder value: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(W.secondary)
            value()
                .font(.system(size: 16, weight: .heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Knoppen: tijdens het lopen Pauze en Overslaan, tijdens een pauze Hervat en Stop.
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
                        pill("Overslaan", icon: "forward.end.fill", primary: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func pill(_ title: String, icon: String, primary: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 14, weight: .heavy))
            .foregroundStyle(primary ? W.sunken : W.text)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(primary ? W.text : W.sunken, in: Capsule())
    }
}
