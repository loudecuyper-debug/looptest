import SwiftUI
import LoopCore

/// "Extra loop deze week": rustige bonusloop op een vrije dag, telt niet mee voor de opbouw.
struct ExtraRunSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let week: PlanWeek
    let today: PlanDay
    @State private var picked: Weekday?

    private var freeDays: [Weekday] {
        ExtraRun.freeDays(in: week).filter { PlanDay(week: today.week, day: $0) >= today }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Extra loop deze week")
                    .font(.system(size: 26, weight: .heavy))
                Text("Een rustige loop van \(Fmt.decimal(ExtraRun.suggestedKm(in: week))) km. Telt niet mee voor de opbouw van je plan.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if freeDays.isEmpty {
                Text("Er is deze week geen vrije dag meer.")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(freeDays, id: \.self) { d in
                        let on = picked == d
                        Button {
                            picked = d
                        } label: {
                            HStack {
                                Text(DateText.longCapitalized(week.date(for: d)))
                                    .font(.system(size: 17, weight: .bold))
                                Spacer()
                                CheckCircle(on: on)
                            }
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 50)
                            .background(on ? Theme.card : Theme.sunken, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(on ? Theme.text : Theme.cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }

            if let picked, let warning = ExtraRun.warning(for: picked, in: week) {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button("Toevoegen") {
                if let picked {
                    model.addExtraRun(on: PlanDay(week: today.week, day: picked))
                }
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(picked == nil)
        }
        .foregroundStyle(Theme.text)
        .padding(Theme.margin)
        .padding(.top, 12)
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.background)
    }
}

/// "Niet 100%": een paar lichtere dagen. De week telt niet mee voor de opbouw.
struct NotFeelingSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var reason: NotFeelingReason?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Niet 100%")
                    .font(.system(size: 26, weight: .heavy))
                Text("Het plan wordt tijdelijk lichter. Deze week telt niet mee voor de opbouw.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                ForEach(NotFeelingReason.allCases, id: \.self) { r in
                    ChoiceCard(icon: icon(r), title: r.name, subtitle: explanation(r), selected: reason == r) {
                        reason = r
                    }
                }
            }

            Spacer(minLength: 0)

            Button("Toepassen") {
                if let reason { model.notFeeling(reason) }
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(reason == nil)
        }
        .foregroundStyle(Theme.text)
        .padding(Theme.margin)
        .padding(.top, 12)
        .presentationDetents([.large])
        .presentationBackground(Theme.background)
    }

    private func icon(_ r: NotFeelingReason) -> String {
        switch r {
        case .sick: return "thermometer.medium"
        case .pain: return "bandage"
        case .noTime: return "clock"
        case .tired: return "battery.25"
        }
    }

    private func explanation(_ r: NotFeelingReason) -> String {
        switch r {
        case .sick: return "Trainingen pauzeren tot je hersteld bent"
        case .pain: return "Drie dagen enkel korte rustige loopjes"
        case .noTime: return "Rustige loopjes vervallen, lange loop korter"
        case .tired: return "Vandaag rustig, kwaliteit schuift op"
        }
    }
}
