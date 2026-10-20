import SwiftUI
import UniformTypeIdentifiers
import LoopCore

/// Keuzes voor de stem en de cues. De cues zelf gebruiken we vanaf de volgende stap (lopen).
enum CueSettings {
    static let voiceRate = "voiceRate"          // 0 trager, 1 normaal, 2 sneller
    static let blocks = "cueBlocks"
    static let countdown = "cueCountdown"
    static let pace = "cuePace"
    static let splits = "cueSplits"
    static let remaining = "cueRemaining"
    static let duck = "duckMusic"

    static func rateFactor(_ setting: Int) -> Float {
        switch setting {
        case 0: return 0.9
        case 2: return 1.1
        default: return 1
        }
    }

    private static func bool(_ key: String, _ fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }

    /// Welke cues de engine uitspreekt, zoals ingesteld in Instellingen.
    static var engineSettings: EngineSettings {
        EngineSettings(blockCues: bool(blocks, true), countdown: bool(countdown, true),
                       paceFeedback: bool(pace, true), splits: bool(splits, true),
                       remaining: bool(remaining, false))
    }

    static var duckMusic: Bool { bool(duck, true) }

    static var currentRateFactor: Float {
        rateFactor(UserDefaults.standard.object(forKey: voiceRate) as? Int ?? 1)
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    @AppStorage(CueSettings.voiceRate) private var voiceRate = 1
    @AppStorage(CueSettings.blocks) private var cueBlocks = true
    @AppStorage(CueSettings.countdown) private var cueCountdown = true
    @AppStorage(CueSettings.pace) private var cuePace = true
    @AppStorage(CueSettings.splits) private var cueSplits = true
    @AppStorage(CueSettings.remaining) private var cueRemaining = false
    @AppStorage(CueSettings.duck) private var duckMusic = true

    @State private var speaker: Speaker?
    @State private var exportDocument: BackupDocument?
    @State private var showImporter = false
    @State private var pendingRestore: Data?
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    voiceCard
                    cuesCard
                    backupCard
                    diagnoseCard
                    Text("Runner \(appVersion) · alles lokaal, geen account")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.tertiary)
                        .padding(.top, 4)
                }
                .foregroundStyle(Theme.text)
                .padding(.horizontal, Theme.margin)
                .padding(.vertical, 8)
            }
            .screenTitle("Instellingen")
            .fileExporter(isPresented: Binding(present: $exportDocument), document: exportDocument,
                          contentType: .json, defaultFilename: backupName) { result in
                switch result {
                case .success: notice = "Backup bewaard."
                case .failure(let error): notice = "Backup bewaren mislukt: \(error.localizedDescription)"
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    do {
                        pendingRestore = try Data(contentsOf: url)
                    } catch {
                        notice = "Het bestand kon niet gelezen worden."
                    }
                case .failure(let error):
                    notice = "Openen mislukt: \(error.localizedDescription)"
                }
            }
            .confirmationDialog("Backup terugzetten?", isPresented: Binding(present: $pendingRestore),
                                titleVisibility: .visible) {
                Button("Terugzetten", role: .destructive) { restore() }
                Button("Annuleren", role: .cancel) {}
            } message: {
                Text("Alles wat nu in de app staat, wordt vervangen door de inhoud van de backup.")
            }
            .alert("Backup", isPresented: Binding(present: $notice)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(notice ?? "")
            }
        }
    }

    // MARK: - Stem

    private var voiceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Stem", color: Theme.muted).padding(.bottom, 10)
                HStack {
                    Text("Stem").font(.system(size: 15, weight: .bold))
                    Spacer()
                    Text(Speaker.describe(Speaker.bestVoice()))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.trailing)
                }
                .frame(minHeight: 48)
                .overlay(alignment: .top) { divider }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Spreektempo").font(.system(size: 15, weight: .bold))
                    Segmented(options: [(0, "Trager"), (1, "Normaal"), (2, "Sneller")], selection: $voiceRate, height: 32)
                }
                .padding(.vertical, 12)
                .overlay(alignment: .top) { divider }

                Button {
                    let s = speaker ?? Speaker()
                    speaker = s
                    s.rateFactor = CueSettings.rateFactor(voiceRate)
                    s.speak("Interval 3 van 6. Snel lopen, 1 minuut.")
                } label: {
                    Label("Stem testen", systemImage: "speaker.wave.2")
                }
                .buttonStyle(SecondaryButtonStyle(height: 48))
                .padding(.top, 8)

                Text("Een betere stem download je in iOS via Instellingen › Toegankelijkheid › Gesproken materiaal › Stemmen › Nederlands. De app kiest automatisch de beste.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
    }

    // MARK: - Cues

    private var cuesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Wat de stem zegt", color: Theme.muted).padding(.bottom, 10)
                toggleRow("Begin en einde van elk blok", nil, $cueBlocks)
                toggleRow("Aftellen", "Nog 100 meter, nog 10 seconden", $cueCountdown)
                toggleRow("Tempo te snel of te traag", "Hooguit één keer per halve minuut", $cuePace)
                toggleRow("Tijd per kilometer", nil, $cueSplits)
                toggleRow("Intervallen nog te gaan", nil, $cueRemaining)
                toggleRow("Muziek stiller tijdens cues", "Spotify en Apple Music", $duckMusic)
            }
        }
    }

    private func toggleRow(_ title: String, _ subtitle: String?, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .bold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                }
            }
        }
        .toggleStyle(LoopToggleStyle())
        .frame(minHeight: 54)
        .overlay(alignment: .top) { divider }
    }

    // MARK: - Backup

    private var backupCard: some View {
        let last = model.lastBackup
        let late = model.backupReminder

        return Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Backup", color: Theme.muted)
                HStack(spacing: 12) {
                    Circle().fill(late ? Theme.accent : (last == nil ? Theme.outline : Theme.good))
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(backupTitle(last)).font(.system(size: 15, weight: .heavy))
                        if let last {
                            Text(Backup.fileName(for: last))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text("Alles staat enkel op deze iPhone. Bewaar af en toe een backup in Bestanden, bijvoorbeeld in iCloud Drive.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Backup maken") { makeBackup() }
                    .buttonStyle(PrimaryButtonStyle(height: 52))
                Button("Backup terugzetten") { showImporter = true }
                    .buttonStyle(SecondaryButtonStyle(height: 48))
            }
        }
    }

    private func backupTitle(_ last: Date?) -> String {
        guard let last else { return "Nog geen backup gemaakt" }
        let days = PlanCalendar.default.dateComponents([.day], from: PlanCalendar.default.startOfDay(for: last),
                                                       to: PlanCalendar.default.startOfDay(for: Date())).day ?? 0
        switch days {
        case ..<1: return "Laatste backup vandaag"
        case 1: return "Laatste backup gisteren"
        default: return "Laatste backup \(days) dagen geleden"
        }
    }

    private var backupName: String {
        Backup.fileName(for: Date()).replacingOccurrences(of: ".json", with: "")
    }

    private func makeBackup() {
        do {
            exportDocument = BackupDocument(data: try model.makeBackup())
        } catch {
            notice = "Backup maken mislukt: \(error.localizedDescription)"
        }
    }

    private func restore() {
        guard let data = pendingRestore else { return }
        pendingRestore = nil
        do {
            try model.restore(data)
            notice = "Backup teruggezet."
        } catch RunStore.StoreError.backupTooNew {
            notice = "Deze backup komt uit een nieuwere versie van de app en kan niet teruggezet worden."
        } catch {
            notice = "Terugzetten mislukt. Is dit wel een LoopApp-backup?"
        }
    }

    // MARK: - Diagnose

    private var diagnoseCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Diagnose", color: Theme.muted)
                NavigationLink {
                    DebugRunScreen()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("GPS en stem testen").font(.system(size: 15, weight: .bold))
                            Text("Intervaltest of vrij lopen met diagnose")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(Theme.text)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Hulp

    private var divider: some View {
        Rectangle().fill(Theme.cardBorder).frame(height: 1)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}

/// Backupbestand voor de Bestanden-app.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
