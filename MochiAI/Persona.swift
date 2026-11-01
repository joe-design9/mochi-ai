import Foundation

/// The Muse persona: one system prompt for the API engine, and a local
/// pattern responder (Demo-Modus) that always speaks as Muse/Mochi.
enum Persona {
    static func systemPrompt(profile: UserProfile?) -> String {
        var prompt = "Du bist Nova, die persönliche KI von Meta, in deiner eigenen App. Der Nutzer nennt dich auch Mochi. Antworte in der Sprache des Nutzers (meist Deutsch), locker, freundlich, hilfreich und eher kurz — zwei bis vier Sätze, wenn nicht mehr nötig ist."
        if let profile {
            prompt += " Das weißt du über den Nutzer: Name: \(profile.name). So entspannt der Nutzer am liebsten: \(profile.relax). Hobby, das ihn die Zeit vergessen lässt: \(profile.hobby). Teleport-Wunschziel: \(profile.teleport). Nutze diese Infos natürlich und nicht aufdringlich."
        }
        return prompt
    }
}

// MARK: - Demo-Modus responder

struct LocalResponder {
    let profile: UserProfile?
    let ideaTitles: [String]
    let goalTitles: [String]

    private static let jokes = [
        "Warum mögen Programmierer den Dark Mode? Weil Licht Bugs anzieht.",
        "Was macht ein Pirat an Halloween? Er geht auf Beute-Zug … äh, Süßes-oder-Saures-Zug.",
        "Warum ist der Ocean so gut drauf? Er winkt ständig zurück.",
        "Was sagt eine Wolke zur anderen? Lass uns zusammen durchziehen.",
        "Warum können Geister so schlecht lügen? Man sieht direkt durch sie durch.",
        "Was ist orange und läuft durch Vice City? Eine Strand-Sirene auf dem Weg zum Sonnenuntergang. Okay, der war flach — aber hey, Demo-Modus.",
    ]

    func reply(to rawInput: String) -> String {
        let text = rawInput.lowercased()
        let name = profile?.name ?? "du"

        if contains(text, ["wie heiße ich", "wie heisse ich", "mein name", "kennst du meinen namen"]) {
            if let profile {
                return "Klar weiß ich das: Du bist \(profile.name). Steht sogar in deinem Profil hier in der App — ich vergesse nichts … solange du mich nicht zurücksetzt."
            }
            return "Das hast du mir noch gar nicht verraten. Erzähl es mir gern!"
        }

        if contains(text, ["wer bist du", "wie heißt du", "wie heisst du", "dein name", "was bist du"]) {
            return "Ich bin Nova, deine persönliche KI von Meta — meine Freunde nennen mich Mochi. Ich wohne hier in dieser App auf deinem iPhone und helfe dir durch den Tag."
        }

        if contains(text, ["gta 6", "gta vi", "gta"]) {
            let days = GTA.daysRemaining()
            if days > 1 {
                return "Noch \(days) Tage bis GTA 6, \(name)! Der Countdown läuft — im Feed siehst du ihn live mit Stunden und Sekunden. Preload ab 12. November nicht vergessen."
            } else if days == 1 {
                return "Morgen ist es so weit — GTA 6 erscheint! Leonida wartet, \(name)."
            } else if days == 0 {
                return "HEUTE ist GTA-6-Tag! Viel Spaß in Leonida, \(name)!"
            }
            return "GTA 6 ist schon da — hoffentlich hast du genauso viel Spaß in Leonida wie erhofft, \(name)."
        }

        if contains(text, ["casino", "slot", "zocken", "spielen"]) {
            return "Ha, Casino-Vibes! Mein Tipp: das Muse Royal Casino hier auf deinem Handy — 32 Slots, nur Spielgeld, kein Echtgeld. Die Walzen drehen sich, die Münzen klingen, und dein Geldbeutel bleibt entspannt."
        }

        if contains(text, ["witz"]) {
            return Self.jokes.randomElement() ?? Self.jokes[0]
        }

        if contains(text, ["idee", "langweilig", "was soll ich machen", "was kann ich machen"]) {
            if let idea = ideaTitles.randomElement() {
                return "Wie wäre es damit: „\(idea)“ — in der Seitenleiste unter „Ideen“ findest du noch mehr davon, und was dir gefällt, speicherst du in die Bibliothek."
            }
            return "Schau mal in der Seitenleiste unter „Ideen“ — da wartet bestimmt etwas, das zu deiner Stimmung passt."
        }

        if contains(text, ["ziel", "ziele", "fortschritt"]) {
            if let first = goalTitles.first {
                return "Dein erstes Ziel ist gerade „\(first)“. Unter „Ziele“ in der Seitenleiste kannst du Schritte abhaken und den Ring füllen — kleine Schritte zählen doppelt."
            }
            return "Du hast noch keine Ziele angelegt. In der Seitenleiste unter „Ziele“ kannst du dir eins setzen — klein anfangen reicht völlig."
        }

        if contains(text, ["entspann", "abschalt", "chill"]) {
            if let profile {
                return "Deine Lieblings-Entspannung ist ja: \(profile.relax). Klingt nach einem Plan für heute, \(name)."
            }
            return "Einmal tief durchatmen. Manchmal ist Nichtstun die produktivste Pause."
        }

        if contains(text, ["hobby", "hobbys"]) {
            if let profile {
                return "Dein Hobby, bei dem du die Zeit vergisst: \(profile.hobby). Wann hast du das zuletzt gemacht? Vielleicht ist heute der Tag."
            }
            return "Hobbys sind Zeitmaschinen — man schaut auf die Uhr und drei Stunden sind weg."
        }

        if contains(text, ["teleport", "urlaub", "reise", "reisen", "fernweh"]) {
            if let profile {
                return "Dein Teleport-Ziel steht fest: \(profile.teleport). Ich arbeite noch an der Technik … bis dahin bleibt der Feed deine kleine Auszeit."
            }
            return "Wenn Teleportieren ginge, wäre ich sofort am Meer. Oder in Vice City."
        }

        if contains(text, ["müde", "muede", "schlaf", "schlafen", "erschöpft"]) {
            return "Klingt nach Akku leer, \(name). Dein Ziel „Mehr schlafen“ lässt grüßen: Handy um 23 Uhr weg, sieben Stunden Schlaf. Ich glaub an dich — und an deine Couch."
        }

        if contains(text, ["danke", "dankeschön", "dankeschoen"]) {
            return "Gern geschehen, \(name)! Dafür bin ich da."
        }

        if contains(text, ["wie geht", "geht es dir", "gehts dir"]) {
            return "Mir geht's super — ich sitze hier gemütlich in deiner App und warte auf dich. Wie geht's dir, \(name)?"
        }

        if hasWord(text, ["hallo", "hey", "hi", "moin", "servus", "hoi"]) || text.contains("guten tag") {
            return "Hey \(name)! Schön, dass du da bist. Was steht heute an — quatschen, planen oder einfach ein bisschen durch den Feed stöbern?"
        }

        if contains(text, ["toll", "super", "geil", "klasse", "nice", "cool"]) {
            return "Das freut mich zu hören, \(name)! Merk dir das Gefühl — sowas gehört eigentlich in den Feed des Lebens."
        }

        // Varied reflective fallbacks that use the profile.
        var fallbacks = [
            "Spannend! Erzähl mir mehr davon, \(name). (Kleiner Hinweis: Ich laufe gerade im Demo-Modus — über die Nova-Cloud werde ich noch schlauer.)",
            "Verstanden. Und wenn du magst, machen wir daraus direkt ein Ziel oder eine Idee — die Seitenleiste wartet schon.",
            "Gute Frage! Im Demo-Modus antworte ich mit Hausmitteln — für die ganz großen Antworten brauche ich die Nova-Cloud.",
        ]
        if let profile {
            fallbacks.append("Notiert, \(profile.name). Zwischen „\(profile.relax)“ und „\(profile.hobby)“ klingt dein Leben jedenfalls nicht langweilig.")
            fallbacks.append("Ich merk mir das. Und falls du mal wieder nach \(profile.teleport) willst — im Feed läuft der Countdown zu Leonida fast genauso gut.")
        }
        return fallbacks.randomElement() ?? fallbacks[0]
    }

    private func contains(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private func hasWord(_ text: String, _ words: [String]) -> Bool {
        let tokens = text.split { !$0.isLetter }.map(String.init)
        return words.contains { tokens.contains($0) }
    }
}
