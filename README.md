# LoopApp

Persoonlijke loopcoach voor iPhone (native SwiftUI), gebouwd met GitHub Actions en geïnstalleerd met SideStore. Alles staat lokaal op de iPhone, zonder account of server.

## Structuur

| Map / bestand | Wat |
|---|---|
| `LoopApp/` | De app (SwiftUI) |
| `LoopApp/UI/Theme.swift` | Stijl D: kleuren, knoppen, kaarten, schakelaars |
| `LoopApp/AppModel.swift` | Plan, coach en loopjes; bewaart alles via `RunStore` |
| `LoopApp/Onboarding/` | Vragenreeks en preview van het plan |
| `LoopApp/Today/`, `Plan/`, `Calendar/`, `Progress/`, `Settings/` | De vijf tabbladen |
| `LoopApp/Shared/WorkoutViews.swift` | Workoutkaart, details en stappen |
| `LoopApp/Debug/` | Proof of concept (GPS met scherm uit, cues over muziek), via Instellingen › Diagnose |
| `LoopCore/` | Plan-brein: zones, plangenerator, coach, opslag. Getest in GitHub Actions |
| `project.yml` | XcodeGen: maakt het Xcode-project, koppelt LoopCore |
| `.github/workflows/build.yml` | Bouwt `LoopApp.ipa` en zet hem in Releases |
| `.github/workflows/core.yml` | Tests en plan-preview van LoopCore |

## Installeren

1. Push naar `main`. Actions bouwt de app (5 tot 10 minuten).
2. Op je iPhone in Safari: repo › **Releases** › `LoopApp.ipa`.
3. SideStore › **Mijn apps** › **+** › kies `LoopApp.ipa`.

Mislukt de build? Open de rode stap in Actions en kopieer de regels met `error:`.

## Stand van zaken

- Stap 1 (klaar): thema, vijf tabbladen, vragenreeks, Vandaag, Plan, Kalender, Voortgang, Instellingen, backup.
- Stap 2 (volgende): lopen met GPS en Nederlandse cues, scherm Na de loop.
