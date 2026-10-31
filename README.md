# Muse — Persönliche KI-App

Eine native iOS-App (SwiftUI, iOS 26) in ruhigem, warmem Design (hell/dunkel
je nach System): die persönliche KI **Muse** (auch „Mochi“ genannt) mit Chat,
Feed, Ideen, Zielen und Bibliothek — native Tab-Bar, Serif-Titel und vier
animierte **Begleiter** (Mochi, Bit, Neko, Boo), die im Chat neben den
Antworten sitzen, blinzeln und bei jeder Antwort hüpfen. Der Begleiter wird
in der Bibliothek gewählt.

## Tabs

- **Chat** — mit Muse schreiben, Claude-artig: Antworten als reiner Text,
  eigene Nachrichten in dezenten Bubbles. Engine nach Wahl: ein eigener
  API-Key (Anbieter-Presets unten) oder der lokale **Demo-Modus** ohne Key.
  Nachrichten lassen sich auch am Stück hintereinander abschicken (FIFO-
  Sende-Warteschlange, eine Antwort nach der anderen), und alle Chats
  bleiben im **Chatverlauf** (Uhr-Symbol oben rechts) erhalten — antippen
  zum Weiterlesen, wischen zum Löschen, „Neuer Chat“ startet frisch.
- **Feed** — GTA-6-Countdown (live), deine Vibes aus dem Onboarding,
  Karte des Tages, Muse Royal Casino, Ideen-Teaser.
- **Ideen** — Karten speichern oder verwerfen, eigene Ideen anlegen.
- **Ziele** — Ziele mit Schritten, Fortschrittsring und Abhaken.
- **Bibliothek** — Begleiter-Auswahl, Gespeichertes, dein Profil und
  Einstellungen (inkl. „Verbindung testen“-Knopf zur Selbstdiagnose).

## KI-Engine

- **Gemini (Google) — gratis Key** (Standard): native Gemini-API
  (`POST https://generativelanguage.googleapis.com/v1beta/models/{Modell}:generateContent`,
  Header `x-goog-api-key`). Key gibt es gratis im Google AI Studio
  (aistudio.google.com → „Get API key“, nur Google-Login, keine
  Kreditkarte). Standard-Modell: `gemini-3.8-flash`.
- **OpenAI-kompatibel**: OpenAI-Chat-Completions-Protokoll
  (`POST {API-Adresse}/chat/completions`, Bearer-Key) mit freier
  API-Adresse und Modellwahl (z. B. OpenAI, Groq, OpenRouter).

Fehlermeldungen der Anbieter werden im Chat und im Verbindungstest im
Wortlaut angezeigt. Jeder Anbieter speichert seinen eigenen Key in der
Keychain. Ohne Key läuft der Chat im Demo-Modus (lokale Antworten, kein
Banner). Es ist **kein Key im Code hinterlegt**.

Alle Daten (Profil, Ziele, Ideen, Gespeichertes, Begleiter-Wahl und der
komplette Chatverlauf) bleiben lokal in UserDefaults auf dem Gerät.

## Bauen

CI baut bei jedem Push auf `main` und bei jedem Release eine unsignierte
IPA (`.github/workflows/build-ipa.yml`) und hängt sie ans Release.
Installation per Sideloadly/AltStore mit eigener Apple-ID.
