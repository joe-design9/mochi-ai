# QA — Screenshot-Check der Antwort-Verankerung (Simulator)

Zweck: **Vor jedem Release visuell prüfen**, ob eine lange Antwort im
Chat ohne Scrollen lesbar ist (v2.2.2-Ankerregel). Dafür gibt es einen
internen Testmodus, der **niemals** in den Release-IPAs erreichbar ist.

## Wie der Modus abgesichert ist (doppelte Sperre)

1. **Build-Konfiguration `QA`** (Klon von `Debug`) setzt die
   Compilation Condition `QA` (Projekt-Ebene in
   `MochiAI.xcodeproj/project.pbxproj`, IDs `…0016`/`…0017`).
   Release/Debug kompilieren die Bedingung nicht — der Codepfad
   existiert in den ausgelieferten IPAs praktisch nicht. Der
   Release-Workflow (`.github/workflows/build-ipa.yml`) ist davon
   unberührt und baut weiter nur `Release`.
2. **Startargument `-UITestMode`**: Nur wenn beides zusammenkommt
   (`AppStore.seedUITestDataIfRequested()`), überspringt die App das
   Onboarding mit einem lokalen Testprofil („QA Tester") und startet
   im Chat-Tab mit einer **voreingestellten Unterhaltung**: zwei kurze
   Austausche, als letzte Nachricht eine **lange, mehrteilige
   Beispiel-Antwort** (deutscher Testtext, beginnt mit „TESTTEXT").
   Alles lokal — kein Netz, kein API-Key nötig.

## QA-Build erzeugen (iOS Simulator)

```sh
xcodebuild \
  -project MochiAI.xcodeproj \
  -scheme MochiAI \
  -configuration QA \
  -sdk iphonesimulator \
  -derivedDataPath "$PWD/build-qa" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

## Installieren, starten, fotografieren

```sh
xcrun simctl install booted build-qa/Build/Products/QA-iphonesimulator/MochiAI.app
xcrun simctl launch booted dev.joe.mochiai -UITestMode
xcrun simctl io booted screenshot chat-verankerung.png
```

## Was der Parent im Screenshot prüft

- Die App zeigt direkt den Chat (kein Onboarding) mit der
  Beispiel-Unterhaltung.
- Die lange Antwort ist **an ihrem Anfang verankert**: Die erste
  Zeile des Testtexts („TESTTEXT — lange Beispielantwort …") steht
  **oben** im Nachrichtenbereich, direkt unter der Kopfzeile.
- **Fehlerbilder** (nicht freigeben): Der Screenshot zeigt das
  Gesprächsende / die letzte Testtext-Zeile („…sonst ist die
  Verankerung falsch herum") oder die Textmitte — dann steht die
  Ansicht am falschen Anker und die Version geht nicht raus.

## Erweiterte Capture-Matrix (ab v2.3.0)

Der QA-Workflow (`.github/workflows/mochi-qa.yml`, temporär per
Browser hochgeladen) fotografiert auf einem **iPhone 15 Pro Max**
(nicht „irgendein iPhone") mit erzwungener Software-Tastatur die
komplette Oberfläche — zwei volle Läufe, beide müssen grün sein:

| Datei | Start | Prüft |
|---|---|---|
| `onboarding.png` | frische Installation, **keine** Argumente | echtes Onboarding (erster Screen) |
| `chat.png` | `-UITestMode -QASendFlow` (Phase 0) | lange Antwort oben verankert |
| `sendflow1.png` / `sendflow2.png` | Send-Flow-Phasen 1/2 | Antwort sichtbar, unten verankert, `focus=1` im Badge (Tastatur bleibt offen) |
| `feed.png` | `-UITestMode -QAStartTab 1` | Feed inkl. GTA-6-Countdown-Karte |
| `ideas.png` | `-UITestMode -QAStartTab 2` | Ideen-Karten |
| `goals.png` | `-UITestMode -QAStartTab 3` | Ziele mit Fortschrittsringen |
| `library.png` | `-UITestMode -QAStartTab 4` | Bibliothek inkl. About-Zeile „Version 2.4.0" |
| `chat-empty.png` | `-UITestMode -QAEmpty` | echter Chat-Leerzustand (Willkommens-Hero) |
| `ideas-empty.png` | `-UITestMode -QAEmpty -QAStartTab 2` | Ideen-Leerzustand |
| `goals-empty.png` | `-UITestMode -QAEmpty -QAStartTab 3` | Ziele-Leerzustand |
| `library-empty.png` | `-UITestMode -QAEmpty -QAStartTab 4` | Bibliothek mit leerer Gespeichert-Sektion |
| `call.png` | `-UITestMode -QACallPreview` | Anruf-Screen rendert nur (Controller startet nicht: kein Mikrofon-Dialog, kein Netz) |

Jede Glasfläche wird gegen das freigegebene Rezept geprüft: native
TabView, `glassTint` (dunkel: Weiß 0,08 @ 52 %) auf jeder neutralen
Glasfläche, Rim-Gradient 0,30 → 0,04, Backdrop reines Schwarz +
Sheen 0,075 — keine flachen Plastik-Fills.

## v2.4.0 — Dark Appearance, Invite-Gate, Admin-Variante

Ab v2.4.0 läuft die Matrix in **Dark Appearance** (`simctl ui …
appearance dark` direkt nach dem Boot) — Joel beurteilt Glas auf
seinem Gerät im Dark Mode; die hellen Captures aus v2.3.0 konnten
die Glasflächen nicht bewerten. Zwei Aufnahmen kommen dazu:

| Datei | Start | Prüft |
|---|---|---|
| `gate.png` | frische Installation, **keine** Argumente | Invite-Gate — der echte erste Screen der Normalversion seit v2.4.0 |
| `onboarding.png` | gleiche Installation, `-QAPreviewOnboarding` | Onboarding (QA-only Gate-Bypass, nur Anzeige — nichts wird eingelöst/persistiert) |
| `admin-invites.png` | **QAAdmin**-Build (Bundle `dev.joe.mochiai.admin`), `-UITestMode -QAAdminInvites -QAStartTab 4` | Bibliothek der Admin-Version mit Invite-Codes-Sektion; zwei lokale Sample-Codes (einer offen, einer eingelöst), kein Netz |

Der Workflow baut dafür zusätzlich die Konfiguration `QAAdmin`
(Schema `MochiAIAdmin`). Die Invite-Sektion steht in der
Admin-Bibliothek bewusst ganz oben (erster Screen der Sektion =
Capture-Fläche und Joels Hauptzweck mit der Admin-App).
