# LoopTest (proof of concept)

Mini-app die drie dingen test voor we de volledige loopapp bouwen:

1. Werkt de route GitHub → .ipa → SideStore → iPhone?
2. Blijft GPS doorlopen met je scherm vergrendeld?
3. Klinken Nederlandse cues goed over je muziek (muziek even stiller, daarna terug)?

---

## Stap 1: GitHub-repo (10 min)

1. Ga naar github.com › **New repository**, naam `LoopTest`, zet hem op **Public** (gratis macOS-builds, er staat niets privé in).
2. Pak deze zip uit en upload **alles**, ook de map `.github` (die is op Windows soms verborgen: Verkenner › Beeld › Verborgen items aanvinken). Makkelijkst via **GitHub Desktop**, of via *Add file › Upload files* en de mappen erin slepen.
3. Open het tabblad **Actions**: de build start vanzelf en duurt zo'n 5 tot 10 minuten.
4. Groen vinkje? Dan staat `LoopTest.ipa` onder **Releases** (rechts op de repo-pagina).
   Rood kruis? Open de mislukte stap, kopieer de foutmelding en stuur ze naar mij.

## Stap 2: SideStore installeren (eenmalig, ongeveer een uur)

Volg de officiële gids op **docs.sidestore.io**, die wordt up-to-date gehouden. De grote lijnen:

1. **iPhone**: zet *Ontwikkelaarsmodus* aan (Instellingen › Privacy en beveiliging › Ontwikkelaarsmodus, iPhone herstart).
2. **Windows**: installeer **iTunes via apple.com** (niet de Microsoft Store-versie, niet Apple Music) en het installatieprogramma uit de SideStore-gids.
3. Sluit je iPhone met een kabel aan, kies *Vertrouw deze computer*, en installeer SideStore met je Apple ID.
4. **iPhone**: vertrouw je eigen ontwikkelaarsprofiel via Instellingen › Algemeen › VPN en apparaatbeheer, en installeer de VPN-app die de gids vraagt.
5. Open SideStore en log in met dezelfde Apple ID.
6. Tip: maak de opfris-automatisering in Opdrachten zoals de gids beschrijft, dan verloopt je app nooit na 7 dagen.

Met een gratis Apple ID mag je 3 apps sideloaden (SideStore telt mee), dus SideStore + LoopTest past ruim.

## Stap 3: LoopTest installeren

1. Open op je iPhone in Safari je repo › **Releases** › tik op `LoopTest.ipa` (komt in Bestanden › Downloads).
2. SideStore › **Mijn apps** › **+** › kies `LoopTest.ipa`.
3. Eerste keer openen: locatie **Bij gebruik van app** toestaan en **Exacte locatie** aan laten.

Optioneel maar aanrader: een betere stem downloaden via Instellingen › Toegankelijkheid › Gesproken materiaal › Stemmen › Nederlands (kies een "verbeterde" stem). De app pakt automatisch de beste.

## Stap 4: Testen

**Test A: intervaltest (6 min)**
1. Zet Spotify aan met wat muziek.
2. Open LoopTest › *Start intervaltest*.
3. Tijdens het aftellen: **scherm vergrendelen** en gsm wegsteken.
4. Loop 3 × 1 minuut snel met telkens 1 minuut wandelen.

**Test B: vrij lopen (minstens 2 km)**, scherm de hele tijd vergrendeld, tik daarna op *Stop*.

**Let op tijdens het lopen:**
- Hoor je de cues duidelijk? Gaat je muziek even stiller en daarna terug luider?
- Klopt "Nog 10 seconden" en de wissel tussen snel en wandelen?

**Na afloop** zie je je route, stats per blok en een **diagnose**:
- ✅ *GPS liep door met scherm uit* = geslaagd
- ❌ *GPS haperde* = stuur me een screenshot van diagnose + logboek
- Vergelijk de afstand eens met een gekende route (bv. Google Maps).

Stuur me na beide tests een screenshot van de diagnose en het logboek, plus hoe de cues klonken. Daarmee weten we of de basis staat.

---

## Wat zit er in de code

| Bestand | Wat |
|---|---|
| `Workout.swift` | Workout-opbouw, timing van cues, Nederlandse teksten (wordt later het plan-brein) |
| `RunSession.swift` | GPS, klok, afstand, tempo en diagnose |
| `Speaker.swift` | Nederlandse stem + muziek stiller zetten |
| `ContentView.swift` / `ResultView.swift` | Schermen |
| `project.yml` | Projectconfig, GitHub maakt hiermee het Xcode-project |
| `.github/workflows/build.yml` | Bouwt bij elke push een nieuwe `.ipa` |
