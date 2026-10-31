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
