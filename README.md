# Muse — Persönliche KI-App

Eine native iOS-App (SwiftUI, iOS 26) im Liquid-Glass-Design: die persönliche
KI **Muse** (auch „Mochi“ genannt) mit Chat, Feed, Ideen, Zielen und
Bibliothek — schwebende Glas-Tab-Bar, violetter Farbverlauf, Orb-Avatar.

## Tabs

- **Chat** — mit Muse schreiben. Engine nach Wahl: ein eigener API-Key
  (Anbieter-Presets unten) oder der lokale **Demo-Modus** ohne Key.
- **Feed** — GTA-6-Countdown (live), deine Vibes aus dem Onboarding,
  Karte des Tages, Muse Royal Casino, Ideen-Teaser.
- **Ideen** — Karten speichern oder verwerfen, eigene Ideen anlegen.
- **Ziele** — Ziele mit Schritten, Fortschrittsring und Abhaken.
- **Bibliothek** — Gespeichertes, dein Profil und Einstellungen.

## KI-Engine

OpenAI-kompatibles Chat-Completions-Protokoll
(`POST {API-Adresse}/chat/completions`, Bearer-Key):

- **Gemini (Google) — gratis Key** (Standard): Key gibt es gratis im
  Google AI Studio (aistudio.google.com → „Get API key“, nur Google-Login,
  keine Kreditkarte). Standard-Modell: `gemini-2.5-flash`.
- **OpenAI-kompatibel**: freie API-Adresse und Modellwahl (z. B. OpenAI,
  Groq, OpenRouter).

Jeder Anbieter speichert seinen eigenen Key in der Keychain. Ohne Key läuft
der Chat im Demo-Modus (lokale Antworten, kein Banner). Es ist **kein Key im
Code hinterlegt**.

Alle Daten (Profil, Ziele, Ideen, Gespeichertes) bleiben lokal in
UserDefaults auf dem Gerät.

## Bauen

CI baut bei jedem Push auf `main` und bei jedem Release eine unsignierte
IPA (`.github/workflows/build-ipa.yml`) und hängt sie ans Release.
Installation per Sideloadly/AltStore mit eigener Apple-ID.
