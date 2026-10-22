import SwiftUI
import UIKit
import LoopCore

@main
struct LoopAppMain: App {
    @StateObject private var model = AppModel()

    init() {
        // Tabbalk zoals stijl D: donker, actief wit, rest grijs.
        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = UIColor(Theme.sunken)
        tabs.shadowColor = .clear
        let normal = tabs.stackedLayoutAppearance.normal
        normal.iconColor = UIColor(Theme.tertiary)
        normal.titleTextAttributes = [.foregroundColor: UIColor(Theme.tertiary)]
        let selected = tabs.stackedLayoutAppearance.selected
        selected.iconColor = UIColor(Theme.text)
        selected.titleTextAttributes = [.foregroundColor: UIColor(Theme.text)]
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(Theme.text)
        }
    }
}

enum AppTab: Hashable {
    case today, plan, calendar, progress, settings
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .today

    var body: some View {
        Group {
            if model.coach == nil {
                OnboardingView(onCancel: nil) { input in
                    model.createPlan(input)
                }
            } else {
                TabView(selection: $tab) {
                    TodayView(openTab: { tab = $0 })
                        .tabItem { Label("Vandaag", systemImage: "sun.max") }
                        .tag(AppTab.today)
                    PlanView()
                        .tabItem { Label("Plan", systemImage: "scope") }
                        .tag(AppTab.plan)
                    CalendarView()
                        .tabItem { Label("Kalender", systemImage: "calendar") }
                        .tag(AppTab.calendar)
                    VoortgangView()
                        .tabItem { Label("Voortgang", systemImage: "chart.bar") }
                        .tag(AppTab.progress)
                    SettingsView()
                        .tabItem { Label("Instellingen", systemImage: "slider.horizontal.3") }
                        .tag(AppTab.settings)
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.catchUp()
                model.rescheduleReminders()   // venster van 14 dagen schuift mee
            }
        }
        .task(id: model.coach != nil) {
            // Toestemming voor meldingen vragen zodra er een plan is (iOS vraagt het maar één keer).
            guard model.coach != nil, ReminderSettings.anyOn else { return }
            await Reminders.requestIfNeeded()
            model.rescheduleReminders()
        }
        .alert("Er liep iets mis", isPresented: Binding(present: $model.errorText)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorText ?? "")
        }
    }
}
