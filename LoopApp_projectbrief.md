# LoopApp: projectbrief

Gratis, persoonlijke Runna-achtige loopcoach voor Louis' iPhone. Native Swift-app, gesideload met een gratis Apple ID (via iloader, SideStore staat ook op de iPhone). Volledig lokaal, geen account, geen server. Naam op de iPhone: **Runner** (sinds 18 okt); intern blijft alles LoopApp heten.

## Doel van Louis
- Verder lopen (langere afstanden) en sneller worden
- **Concreet nu: snelheid opbouwen voor de 10 km.** Huidig niveau: 5 km in ongeveer 25:00 (VDOT ~38,3, voorspelde 10 km ~51:53)
- Enkel iPhone, geen Apple Watch, dus geen hartslag: bijsturen op pace + hoe zwaar een loop aanvoelde (RPE 1-10)
- Puur lokaal op de iPhone, geen sync
- Audio cues in het Nederlands zijn de belangrijkste live-feature (intervallen, over muziek heen)

## Werkwijze (fases)
1. ~~Analyse van Runna~~ (klaar)
2. ~~Features kiezen~~ (klaar, zie hieronder)
3. ~~Proof of concept~~ (geslaagd 18 okt, Diagnose verwijderd in 0.7)
4. ~~Technische opbouw: plan-brein, datamodel, schermen~~ (klaar 15 okt, zie Fase 4)
5. **UI** ← **bezig**: tekeningen goedgekeurd (15 okt). SwiftUI stap 1 (schil en plan) klaar op 15 okt, draait op de iPhone sinds 18 okt. Stap 2 (lopen) bezig: `WorkoutEngine` in LoopCore klaar, de rest wacht op de PoC-test.
6. Volledige app bouwen

Afspraken: eerst brainstormen tot het plan klopt, proof of concepts voor risicovolle onderdelen, opties voorleggen en goedkeuring vragen voor grote herschrijvingen. Communicatie in casual Nederlands. Geen em-dashes in teksten.

## Platformbeslissing
- **Native Swift (SwiftUI)**, geen PWA: een PWA kan op iOS geen GPS volgen met vergrendeld scherm en audio cues over muziek zijn onbetrouwbaar.
- Geen Expo/React Native: achtergrondlocatie vereist sowieso een eigen build, dan liever meteen Swift.
- Louis heeft **Windows** (geen Mac). Builden gebeurt via **GitHub Actions** (macOS-runner): XcodeGen genereert het project uit `project.yml`, `xcodebuild` maakt een unsigned `.ipa`, die als GitHub Release gepubliceerd wordt. Lokaal (in Claude's werkruimte) is er geen Swift: enkel een syntaxcontrole, de echte compilatie gebeurt in Actions.
- Installeren met een **gratis Apple ID** via **iloader** op de pc: Import IPA, elke 7 dagen opnieuw met kabel. Zo werkt het sinds 18 okt (zie Status voor de exacte werkwijze). SideStore staat ook op de iPhone maar wordt nu niet gebruikt. Max 3 apps met gratis Apple ID, SideStore telt mee.
- **Geen betaald Apple Developer-account (beslist 16 okt):** de app moet gratis blijven, dat is het hele punt (niet betalen voor Runna).
- Louis pusht zelf via **GitHub Desktop** (public repo `LoopTest`, voor gratis macOS-builds).
- **LoopTest omgebouwd tot LoopApp (15 okt, keuze van Louis)**: één app. Map `LoopApp/`, target en product `LoopApp`, bundle `com.loudecuyper.loopapp`, `LoopApp.ipa` in Releases. De repo blijft `LoopTest` heten (de oude submap `LoopTest/` is verwijderd). De PoC-schermen zitten als Diagnose in Instellingen.

## Naam en icoon (18 okt)
- **Naam: Runner** (keuze van Louis). Enkel de naam onder het icoon (`CFBundleDisplayName`) en zichtbare teksten zijn aangepast. Bundle-ID `com.loudecuyper.loopapp`, target, map en `LoopApp.ipa` blijven ongewijzigd: een andere bundle-ID zou een nieuwe app zijn (gegevens kwijt, extra plek van de 3 gratis apps).
- **Icoon: een loper waarin een R verborgen zit.** Voorover hellende romp, geplooide voorste arm, lang voorste been; achterste arm en been lopen uit in een punt. Alle ledematen lopen taps toe (dik bij de romp, dun naar hand en voet) zodat links en rechts in evenwicht zijn. Oranje hoofd (#FF8536) los boven de schouder. Witte figuur (#EEF1F5) op leisteen (verloop #3B434F → #252B34), bewust zachter dan het bijna-zwart van de app.
- Getoetst aan: Apple HIG (één brandpunt, eenvoudig, herkenbaar), werkt op 29 px en in grijs, max twee kleuren, geen tekst of snelheidsstreepjes, visueel gewicht in balans (rechtsonder weegt zwaarst, dus daar lichter).
- Bestanden: `LoopApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (1024×1024, vierkant, iOS rondt zelf af) en de bron `Design/runner-icon.svg`. In `project.yml`: `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`, versie 0.3 (build 3).
- Niet gedaan: geen nagemaakt stocklogo (Shutterstock-voorbeeld enkel als sfeer). Donkere en getinte icoonvarianten van iOS zijn optioneel, kan later.

## Features versie 1
**Plan maken (in de app zelf, via een vragenreeks bij eerste gebruik):** doel (verder / sneller / beide), optionele racedatum, startniveau (recente tijd of testloop), huidig weekvolume, langste recente loop, loopdagen per week, dag voor lange loop. Fases opbouw → zwaarder → piek → taper, 6 tot 24 weken. Pace-zones uit niveau (VDOT).

**Workouttypes:** easy, long run, tempo, intervallen, fartlek, progressieloop, herstelloop, testloop. Altijd opwarming + cooling down.

**Tijdens het lopen:** GPS met scherm uit, Nederlandse audio cues met muziek-ducking (start/einde blok, "nog 100 meter", pace-feedback te snel/te traag, km-splits, intervallen te gaan), live stats op vergrendelscherm, pauzeren/blok overslaan/vroeger stoppen, vrij lopen zonder plan.

**Na het lopen:** afstand, tijd, pace per km, routekaart, doelpace vs. echt per interval, RPE 1-10 + pijn ja/nee, lokaal opslaan, optioneel naar Apple Health.

**Extra loop deze week:** plan blijft op de vaste dagen gebouwd, maar per week kan je een rustige bonusloop (3 à 5 km) toevoegen op een vrije dag. Waarschuwing als die vlak voor een kwaliteitssessie of lange loop valt. Telt niet mee voor de opbouw. Na 3 weken op rij met een extra loop stelt de app voor om een vaste dag toe te voegen.

**Plan aanpassen:** pace-zones schuiven als kwaliteitssessies structureel te snel/traag gaan, waarschuwing bij te snelle easy runs, gemiste sessies slim herschikken, "Niet 100%"-knop (ziek/pijn/geen tijd, enkele lichtere dagen, dan terug in plan), opbouw remt af bij stelselmatig hoge RPE.

**Overzicht:** weekkalender, weekvolume-grafiek, PR's, voorspelde racetijden.

**Overgenomen van Runna (15 okt):** workouts zelf verslepen in de kalender (binnen de week, met waarschuwing bij twee zware dagen naast elkaar), weekkilometers op Vandaag ("9,5 van 17,6 km"), manueel een loop toevoegen (gsm vergeten, loopband).

**Backup:** knop "Backup maken" zet alles als één JSON-bestand in de Bestanden-app, "Backup terugzetten" zet het terug. Herinnering na 21 dagen zonder backup. Belangrijk omdat alles lokaal staat en een gesideloade app soms opnieuw geïnstalleerd moet worden.

**Native extra's in v1:** kadans via bewegingssensor (ook treadmill zonder GPS), lokale meldingen ("morgen: 6×400 m"), widget met workout van vandaag.

**Toegevoegd 18 okt (wens van Louis):**
- **Live Activity** op het vergrendelscherm en in het Dynamic Island tijdens het lopen: huidig blok ("SNEL · 2 VAN 3") met resterende tijd (telt zelf af), volgend blok, totale tijd, afstand, tempo. Knoppen: Pauze en Blok overslaan tijdens het lopen, Hervat en Stop tijdens een pauze (Stop enkel bij pauze, tegen per ongeluk stoppen in de zak). Starten kan niet vanaf een Live Activity; later eventueel via bedieningspaneel of actieknop.
- **Routekaart** in Voortgang: alle gelopen GPS-routes als dunne oranje lijnen op een donkere kaart (vaak gelopen straten kleuren feller door overlap), filter alles / dit jaar / deze maand, tik op een route om de loop te openen. Gebruikt de bewaarde `RouteTrack`, niets nieuws op te slaan.
- **Routes plannen** (op vraag van Louis meteen mee gebouwd, 18 okt): punten aantikken, elk stuk volgt straten en paden via Apple Kaarten (wandelroute), afstand en geschatte duur op rustig tempo live, Terug, Naar start, Wissen, bewaren met naam.

**Later:** schoenen bijhouden (km per paar, melding rond 600 à 800 km), hitte-aanpassing (weer-API), krachttraining, meerdere plannen na elkaar + herstelblok na race, import uit Apple Health, Siri/actieknop.

**Niet:** sociale features, racedatabase, smartwatch, AI-briefings.

## Proof of concept (nu Diagnose in LoopApp)
Test: (1) GitHub → .ipa → iPhone werkt (✅ 18 okt), (2) GPS loopt door met scherm uit, (3) NL cues klinken goed over muziek.
- Intervaltest 3 × (1 min snel / 1 min wandelen) en vrij lopen met cue per km
- 10 s aftellen om scherm te vergrendelen, resultaat met routekaart, stats per blok, diagnosescherm (GPS-punten met scherm uit, grootste GPS-gat, tijd op achtergrond) en logboek

Bestanden (`LoopApp/Debug/`):
| Bestand | Inhoud |
|---|---|
| `PoCWorkout.swift` | `WorkoutPlan`, `Segment`, `CueEngine` (cue-timing, vangt vertraagde ticks op), `Format` (NL-teksten, pace) |
| `RunSession.swift` | CoreLocation (achtergrond, `CLBackgroundActivitySession`), klok, afstand met ruisfilter (>12 m/s genegeerd, accuracy ≤30 m), rollend tempo over 30 s, diagnose |
| `Speaker.swift` | `AVSpeechSynthesizer`, beste NL-stem (nl-BE voorkeur), audiosessie `.playback/.voicePrompt` met `.duckOthers`, `rateFactor` voor spreektempo |
| `DebugViews.swift` | Start, live en resultaat van de test (`DebugRunScreen`) |

## Fase 4: plan-brein (LoopCore)
Beslissingen:
- **Apart Swift-pakket `LoopCore/`** met enkel pure logica (Foundation). De app gebruikt het via XcodeGen (`packages:` in `project.yml`, sinds 15 okt gekoppeld).
- **Automatische tests** in GitHub Actions (`.github/workflows/core.yml`, `swift test` op `macos-15`), plus een **plan-preview** (`swift run plan-preview`) die als Markdown in de Summary van de run verschijnt. Zo is de logica na te lezen zonder iPhone.
- **Opslag:** gewone `Codable`-structs als JSON, geen SwiftData (testbaar, ruim genoeg voor één gebruiker).
- **Pace-zones via VDOT (Daniels/Gilbert-formules)**, fracties van VDOT: herstel 55-62%, rustig 62-70%, duurtempo = voorspeld marathontempo ±5 s, tempo 86-89%, interval 96-100%, snelheid 106-110%. Gecontroleerd tegen de Daniels-tabellen.
- Startniveau: recente prestatie (≥1500 m) of Cooper-test (12 min).
- Plan maken gebeurt in de app zelf (vragenreeks). Het testprofiel in de preview (5 km 25:00, 15 km/week, langste loop 8 km, di/do/zo) dient enkel om de logica te controleren.

Regels plangenerator v1:
- Fases: 40% opbouw, 35% zwaarder, rest piek, laatste week taper. Weken starten op maandag.
- **Start in de huidige week (beslist 20 okt):** week 1 begint op de maandag van de week waarin het plan gemaakt wordt; loopdagen vóór die dag vallen weg (niet als gemist). Is er die week geen loopdag meer over, dan start het plan de maandag erna. Voorheen schoof het plan altijd naar de volgende maandag, waardoor een plan gemaakt op dinsdag pas zes dagen later begon. `PlanCalendar.planStart`, `firstPlanDay`, `monday(of:)`, `weekday(of:)`; tests in `PlanGeneratorTests`. Bestaande plannen schuiven mee, want het plan wordt altijd herberekend uit `PlanInput.startDate`.
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
- "Niet 100%" (week telt niet mee): ziek = alles op pauze tot "beter", dan 3 dagen rustig. Pijn = 3 dagen korte rustige loopjes. Geen tijd = rustige loopjes vallen weg, lange loop -25%. Moe = vandaag rustig, kwaliteit schuift naar een latere vrije dag als dat kan.
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
| `Sources/LoopCore/AdaptationModels.swift` | `PlanDay`, `WeekAdjustment`, `DayOverride`, `LevelChange`, `SickPeriod`, `RunResult`, `NotFeelingReason`, `LevelSuggestion`, `CoachEvent` (met NL-teksten, zakelijk sinds 15 okt), `AdaptationState` |
| `Sources/LoopCore/Coach.swift` | De coach: `record`, `accept`, `finishWeek`, `notFeeling`, `recovered`, extra loop, `moveWorkout` |
| `Sources/LoopCore/CueText.swift` | Uitgesproken tijden, tempo's en afstanden ("4 minuten 50", "anderhalve kilometer") |
| `Sources/LoopCore/WorkoutEngine.swift` | Engine voor het lopen: `EngineSettings`, `Cue`, `EngineStep`, `WorkoutEngine` (start, update, skipStep, stop, completedRun) |
| `Sources/LoopCore/LivePace.swift` | Tempo "nu" op het loopscherm: Doppler-snelheid, 10 s vasthouden, dan pasteller; mediaan van 5 + glijdend gemiddelde (22 okt) |
| `Sources/LoopCore/EngineSimulator.swift` | Gesimuleerde loper voor tests en cue-preview |
| `Sources/CuePreview/main.swift` | Cue-preview: wat de stem zegt bij 7 gesimuleerde loopjes, als Markdown in de Summary |
| `Sources/PlanPreview/main.swift` | Preview: zones, volledig 12-weken-plan, voorbeeld extra loop, vergelijking 4 dagen, coach-scenario's A-E |
| `Tests/LoopCoreTests/*.swift` | Tests tegen Daniels-tabellen en het Python-prototype, structuur plan, extra loop, coach-scenario's, Niet 100%, Codable. `WorkoutEngineTests`: blokken, cues, aftellen, tempofeedback, splits, overslaan, stoppen, vertraagde metingen, instellingen |

## Schermstructuur (goedgekeurd 15 okt)
Vijf tabbladen, zoals Runna:
1. **Vandaag**: workout van vandaag (inhoud, tempo's, geschatte duur, startknop), weekkilometers, meldingen van de coach (tempo's aanpassen ja/nee, tips), knoppen *Extra loop* en *Niet 100%*, vrij lopen starten. Rustdag: wat komt er morgen.
2. **Plan**: tempozones, voorspelde racetijden, niveau en voortgang naar het doel, plan beheren (plan opnieuw maken, loopdagen, dag lange loop).
3. **Kalender**: alle weken met fase en km, status per workout (gelopen/gemist), workouts verslepen, tik voor details.
4. **Voortgang**: alle loopjes (ook vrije en manuele, met + om manueel toe te voegen), weekvolume-grafiek, PR's (1 km, 5 km, 10 km, langste loop), niveau-verloop.
5. **Instellingen**: stem testen, welke cues, backup maken/terugzetten, Apple Health.

Over alles heen:
- **Lopen** (volledig scherm): huidig blok, resterend, tempo vs. doel in kleur, afstand, pauze/blok overslaan/stop.
- **Na de loop**: samenvatting, kaart, splits, per blok doel vs. echt, RPE + pijn, daarna de reactie van de coach.
- **Eerste keer**: vragenreeks (doel, recente tijd of testloop, weekvolume, langste loop, loopdagen, dag lange loop, weken of racedatum) en preview van het plan.

## Stijl (fase 5, gekozen 15 okt: richting D, tekeningen goedgekeurd)
Ontwerp-canvas "LoopApp stijlrichtingen" (claude.ai artifact). Enkel richting D staat er nog op, in drie rijen: tabbladen + Lopen, onboarding, Na de loop + Instellingen. In de geest van Runna maar zonder hun merkelementen (geen logo, badges, illustraties of mintgroen).
- **Kleuren**: achtergrond #0B0D10, paneel bovenaan #1C2027, kaarten #22272F met rand #2E3440, tabbalk #15181D. Tekst #F3F5F8, secundair #98A2B3. Accent oranje #FF7A1A (spaarzaam: weekring, voortgangsbalkjes, meldingsstip).
- **Primaire knop**: wit (#F3F5F8) met zwarte tekst, brede pil, zwevend boven de tabbalk.
- **Kleur per type**: rustig #4CC38A, lang #5B8CFF, tempo #F2B32A, interval #FF6B3D, fartlek #E05BA0, progressie/duurtempo #9B7BFF, tijdrit #F0524F.
- **Letter**: SF Pro (systeem). Zware titels, kleine HOOFDLETTER-labels met letterspatiëring boven cijfers, grote vette cijfers (tabular).
- **Layout**: 16 px marge, kaarten met radius 22, Vandaag met weekstrook (huidige dag witte cirkel, stipje in typekleur), titel gecentreerd bovenaan, tabbalk met iconen (actief wit, rest grijs).
- **Keuzes en schakelaars**: gekozen = witte rand of witte vulling met zwarte tekst (kaarten, chips, segmenten). Schakelaar aan = wit spoor met zwart bolletje, uit = grijs. Geen accentkleur voor selecties.
- **Toon van teksten**: zakelijk en professioneel, zoals een trainer. Geen verkleinwoorden of kinderlijke zinnen ("pijn" of "klachten", niet "pijntje"; geen "Goed gedaan" of "netjes"). Feitelijk: cijfers en wat er verandert. Ook de `CoachEvent`-teksten en `NotFeelingReason` in LoopCore volgen dit (15 okt).

Ontwerp onboarding (vragenreeks):
- Eén vraag per scherm, bovenaan "VRAAG x VAN 7" + oranje voortgangsbalk, terugknop, witte "Verder" onderaan.
- 1 Doel (3 keuzekaarten + chips doelafstand 5 km / 10 km / halve / marathon), 2 Niveau (segment Recente tijd / Testloop; afstand-chips, tijd in min en s, berekend niveau + voorspelde 10 km live eronder), 3 Weekvolume (grote stepper − / +), 4 Langste loop (zelfde stepper), 5 Loopdagen (7 rijen aan/uit, tip past zich aan het aantal aan), 6 Dag lange loop (enkel de gekozen dagen), 7 Duur (aantal weken of racedatum).
- Afsluiter "Je plan staat klaar": doel, weken en data, fasebalk, start → piek per week en lange loop, voorspelde 10 km, eerste week, knoppen "Plan starten" en "Antwoorden aanpassen".

Ontwerp na de loop (twee stappen):
- Eerst "Hoe zwaar voelde het?": korte stats bovenaan ("Loop afgerond"), RPE als raster 1-10 met label en uitleg per niveau, "Verwacht voor een fartlek: 7", "Pijn of klachten?" Nee/Ja, optionele notitie, "Opslaan".
- Daarna de samenvatting: coach-kaart bovenaan (binnen je doeltempo / voorstel tempo's met Ja, aanpassen / Nee / pijn gemeld met aangepaste volgende loop), routekaart, 6 stats (afstand, tijd, gem. tempo, kadans, zwaarte, pijn), snelle blokken als staafjes links (sneller) of rechts (trager) van het doel, groen binnen de zone en geel erbuiten, in- en uitlopen en herstel, tempo per km, "Klaar".

Ontwerp Instellingen: Stem (keuze stem, spreektempo, Stem testen), Wat de stem zegt (schakelaars per soort cue + muziek stiller), Backup (status met groene of oranje stip, Backup maken, Backup terugzetten), Apple Health en herinnering voor je training.

## Fase 5: SwiftUI-app
Bouwvolgorde (gekozen 15 okt): **stap 1 schil en plan** (thema, 5 tabbladen, onboarding, Vandaag, Plan, Kalender, Voortgang, Instellingen), **stap 2 lopen** (GPS en cues voor LoopCore-workouts, Na de loop), daarna meldingen, widget, Apple Health, kadans.

Stap 1 (klaar 15 okt, app-build en LoopCore-tests groen in Actions, draait op de iPhone sinds 18 okt):
- `AppModel` (@MainActor) houdt `Coach`, het berekende plan, `RunSummary`'s en PR's bij en bewaart via `RunStore`. Alle coach-acties gaan via één `mutateCoach` (bewaren + plan herberekenen).
- Vandaag: weekstrook (tik op een dag toont die dag), workoutkaart → details, rustdag met volgende workout, coach-meldingen (tempovoorstel met Ja/Nee), weekoverzicht, Extra loop en Niet 100% als sheets, kaart "Ik ben hersteld" bij ziek, backup-herinnering. Ook schermen voor "plan start maandag" en "plan afgerond".
- "Start workout" toont voorlopig dat lopen in stap 2 komt.
- Plan: doel, tijdritdatum, fasestrook, weken en totale afstand, tempozones met uitleg, voorspelde tijden, niveau-aanpassingen. "Plan beheren" = nieuw plan maken (bevestiging; gelopen loopjes blijven).
- Kalender: alle weken, status per workout, scrollt naar de huidige week. Verplaatsen via lang drukken › "Verplaatsen naar" (en een knop in de details) in plaats van slepen, met de waarschuwing van `Coach.moveWorkout`.
- Voortgang: grafiek gepland vs. gelopen per week (Swift Charts), PR's, alle loopjes (lang drukken om te verwijderen), + voor een manuele loop (datum, afstand, tijd, zwaarte, pijn, notitie, optioneel koppelen aan de geplande workout van die dag, die dan naar de coach gaat).
- Instellingen: beste NL-stem, spreektempo, Stem testen, cue-schakelaars (bewaard in `@AppStorage`, gebruikt vanaf stap 2), backup maken/terugzetten via de Bestanden-app, Diagnose (PoC).
- Afwijkingen van de tekeningen: testloop in de onboarding vraagt de afstand na 12 minuten (de app kan nog niet lopen); Apple Health en meldingen nog niet in Instellingen.
- Nog niet: gemiste sessies automatisch melden aan de coach en `finishWeek` bij een nieuwe week (komt met stap 2, anders telt alles als gemist zolang lopen niet kan); coach-meldingen worden nog niet bewaard tussen app-starts.

UI-ronde 18 okt (na eerste test op de iPhone, tekening goedgekeurd door Louis):
- **Vandaag** heeft altijd dezelfde opbouw, ook voor de start: weekstrook (voor de start week 1, zonder "vandaag"), melding "Je plan start morgen / over x dagen", workoutkaart met klein label (VANDAAG, MORGEN, EERSTE TRAINING), weekoverzicht ("Trainingen" en "Afstand"), Extra loop en Niet 100% enkel tijdens het plan, vaste witte knop onderaan: "Start <workout>" op een trainingsdag, anders "Vrij lopen" (beide tonen nog de uitleg dat lopen in stap 2 komt). Het aparte scherm "Je plan start…" is weg.
- **Kalender**: schakelaar Lijst / Maand bovenaan (keuze onthouden). Maand = rooster met tegels per dag zoals een echte kalender: vandaag omrand, trainingsdagen lichter met een streepje in de typekleur (vinkje als gelopen, vaag als gemist), gekozen dag wit. Eronder de workoutkaart van de gekozen dag (standaard de eerstvolgende), legende van de types, geplande km van de maand rechtsboven, ‹ › binnen de maanden van het plan, lang drukken om te verplaatsen. Bestand `Calendar/MonthCalendar.swift` (met `FlowRow`-layout).
- **Letters een trap kleiner** in alle schermen (niet in Debug), vaste tabel: 84→64, 44→34, 36→30, 32/30→24, 28→21, 26/24→20, 22→19, 20/19→17, 18→16, 17→15, 16→15, 15→14, 14→13, 13→12, 12→11. Grote cijfers op Plan 30→24, primaire knop 19→17.
- Instellingen: "Spreektempo" staat boven de keuze (brak midden in het woord). Stemnaam zonder dubbel "verbeterd".
- Stem: Louis verkiest **Xander (Enhanced, nl-NL)** boven Ellen; de app kiest hem automatisch zolang Ellen Enhanced niet geïnstalleerd is.
- Controle: Swift-syntax met tree-sitter in Claude's werkruimte (geen Swift-compiler), echte build in Actions.

Live Activity-proef (18 okt, in Diagnose, nog te testen op de iPhone):
- Nieuwe extensie `RunnerWidgets` (app-extension, bundle `com.loudecuyper.loopapp.widgets`, ingebed in de app, zelfde instellingen zonder ondertekening). Krijgt later ook de widget "training van vandaag".
- Gedeeld bestand `LoopApp/LiveActivity/RunActivity.swift` (in beide targets): `RunActivityAttributes` met `ContentState` (bloklabel, volgend blok, `blockEnd` zodat de klok zelf aftelt, `runStart` gecorrigeerd voor pauzes, afstand, tempo, gepauzeerd, klaar, `canSkip`) en de knoppen als `LiveActivityIntent` (Pauze, Hervat, Overslaan, Stop). Die lopen in het proces van de app en komen binnen via `RunControlCenter.handler`; geen App Group nodig.
- `RunSession` (Diagnose) kreeg pauze, hervatten en blok overslaan (afstand telt niet tijdens pauze), start de Live Activity bij de start (moet op de voorgrond), werkt hem bij bij elk nieuw blok en anders hooguit om de 5 s, en laat de samenvatting nog 15 min staan. Ook in de app zelf knoppen Pauze/Hervat en Overslaan.
- `Info.plist`: `NSSupportsLiveActivities`. Versie 0.4 (build 4). Build-log toont welke extensies in de app zitten.
- Te testen: installeren met iloader (de extensie krijgt een eigen app-ID; met een gratis Apple ID max 10 nieuwe app-ID's per 7 dagen), verschijnt de Live Activity, telt de klok, werken de knoppen met scherm vergrendeld.

Routekaart en routes plannen (18 okt, nog te testen op de iPhone):
- Ingang: kaart "Routekaart" in Voortgang. Scherm `Map/RoutesMapView.swift` met schakelaar **Gelopen / Plannen**, donkere gedempte kaart zonder winkels, knoppen voor je locatie, kompas en schaal.
- Gelopen: alle loopjes met GPS-route als oranje lijnen (uitgedund tot ±8 m tussen punten), filter Alles / Dit jaar / Deze maand, tik op of vlak naast een route (±24 punten op het scherm) om ze wit te markeren met afstand, tijd en tempo. Vult zich pas met de loopjes die het echte loopscherm (stap 2) bewaart; Diagnose bewaart geen loopjes.
- Plannen: `RoutePlanner` vraagt per stuk een wandelroute aan `MKDirections`; zonder netwerk wordt dat stuk een rechte lijn met een melding. Bewaarde routes als chips onderaan (tik = tonen, lang drukken = verwijderen); bewerken van een bewaarde route begint van het laatste punt, opnieuw bewaren overschrijft dezelfde route.
- LoopCore: `PlannedRoute` en `RouteGeometry` (afstand met haversine, lengte, uitdunnen, afstand van een punt tot een lijn) in `PlannedRoute.swift`; `RunStore` bewaart routes in `planned-routes.json`; de backup bevat ze in het optionele veld `plannedRoutes` (oudere backups zonder dat veld laten de huidige routes staan, versie blijft 1). Tests in `PlannedRouteTests` (waarden nagerekend in Python).

Stap 2 gebouwd (18 okt, voor de eerste plantraining op dinsdag 20 okt):
- Diagnose-test thuis geslaagd (18 okt): GPS liep door met scherm uit, Live Activity startte, knoppen werkten. Daarmee is de proef afgerond.
- `Run/RunTracker.swift`: GPS (zelfde filter als de proef), klok zonder pauzes, stem met instellingen uit Instellingen (cues, spreektempo, muziek stiller of niet), `WorkoutEngine` uit LoopCore, route als `RouteTrack`, kadans via `CMPedometer` (gemiddelde = passen / looptijd), Live Activity (afstandsblokken tonen de resterende meters als tekst, tijdsblokken tellen zelf af), knoppen op het vergrendelscherm. Na afloop een `CompletedRun`.
- `Run/RunScreen.swift`: aftellen (10 s, annuleren mogelijk, niets bewaard), loopscherm (bloklabel in typekleur, groot resterend deel, voortgangsbalk, volgend blok, tempo in kleur met doel, afstand en totale tijd of kadans bij vrij lopen, Pauze/Hervat, Blok overslaan, Stop met bevestiging "Wat je al liep wordt bewaard"), daarna Na de loop: zwaarte 1-10 met uitleg en verwachte zwaarte per type, pijn ja/nee, notitie, Opslaan; dan samenvatting met de meldingen van de coach, routekaart, 6 cijfers, snelle blokken tegenover doel en tempo per km.
- Starten: witte knop op Vandaag ("Start <workout>" op een trainingsdag, anders vrij lopen) en "Start workout" in de details, enkel op de dag zelf. `AppModel.saveRun` bewaart en geeft de loop aan de coach.
- `Info.plist`: `NSMotionUsageDescription`. Versie 0.5 (build 5).
- Nog niet: gemiste sessies automatisch melden en `finishWeek` bij een nieuwe week (volgende stap, ruim voor zondag 25 okt), loopband-modus zonder GPS.

Routes plannen bijgestuurd (18 okt, na eerste test "finicky"): punten worden op de weg gelegd zoals Apple Kaarten ze plaatst (geen spieën meer van het getikte punt naar de weg), melding bij een stuk met een omweg (meer dan 2,5× en 250 m langer dan in vogelvlucht), schakelaar **Langs straten** (uit = rechte lijnen), "terug bij start" mag 25 m ernaast liggen. Vergeleken met Strava: daar ook punten verslepen, tekenen met de vinger en routes op populariteit (heatmap). Punten verslepen staat op de lijst voor na dinsdag; populariteit kan niet zonder data van anderen.

Stap 2 (lopen), plan goedgekeurd 15 okt:
- Kadans komt mee (bewegingssensor, extra toestemming). Live stats op het vergrendelscherm later, samen met de widget (vraagt een extra extensie).
- **Volgorde (beslist 15 okt):** eerst de `WorkoutEngine` in LoopCore (testbaar in Actions). Loopscherm, `RunTracker` (GPS, klok, stem, kadans), Na de loop en gemiste sessies/`finishWeek` pas na de PoC-test op de iPhone, zodat dat deel op een bewezen basis gebouwd wordt.
- `WorkoutEngine` (15 okt geschreven): pure logica. De app geeft looptijd zonder pauzes, totale afstand en actueel tempo door; de engine geeft cues, afgesloten blokken (`BlockResult`) en km-splits terug, en maakt op het einde een `CompletedRun`.
  - Blokovergangen op tijd of afstand, met interpolatie tussen twee metingen (klopt ook als metingen vertraagd binnenkomen).
  - Cues: begin blok ("Interval 3 van 6: 1 minuut op 4 minuten 50."), aftellen ("Nog 100 meter." vanaf 300 m, "Nog 10 seconden." vanaf 30 s), tempo in snelle blokken (buiten zone + 2 s speling, 15 s aanhoudend, niet in de eerste 20 s, hooguit om de 30 s: "Iets sneller/rustiger. Je loopt ..."), rustige blokken enkel te snel (5 s voorbij de zone, 30 s aanhoudend, hooguit om de 2 min), halverwege lange snelle blokken één keer "Op tempo", per km "3 kilometer. 6 minuten 12 per kilometer.", einde met afstand, tijd en gemiddeld tempo. "Nog 3 te gaan" bij het herstel als die instelling aan staat.
  - Overslaan sluit het blok af; stoppen markeert "vroeger gestopt" enkel als er nog meer dan het uitlopen restte.
  - Labels voor het loopscherm ("SNEL · 3 VAN 6", "TIJDRIT") en `paceStatus` (op tempo, te snel, te traag) voor de kleur.
  - Tellingen van de tests eerst gecontroleerd met een Python-port van de engine.

Bestanden app (`LoopApp/`):
| Bestand | Inhoud |
|---|---|
| `LoopApp.swift` | `@main`, tabbalk-uiterlijk, `RootView` (onboarding of 5 tabbladen, foutmelding) |
| `AppModel.swift` | Plan, coach, loopjes, backup |
| `UI/Theme.swift` | Kleuren, typekleuren, `Fmt`, `DateText` (nl_BE), `Card`, `SectionLabel`, `TypeTag`, `StatBlock`, knopstijlen, `Chip`, `ChoiceCard`, `Segmented`, `LoopToggleStyle`, `BigStepper`, `ProgressRing`, `Bar` |
| `Onboarding/OnboardingView.swift` | Vragenreeks, `NumberBox`, `PlanPreview`, `PhaseStrip`, `PlanTexts` |
| `Today/TodayView.swift`, `Today/Sheets.swift` | Vandaag, `WeekHeader`, `CoachMessageCard`, Extra loop, Niet 100% |
| `Shared/WorkoutViews.swift` | `WorkoutCard`, `WorkoutDetailView`, `StepRow` |
| `Plan/PlanView.swift`, `Calendar/CalendarView.swift`, `Progress/VoortgangView.swift`, `Settings/SettingsView.swift` | De tabbladen, `ManualRunSheet`, `BackupDocument` |
| `Debug/*` | Proof of concept |
| `Map/RoutesMapView.swift` | Routekaart (gelopen routes) en routes plannen, `RoutePlanner`, `RunLine` |
| `LiveActivity/RunActivity.swift` | Gedeeld met `RunnerWidgets`: Live Activity-gegevens en knoppen |
| `Assets.xcassets/AppIcon.appiconset/` | App-icoon Runner (1024 px), bron in `Design/runner-icon.svg` |

## Opslag (`RunStore.swift`, `RunRecord.swift`, `Stats.swift`)
- Map Documenten/LoopApp: `coach.json` (invoer + aanpassingen), `runs/<id>.json` per loop, `runs-index.json` (samenvattingen, nieuwste eerst), `meta.json` (laatste backup).
- `CompletedRun`: datum, bron (gps/loopband/manueel), plek in plan, **workout zoals toen gepland**, status, afstand, tijd, km-splits, per blok doel vs. echt, route (3 lijsten lat/lon/tijd), RPE, pijn, kadans, notitie. `coachResult` zet hem om voor de coach.
- `Backup`: versie 1, JSON met coach + alle loopjes. Nieuwere versie wordt geweigerd.
- `Stats`: weekkilometers gepland vs. gelopen (op datum, dus ook vrije loopjes), PR's uit opeenvolgende volle km-splits (manuele loopjes enkel voor langste loop).
- `Coach.moveWorkout`: verslepen binnen de week, resultaat `moved(warning:)`, `dayTaken`, `nothingToMove`, `alreadyDone`.

## Status (18 oktober 2026, zie ook de versies hieronder)
- ✅ **LoopApp staat op de iPhone en opent (18 okt).** De route GitHub Actions → `LoopApp.ipa` → iloader → iPhone werkt.
- 🔄 Naam Runner en nieuw icoon (18 okt): klaar in de repo-bestanden, nog te pushen en te controleren op de iPhone (build 0.3).
- ✅ LoopCore (plan-brein, coach, opslag) volledig getest in GitHub Actions.
- ✅ Alle schermen getekend in stijl D en goedgekeurd (15 okt).
- ✅ SwiftUI stap 1 (15 okt): app-build en LoopCore-tests groen, draait op de iPhone.
- ✅ `WorkoutEngine` + tests + cue-preview (15 okt): LoopCore-tests en app-build groen in Actions.
- 🔄 Eerste Diagnose-test (18 okt, binnenshuis gewandeld): GPS liep door met scherm uit (107 punten in 173 s achtergrond). "Haperde" kwam door zwak binnensignaal (punten >30 m onnauwkeurig weggefilterd, gat 17 s) en de afstand (0,27 km) en tempo's zijn binnen onbruikbaar. Stem en cues klonken. Echte test buiten (10+ min, scherm vergrendeld) nog te doen. Fout `kCLErrorDomain 1` bij de start = toestemmingsvraag stond nog open, eenmalig.
- 🔄 UI-ronde 18 okt (Vandaag, maandkalender, kleinere letters): klaar in de repo-bestanden, nog te pushen en te bekijken op de iPhone.

**Installeren en verversen (werkwijze sinds 18 okt):**
1. iloader (2.3.10 of nieuwer) op de pc, iPhone met kabel, ontgrendeld.
2. In de iloader-instellingen de **keyring uitschakelen**. Staat die aan, dan faalt het met "Platform secure storage failure: Windows error code 8". Een iloader-update kan die instelling terugzetten, dus na elke update controleren.
3. **Reset Anisette State**, iPhone opnieuw selecteren, anisette-server **Jkcoxson (Windows)**.
4. Inloggen, 2FA-code via de iPhone.
5. **Import IPA** › `LoopApp.ipa` uit de nieuwste Release.
6. Eerste keer: op de iPhone Instellingen › Algemeen › VPN en apparaatbeheer › Apple ID vertrouwen.
7. De app verloopt na 7 dagen (eerste keer: 25 okt). Dan stappen 1 tot 5 opnieuw. Backup maken vóór het opnieuw installeren is veilig, al blijven de gegevens normaal bewaard bij een herinstallatie over de bestaande app heen.

**Achtergrond van de storing (12 tot 18 okt):** sinds 12-13 okt weigert Apple logins via de standaard anisette-servers (fout -80045, treft SideStore, iloader, AltServer en Sideloadly; zie iloader #859, SideStore #1652/#1658, anisette-v3-server #61). Enkel Windows-anisette werkt nog, en niet voor elk account. Afspraken die blijven gelden:
- Bij -80045 of 503: stoppen, niet blijven proberen of van server wisselen.
- Bij -20209 (Apple ID geblokkeerd na herhaalde logins): eerst ontgrendelen via iforgot.apple.com.
- Fouten die vóór het inloggen bij Apple optreden (zoals de keyring-fout) tellen niet als poging.

**Gratis alternatieven bekeken (16 okt), voor als iloader ooit niet meer werkt:** Xcode op de Mac van Louis' vriendin (Personal Team, gratis, geen last van anisette) zou werken, maar valt af: te weinig schijfruimte (Xcode vraagt 30 à 40 GB). Valt ook af: PWA (geen GPS met scherm uit), macOS-VM op Windows, EU-route met alternatieve appwinkels (vraagt betaald account), TrollStore (enkel oude iOS), eigen anisette-server (veel werk, onzeker, risico op blokkade). Betaald account: nee.

## Feedbackronde na de eerste loop (20 okt, versie 0.6)
Eerste loop: vrij lopen, 4,02 km in 18:14 (4:32 per km), bewust all-out over 4 km (5 km had Louis niet volgehouden).
- **Niveau 40 (keuze van Louis).** Formule geeft 42,4, maar een korte all-out loop test vooral snelheid. Toepassen via de nieuwe niveautest of via Plan › Niveau aanpassen.
- **Niveautest uit een gelopen loop** (`LevelTest.swift`): vanaf 5 km telt het gemeten niveau volledig, korter telt de helft van het verschil met het huidige niveau, naar beneden afgerond op 0,5 (voor deze loop: 40,0). `Coach.setLevel(_:fromWeek:)` geldt vanaf de huidige week en blokkeert 2 weken nieuwe tempovoorstellen. Scherm `Plan/LevelSheet.swift` (stappen van 0,5, vergelijking nu → nieuw van 5 km, 10 km, rustig, tempo, interval). Tests `LevelTestTests`.
- **Detail per loop** (`Progress/RunDetailView.swift`): tik op een loop in Voortgang, swipe tussen loopjes (nieuwste eerst). Route (tik = volledig scherm met start en einde), 9 cijfers (ook beste km, starttijd, bron), geplande workout, snelle blokken tegenover doel, tempo per km als staafjes (snelste in oranje), notitie, Gebruik als niveautest, Loop verwijderen. Na de loop gebruikt dezelfde onderdelen.
- **Loop verwijderen**: knop in het detail (lang drukken in de lijst blijft). Een loop van minder dan 100 m én minder dan 3 minuten wordt bij Stop niet bewaard ("Stoppen zonder bewaren"), ook via het vergrendelscherm.
- **Signalen (in plaats van of naast de stem):** versie 1 (eigen sinustonen) vond Louis schel, versie 2 (Kenney en akx, CC0) beviel minder dan de eigen aanpak. Versie 3 = eigen synthese volgens richtlijnen voor UI-geluiden en earcons: grondtonen ongeveer 260 tot 1050 Hz, hoog doorlaat 120 Hz, laagdoorlaat 3,2 kHz tegen schelheid, FM-klank (warm = marimba, helder = klok) met mallet-tikje en body een octaaf lager, korte stereogalm, alles in C groot, stijgend = sneller of positief, dalend = rustiger, eigen ritme per melding, eerste noot met accent en laatste noot langer, gelijke luidheid (RMS -14 dB, pieken max -1 dB). Momenten: km, aftellen (3x), snel blok, herstel, te traag, te snel, terug op tempo, klaar, pauze, hervat. Bron `Design/sounds/generate_sounds.py`, proefpagina "Runner signalen" (versie 3). **Keuze Louis (20 okt): overal warm (marimba).** Te traag en te snel leken te veel op elkaar; versie 3.1: te traag = tik-tik-TIK (G5, G5, C6, kort en hoger), te snel = twee lange lage dalende noten (E5 naar A4). Verschil zit nu in aantal noten, ritme en register.
- **Loopscherm, voorstel van Claude (mockup "Runner loopscherm", 20 okt):** drie pagina's om tussen te swipen (cijfers, kaart, kilometers). Cijfers: bloklabel in typekleur, overzichtsbalk van de hele workout (A), groot resterend deel met voortgang, volgend blok, tempometer met doelband (B), gemiddeld tempo van het blok (C), afstand, totale tijd, kadans. Kaart (D) met compacte kop. Kilometers (E): tempo per km en snelle blokken tegenover doel. Tijdrit: schema voor of achter in seconden en eindtijd (F). Vergrendelknop (H): houd 1 s vast om te ontgrendelen. **Goedgekeurd door Louis (20 okt).**
- **Live Activity, voorstel (zelfde canvas, rij 2):** kaart van max 160 pt hoog. Interval: bloklabel in typekleur + volgend blok, groot resterend deel, tempo in statuskleur met doelzone, voortgangsbalk, Pauze en Blok overslaan. Vrij lopen: tijd, afstand, tempo, Pauze. Gepauzeerd: oranje rand, Hervat en Stop. Afgerond: samenvatting, 15 min zichtbaar. Dynamic Island: compact (resterend links, tempo rechts), minimaal (voortgangsring), uitgeklapt (alles plus knoppen). Goedkeuring afwachten.

## Versie 0.6 gebouwd (20 okt, alles in één zip `Runner-0.6.zip`)
Bevat: plan start in de huidige week, detail per loop, loop verwijderen, korte loop niet bewaren, niveau aanpassen en niveautest, signalen, nieuw loopscherm en nieuwe Live Activity.
- **Signalen** (`Run/RunSignals.swift`, `Sounds/signal-*.m4a`, versie 3.1 warm): Instellingen › Tijdens het lopen: Stem / Signalen (standaard) / Beide, met een lijst om elk signaal te beluisteren. `Speaker.play(_:)` speelt ze via dezelfde audiosessie (muziek stiller, pas terug luider als zin en signaal klaar zijn). Bij Beide eerst het signaal, dan de zin. Koppeling: start en snel blok = snel, rustig/herstel = herstel, te traag/te snel = sneller/rustiger, halverwege of 8 s terug in de zone na een waarschuwing = optempo ("Weer op tempo."), km = km, einde = klaar, pauze/hervat. Aftellen: 3 signalen op de laatste 3 s van een tijdsblok voor een snel blok, en op 3-2-1 bij de start. De schakelaars bij "Wat je hoort" gelden voor stem en signalen.
- **Loopscherm** (`Run/RunScreen.swift`): drie pagina's (cijfers, kaart, kilometers) met stipjes, vaste knoppen onderaan. Cijfers: overzichtsbalk (`OverviewStrip`), groot resterend deel "van 800 m", volgend blok, tempokaart met `PaceMeter` (doelzone groen, links trager, rechts sneller), raster gem. dit blok / afstand / totale tijd / kadans (vrij lopen: afstand, gem. tempo, lopende km, kadans). Tijdrit over een afstand: `ScheduleCard` (seconden voor of achter, doel en verwachte eindtijd). Kaart volgt je positie en is niet versleepbaar (anders botst het met swipen). Kilometers: `LiveSplitsCard` en `LiveBlocksCard`. Slotje: tikken doet niets, 1 s vasthouden ontgrendelt. Bloklabel met het type ("INTERVAL · 3 VAN 5" in plaats van "SNEL").
- **Live Activity** (`RunnerWidgets.swift`, `ContentState` uitgebreid met standaardwaarden zodat Diagnose blijft werken): zoals de mockup. Balk loopt zelf bij tijdsblokken (`ProgressView(timerInterval:)`), afstandsblokken verversen om de 5 s. Dynamic Island: compact, minimaal (ringetje), uitgeklapt.
- Afwijking van de mockup: vergrendeld blijft de pagina zelf zichtbaar (geen apart vereenvoudigd scherm), enkel de knoppen worden het slotje.
- Controle: Swift-syntax met tree-sitter, echte build in Actions nog te doen.

## Versie 0.7 (20 okt, `Runner-0.7.zip`, na 0.6)
- **Gemiste trainingen en weekafsluiting** (`Coach.catchUp(until:)`, tests `CatchUpTests`): bij elke start en elke terugkeer naar de app (`scenePhase` actief) worden geplande trainingen van vóór vandaag zonder loop als gemist genoteerd, met de bestaande regels (rustig valt weg, kwaliteit en lange loop schuiven naar een vrije dag, maar nooit naar een dag die al voorbij is), en wordt elke week met een voorbije zondag afgesloten (`finishWeek`). Elke dag maar één keer: `AdaptationState.processedThrough` (optioneel veld, oudere gegevens laden gewoon). Extra loopjes worden niet als gemist genoteerd.
- **Vrije loop koppelen** (detail van een vrije loop op een trainingsdag): kaart "Gepland die dag" met "Meetellen als ...". De loop krijgt de plandag en workout, de coach krijgt hem via `Coach.recordLinked` (een eerder "gemist" voor die dag vervalt, samen met de verplaatsing die het veroorzaakte). Ook bruikbaar voor de vrije loop van dinsdag 20 okt.
- **Automatisch pauzeren** (schakelaar Instellingen › Lopen, standaard aan): pauzeert bij minder dan 8 m in 10 s met een verse GPS-meting (±20 m of beter) en snelheid onder 0,8 m/s, hervat bij twee metingen sneller dan 1,6 m/s of meer dan 15 m verplaatsing. Enkel in vrij lopen, inlopen, uitlopen en rustige blokken (lange loop), niet in snelle blokken of herstel. Daarna 15 s geen nieuwe autopauze. Label "AUTOPAUZE", stem of signaal zoals een gewone pauze.
- **Diagnose verwijderd**: `LoopApp/Debug/` is weg. `Speaker` staat nu in `Run/Speaker.swift`, `Format` in `Run/Format.swift`. Proof of concept is daarmee afgesloten.
- Versie 0.7 (build 7).

## Versie 0.8 (22 okt, `Runner-0.8.zip`, na de lange loop van donderdag 22 okt)
Feedback van Louis na zijn lange loop:
1. **Voortgang in het huidige blok** in de overzichtsbalk bovenaan het loopscherm. Voorheen had het huidige blok enkel een witte rand; bij een lange loop (één blok) zag je dus geen voortgang in de balk.
2. **Tempo "nu" schommelde** tussen 7:00 en 4:55 bij een gelijk tempo, vermoedelijk door GPS dat wegviel en terug inpikte.

Oorzaak van 2: het tempo was de afgelegde GPS-afstand over de laatste 30 s. Bij zwak signaal verspringen posities (de afstand wordt opgeblazen, dus te snel) of lopen ze achter en halen ze daarna in (eerst te traag, dan te snel). Simulatie in Python (`scratchpad`, niet in de repo): bij een echte 6:10 gaf de oude methode na zwak signaal tot 3:04.

Gebouwd:
- **`OverviewStrip`** (`Run/RunScreen.swift`): het huidige blok krijgt minstens 40% van de breedte (de rest schuift naar verhouding mee, animatie bij elke blokwissel), vult zich in de typekleur over een lichte versie van dezelfde kleur, en een wit staafje (3 × 20 pt) schuift mee. Voortgang op afstand of tijd, naargelang het blok (`engine.progress`). Gedane blokken gedimd, komende grijs. `RunTracker.Segment` kreeg `progress`. De aparte balk onder het grote getal op de cijferpagina is weg (dubbel); op de kaart- en kilometerpagina blijft hij.
- **`LivePace`** (LoopCore, tests `LivePaceTests`, grenzen nagerekend met een Python-port): (1) Doppler-snelheid van de GPS (`CLLocation.speed`), los van de positie, enkel met `speedAccuracy` ≤ 1,5 m/s; (2) valt die weg, de laatste waarde 10 s vasthouden; (3) daarna het tempo van de pasteller (`CMPedometerData.currentPace`). Mediaan van de laatste 5 metingen (één uitschieter doet niets), dan een tijdsgewogen glijdend gemiddelde (± 5 s, 8 s bij minder nauwkeurige Doppler of pasteller). Stilstaan (trager dan 20:00/km) of 15 s zonder meting = "-:--". Reset bij start en na elke pauze. Een intervalwissel 6:10 → 4:50 staat na ± 10 s op het scherm (oude methode: ± 30 s). De tempo-cues (te snel/traag) gebruiken hetzelfde tempo, dus ook minder valse waarschuwingen.
- **Tijd per meting** = moment van de GPS-meting, niet het moment van binnenkomen (op de achtergrond komen metingen in groepjes).
- **Afstand bij zwak signaal**: bij een positie van ±15 m of slechter én een bruikbare Doppler-snelheid telt een stuk hooguit snelheid × tijd + 20%. Bij goed signaal verandert er niets.
- `Format.rollingPace` verwijderd (niet meer gebruikt). Versie 0.8 (build 8).

Nog te bekijken na een echte loop: of de afstand bij goed signaal ook beter van de Doppler-snelheid komt. Daarvoor zou de app per GPS-punt snelheid en nauwkeurigheid moeten bewaren (idee: optioneel GPS-logboek als CSV), zodat beide methodes op echte data te vergelijken zijn.

## Volgende stap
1. **Versie 0.8 pushen**, LoopCore-tests (`LivePaceTests`) en app-build in Actions controleren, installeren via iloader. De app verloopt zaterdag 25 okt, dus best samen met die herinstallatie.
2. Volgende loop: letten op de overzichtsbalk (staafje, verbreding bij intervallen) en of tempo "nu" rustig blijft, ook onder bomen of tussen hoge gebouwen.
3. Openstaand: punten verslepen in de routeplanner, coach-meldingen bewaren tussen app-starts, meldingen (trainingsdag, herinstallatie na 7 dagen), widget, Apple Health, loopband-modus.
