# LoopApp: projectbrief

Gratis, persoonlijke Runna-achtige loopcoach voor Louis' iPhone. Native Swift-app, gesideload via SideStore. Volledig lokaal, geen account, geen server.

## Doel van Louis
- Verder lopen (langere afstanden) en sneller worden
- **Concreet nu: snelheid opbouwen voor de 10 km.** Huidig niveau: 5 km in ongeveer 25:00 (VDOT ~38,3, voorspelde 10 km ~51:53)
- Enkel iPhone, geen Apple Watch, dus geen hartslag: bijsturen op pace + hoe zwaar een loop aanvoelde (RPE 1-10)
- Puur lokaal op de iPhone, geen sync
- Audio cues in het Nederlands zijn de belangrijkste live-feature (intervallen, over muziek heen)

## Werkwijze (fases)
1. ~~Analyse van Runna~~ (klaar)
2. ~~Features kiezen~~ (klaar, zie hieronder)
3. **Proof of concept** (gebouwd, build werkt, installatie geblokkeerd, zie Status)
4. ~~Technische opbouw: plan-brein, datamodel, schermen~~ (klaar 15 okt, zie Fase 4)
5. **UI** ← **volgende stap**
6. Volledige app bouwen

Afspraken: eerst brainstormen tot het plan klopt, proof of concepts voor risicovolle onderdelen, opties voorleggen en goedkeuring vragen voor grote herschrijvingen. Communicatie in casual Nederlands. Geen em-dashes in teksten.

## Platformbeslissing
- **Native Swift (SwiftUI)**, geen PWA: een PWA kan op iOS geen GPS volgen met vergrendeld scherm en audio cues over muziek zijn onbetrouwbaar.
- Geen Expo/React Native: achtergrondlocatie vereist sowieso een eigen build, dan liever meteen Swift.
- Louis heeft **Windows** (geen Mac). Builden gebeurt via **GitHub Actions** (macOS-runner): XcodeGen genereert het project uit `project.yml`, `xcodebuild` maakt een unsigned `.ipa`, die als GitHub Release gepubliceerd wordt.
- Installeren via **SideStore** met gratis Apple ID (ondertekent zelf, ververst elke 7 dagen via LocalDevVPN). Max 3 apps met gratis Apple ID, SideStore telt mee.
- Louis pusht zelf via **GitHub Desktop** (public repo `LoopTest`, voor gratis macOS-builds).

## Features versie 1
**Plan maken (in de app zelf, via een vragenreeks bij eerste gebruik):** doel (verder / sneller / beide), optionele racedatum, startniveau (recente tijd of testloop), huidig weekvolume, langste recente loop, loopdagen per week, dag voor lange loop. Fases opbouw → zwaarder → piek → taper, 6 tot 24 weken. Pace-zones uit niveau (VDOT).

**Workouttypes:** easy, long run, tempo, intervallen, fartlek, progressieloop, herstelloop, testloop. Altijd opwarming + cooling down.

**Tijdens het lopen:** GPS met scherm uit, Nederlandse audio cues met muziek-ducking (start/einde blok, "nog 100 meter", pace-feedback te snel/te traag, km-splits, intervallen te gaan), live stats op vergrendelscherm, pauzeren/blok overslaan/vroeger stoppen, vrij lopen zonder plan.

**Na het lopen:** afstand, tijd, pace per km, routekaart, doelpace vs. echt per interval, RPE 1-10 + pijntje ja/nee, lokaal opslaan, optioneel naar Apple Health.

**Extra loop deze week:** plan blijft op de vaste dagen gebouwd, maar per week kan je een rustige bonusloop (3 à 5 km) toevoegen op een vrije dag. Waarschuwing als die vlak voor een kwaliteitssessie of lange loop valt. Telt niet mee voor de opbouw. Na 3 weken op rij met een extra loop stelt de app voor om een vaste dag toe te voegen.

**Plan aanpassen:** pace-zones schuiven als kwaliteitssessies structureel te snel/traag gaan, waarschuwing bij te snelle easy runs, gemiste sessies slim herschikken, "Niet 100%"-knop (ziek/pijntje/geen tijd, enkele lichtere dagen, dan terug in plan), opbouw remt af bij stelselmatig hoge RPE.

**Overzicht:** weekkalender, weekvolume-grafiek, PR's, voorspelde racetijden.

**Overgenomen van Runna (15 okt):** workouts zelf verslepen in de kalender (binnen de week, met waarschuwing bij twee zware dagen naast elkaar), weekkilometers op Vandaag ("9,5 van 17,6 km"), manueel een loop toevoegen (gsm vergeten, loopband).

**Backup:** knop "Backup maken" zet alles als één JSON-bestand in de Bestanden-app, "Backup terugzetten" zet het terug. Herinnering na 21 dagen zonder backup. Belangrijk omdat alles lokaal staat en een gesideloade app soms opnieuw geïnstalleerd moet worden.

**Native extra's in v1:** kadans via bewegingssensor (ook treadmill zonder GPS), lokale meldingen ("morgen: 6×400 m"), widget met workout van vandaag.

**Later:** schoenen bijhouden (km per paar, melding rond 600 à 800 km), hitte-aanpassing (weer-API), krachttraining, meerdere plannen na elkaar + herstelblok na race, import uit Apple Health, Siri/actieknop.

**Niet:** sociale features, racedatabase, smartwatch, AI-briefings.

## Proof of concept (LoopTest)
Mini-app die test: (1) GitHub → .ipa → SideStore werkt, (2) GPS loopt door met scherm uit, (3) NL cues klinken goed over muziek.
- Intervaltest 3 × (1 min snel / 1 min wandelen) en vrij lopen met cue per km
- 10 s aftellen om scherm te vergrendelen, resultaat met routekaart, stats per blok, diagnosescherm (GPS-punten met scherm uit, grootste GPS-gat, tijd op achtergrond) en logboek

Bestanden:
| Bestand | Inhoud |
|---|---|
| `LoopTest/Workout.swift` | Pure logica: `WorkoutPlan`, `Segment`, `CueEngine` (cue-timing, vangt vertraagde ticks op), `Format` (NL-teksten, pace) |
| `LoopTest/RunSession.swift` | CoreLocation (achtergrond, `CLBackgroundActivitySession`), klok, afstand met ruisfilter (>12 m/s genegeerd, accuracy ≤30 m), rollend tempo over 30 s, diagnose |
| `LoopTest/Speaker.swift` | `AVSpeechSynthesizer`, beste NL-stem (nl-BE voorkeur), audiosessie `.playback/.voicePrompt` met `.duckOthers` |
| `LoopTest/ContentView.swift`, `ResultView.swift`, `LoopTestApp.swift` | SwiftUI-schermen |
| `LoopTest/Info.plist` | Locatie-teksten, `UIBackgroundModes`: location + audio |
| `project.yml` | XcodeGen, iOS 17, bundle `com.loudecuyper.looptest`, signing uit |
| `.github/workflows/build.yml` | Build op `macos-15`, unsigned ipa, upload + GitHub Release. Slaat pushes over die enkel `LoopCore/` of `.md` wijzigen |

## Fase 4: plan-brein (LoopCore)
Beslissingen:
- **Apart Swift-pakket `LoopCore/`** met enkel pure logica (Foundation). De app gebruikt het later via XcodeGen (`packages:`).
- **Automatische tests** in GitHub Actions (`.github/workflows/core.yml`, `swift test` op `macos-15`), plus een **plan-preview** (`swift run plan-preview`) die als Markdown in de Summary van de run verschijnt. Zo is de logica na te lezen zonder iPhone.
- **Opslag:** gewone `Codable`-structs als JSON, geen SwiftData (testbaar, ruim genoeg voor één gebruiker).
- **Pace-zones via VDOT (Daniels/Gilbert-formules)**, fracties van VDOT: herstel 55-62%, rustig 62-70%, duurtempo = voorspeld marathontempo ±5 s, tempo 86-89%, interval 96-100%, snelheid 106-110%. Gecontroleerd tegen de Daniels-tabellen.
- Startniveau: recente prestatie (≥1500 m) of Cooper-test (12 min).
- Plan maken gebeurt in de app zelf (vragenreeks). Het testprofiel in de preview (5 km 25:00, 15 km/week, langste loop 8 km, di/do/zo) dient enkel om de logica te controleren.

Regels plangenerator v1:
- Fases: 40% opbouw, 35% zwaarder, rest piek, laatste week taper. Weken starten op maandag.
- Volume +8% per week, piek max 1,6× startvolume (of +15 km), elke 4e week rustweek (-25%).
- Lange loop +1 km per week, max 42% van het weekvolume, max 14 km voor 10 km-doel (12 / 20 / 30 km voor 5 km / halve / marathon).
- Kwaliteit: 1 sessie per week. Met 4+ loopdagen een tweede (tempo) enkel in zwaarder en piek.
- Opbouw: fartlek en korte tempo's. Zwaarder: 800 m-intervallen en tempo-km's. Piek: 3× 2 km en 2× 3 km op 10k-tempo, 1 km-intervallen, één lange loop met 2 km duurtempo. Taper: 3× 1 km op 10k-tempo + tijdrit over de doelafstand.
- Zwaar deel begrensd: intervallen max 20%, tempo max 25% van het weekvolume.
- Elke kwaliteitssessie: 1,5 km inlopen, 1 km uitlopen. Rustige loopjes vullen de rest van het volume (min 3 km).
- Kwaliteitsdagen zo ver mogelijk van de lange loop en van elkaar.

Stappen:
1. ~~Pace-zones + racevoorspelling + testopzet~~ (klaar, tests groen op 15 okt)
2. ~~Plangenerator~~ + 3. ~~Workout-bibliotheek~~ (eerste versie, afgestemd op 10 km sneller; regels eerst in een Python-prototype uitgetest en goedgekeurd, daarna naar Swift)
4. ~~Adaptatieregels~~ (regels eerst in Python gesimuleerd op 4 scenario's, goedgekeurd, daarna naar Swift: `Coach`)
5. ~~Opslag van gelopen loopjes en schermstructuur~~ (klaar, zie hieronder)

Adaptatieregels v1 (`Coach.swift`):
- Zones: 2 kwaliteitssessies op rij 3+ s/km sneller én RPE ≤ 7 → voorstel niveau +0,5. 2 op rij 5+ s/km trager of vroeger gestopt → voorstel -0,5. Max 1 voorstel per 2 weken, nooit in de taperweek. **Enkel het gelopen tempo beslist over de zones**, RPE niet.
- Voorstel wordt gevraagd met één tik ("Je loopt sneller dan gepland. Tempo's aanpassen? (interval 4:50 → 4:47)") en pas na "ja" toegepast.
- Tijdrit: niveau meteen op het resultaat.
- Rustige loop 10+ s/km sneller dan de zone → tip. 3 van de laatste 5 → waarschuwing, max om de 2 weken.
- RPE: week gemiddeld 1,5+ boven verwacht (rustig 3,5 · lang 5 · progressie 6 · tempo/fartlek 7 · interval 8 · tijdrit 9) → volgende week groeit niet. Twee weken op rij → rustweek komt vroeger, de geplande rustweek wordt een gewone week op hetzelfde niveau.
- Pijn → volgende loop rustig en max 30 min. Twee keer binnen 7 dagen → "Niet 100%" voorstellen.
- Gemist: rustige loop valt weg. Kwaliteit en lange loop schuiven naar een vrije dag later die week, niet naast een zware dag, anders weg. Lange loop weg → volgende lange loop groeit niet. 2+ sessies van een week gemist → die week telt niet mee voor de opbouw (de week erna neemt hetzelfde niveau over, niet nog eens bevroren).
- "Niet 100%" (week telt niet mee): ziek = alles op pauze tot "beter", dan 3 dagen rustig. Pijntje = 3 dagen korte rustige loopjes. Geen tijd = rustige loopjes vallen weg, lange loop -25%. Moe = vandaag rustig, kwaliteit schuift naar een latere vrije dag als dat kan.
- Het plan wordt altijd opnieuw berekend uit invoer + `AdaptationState` (aanpassingen per week, niveauwijzigingen, ziekteperiodes). Eerdere weken kunnen daardoor achteraf licht wijzigen; gelopen loopjes moeten dus apart bewaard worden (stap 5).
- Opgemerkt: bij het testprofiel bepaalt de 42%-grens de lange loop, dus "lange loop groeit niet" heeft daar weinig effect.

Bestanden LoopCore:
| Bestand | Inhoud |
|---|---|
| `LoopCore/Package.swift` | Pakket: library `LoopCore`, executable `plan-preview`, tests |
| `Sources/LoopCore/Vdot.swift` | VDOT uit prestatie/Cooper-test, voorspelde tijden en tempo's |
| `Sources/LoopCore/PaceZones.swift` | `PaceZone`, `PaceRange` (afwijking te snel/traag), `PaceZones` (+ `adjusted(byVdot:)`) |
| `Sources/LoopCore/TimeText.swift` | Tijd, tempo, afstand als tekst |
| `Sources/LoopCore/PlanModels.swift` | Datamodel: `Weekday`, `PlanInput`, `Phase`, `WorkoutType`, `WorkoutStep`/`WorkoutBlock`, `PlannedWorkout`, `PlanWeek`, `TrainingPlan`, `PlanCalendar` |
| `Sources/LoopCore/WorkoutLibrary.swift` | `QualitySession`-sjablonen, `SimpleRuns` (rustig, lang, progressie, tijdrit) |
| `Sources/LoopCore/PlanGenerator.swift` | De plangenerator met bovenstaande regels |
| `Sources/LoopCore/ExtraRun.swift` | Extra loop toevoegen/verwijderen, waarschuwing, voorstel vaste dag |
| `Sources/LoopCore/WorkoutText.swift` | NL-omschrijving van workouts |
| `Sources/LoopCore/AdaptationModels.swift` | `PlanDay`, `WeekAdjustment`, `DayOverride`, `LevelChange`, `SickPeriod`, `RunResult`, `NotFeelingReason`, `LevelSuggestion`, `CoachEvent` (met NL-teksten), `AdaptationState` |
| `Sources/LoopCore/Coach.swift` | De coach: `record`, `accept`, `finishWeek`, `notFeeling`, `recovered`, extra loop |
| `Sources/PlanPreview/main.swift` | Preview: zones, volledig 12-weken-plan, voorbeeld extra loop, vergelijking 4 dagen, coach-scenario's A-E |
| `Tests/LoopCoreTests/*.swift` | Tests tegen Daniels-tabellen en het Python-prototype, structuur plan, extra loop, coach-scenario's, Niet 100%, Codable |

## Schermstructuur (goedgekeurd 15 okt)
Vijf tabbladen, zoals Runna:
1. **Vandaag**: workout van vandaag (inhoud, tempo's, geschatte duur, startknop), weekkilometers, meldingen van de coach (tempo's aanpassen ja/nee, tips), knoppen *Extra loop* en *Niet 100%*, vrij lopen starten. Rustdag: wat komt er morgen.
2. **Plan**: tempozones, voorspelde racetijden, niveau en voortgang naar het doel, plan beheren (plan opnieuw maken, loopdagen, dag lange loop).
3. **Kalender**: alle weken met fase en km, status per workout (gelopen/gemist), workouts verslepen, tik voor details.
4. **Voortgang**: alle loopjes (ook vrije en manuele, met + om manueel toe te voegen), weekvolume-grafiek, PR's (1 km, 5 km, 10 km, langste loop), niveau-verloop.
5. **Instellingen**: stem testen, welke cues, backup maken/terugzetten, Apple Health.

Over alles heen:
- **Lopen** (volledig scherm): huidig blok, resterend, tempo vs. doel in kleur, afstand, pauze/blok overslaan/stop.
- **Na de loop**: samenvatting, kaart, splits, per blok doel vs. echt, RPE + pijntje, daarna de reactie van de coach.
- **Eerste keer**: vragenreeks (doel, recente tijd of testloop, weekvolume, langste loop, loopdagen, dag lange loop, weken of racedatum) en preview van het plan.

## Opslag (`RunStore.swift`, `RunRecord.swift`, `Stats.swift`)
- Map Documenten/LoopApp: `coach.json` (invoer + aanpassingen), `runs/<id>.json` per loop, `runs-index.json` (samenvattingen, nieuwste eerst), `meta.json` (laatste backup).
- `CompletedRun`: datum, bron (gps/loopband/manueel), plek in plan, **workout zoals toen gepland**, status, afstand, tijd, km-splits, per blok doel vs. echt, route (3 lijsten lat/lon/tijd), RPE, pijntje, kadans, notitie. `coachResult` zet hem om voor de coach.
- `Backup`: versie 1, JSON met coach + alle loopjes. Nieuwere versie wordt geweigerd.
- `Stats`: weekkilometers gepland vs. gelopen (op datum, dus ook vrije loopjes), PR's uit opeenvolgende volle km-splits (manuele loopjes enkel voor langste loop).
- `Coach.moveWorkout`: verslepen binnen de week, resultaat `moved(warning:)`, `dayTaken`, `nothingToMove`, `alreadyDone`.

## Status (15 oktober 2026)
- ✅ GitHub Actions-build slaagt, `LoopTest.ipa` staat in Releases
- ✅ SideStore geïnstalleerd op iPhone via iloader (na anisette-server wissel en keyring uitgeschakeld in iloader-settings)
- ❌ **Inloggen in SideStore faalt met fout -80045** ("This action cannot be completed at this time"). Wereldwijd probleem sinds 12 oktober 2026, treft ook iloader, AltServer en Sideloadly (zie GitHub nab138/iloader issues #859, #865, #883).
- 🔄 Mogelijke oplossing (15 okt): nieuwe iloader-release met tijdelijke fix (werkt met 2FA via vertrouwd toestel, niet via SMS), en een workaround in SideStore via Instellingen › User Customizations › Anisette Client Configuration › Client Info (exacte tekst uit issue #859). SideStore nightly zou het 2FA-probleem al opgelost hebben, stabiele versie volgt. Louis probeert de workaround eenmalig.
- Afspraak: niet blijven proberen (risico op tijdelijke blokkade). Langer dan 1 à 2 weken stuk: plan B bespreken (betaald Apple Developer-account €99/jaar).
- Nog niet getest: GPS met scherm uit, kwaliteit van de cues.

- ✅ LoopCore (plan-brein, coach, opslag) volledig getest in GitHub Actions.

## Volgende stap
Run met de opslag controleren (groen). Dan fase 5: UI. Eerst stijl en look afspreken (kleuren, lettertype, hoe Vandaag en het loopscherm eruitzien), daarna de schermen bouwen. LoopCore moet dan ook in de app gekoppeld worden via XcodeGen (`packages:` in `project.yml`).
