import Foundation

// MARK: - Built-in ideas

enum IdeaPool {
    static let all: [Idea] = [
        Idea(id: "idea-app", title: "Eigene Mini-App bauen",
             text: "Baue eine winzige App, die genau eine Sache richtig gut kann — zum Beispiel einen Countdown bis GTA 6 oder einen Münzwurf mit Stil.",
             category: "Tech"),
        Idea(id: "idea-sunset", title: "Sonnenuntergang-Spaziergang",
             text: "Handy in die Tasche, Lieblingsmusik oder einfach Stille — einmal raus und den Tag ausklingen lassen.",
             category: "Draußen"),
        Idea(id: "idea-leonida", title: "Video: Ein Tag in Leonida",
             text: "Dreh ein kurzes, witziges Video: Was würdest du an deinem ersten Tag in Leonida machen? Handy-Kamera reicht völlig.",
             category: "Video"),
        Idea(id: "idea-gamenight", title: "Spieleabend: Koop-Klassiker",
             text: "Such dir einen Koop-Klassiker aus der Bibliothek und spiel eine Runde mit Freunden online — Headset an, Chips bereit.",
             category: "Gaming"),
        Idea(id: "idea-photo", title: "Foto-Challenge: Violett",
             text: "Mach heute fünf Fotos, auf denen die Farbe Violett die Hauptrolle spielt. Das beste kommt in deine Bibliothek.",
             category: "Kreativ"),
        Idea(id: "idea-pasta", title: "Kochabend: Pasta wie in Italien",
             text: "Ein einfaches Pastagericht, gute Musik, Kerzenlicht — mehr braucht ein kleiner Italien-Abend zu Hause nicht.",
             category: "Essen"),
        Idea(id: "idea-playlist", title: "Playlist: Night Drive durch Vice City",
             text: "Stell eine Playlist aus zehn Songs zusammen, die sich anfühlen wie eine Nachtfahrt mit Neonlichtern.",
             category: "Musik"),
        Idea(id: "idea-room", title: "Zimmer-Upgrade: Lichtstimmung",
             text: "Eine LED-Leiste oder eine neue Lampe verändert den ganzen Raum. Klein anfangen: warmes Licht hinter dem Monitor.",
             category: "Zuhause"),
        Idea(id: "idea-surprise", title: "Jemanden überraschen",
             text: "Schick einer Person, an die du lange nicht gedacht hast, eine nette Nachricht. Kostet nichts, wirkt Wunder.",
             category: "Sozial"),
        Idea(id: "idea-learn", title: "Lern-Sprint: Eine Stunde, ein Thema",
             text: "Such dir ein Thema, das dich neugierig macht, und tauch genau eine Stunde ein — Video, Artikel, Notizen.",
             category: "Lernen"),
    ]
}

// MARK: - Daily feed cards

struct DailyCard {
    let title: String
    let text: String
}

enum DailyPool {
    static let all: [DailyCard] = [
        DailyCard(title: "Impuls des Tages", text: "Kleine Schritte jeden Tag schlagen große Pläne, die nie starten."),
        DailyCard(title: "Tipp des Tages", text: "Handy beim Essen weglegen — alles schmeckt sofort besser."),
        DailyCard(title: "Impuls des Tages", text: "Du musst nicht perfekt starten. Du musst nur starten."),
        DailyCard(title: "Tipp des Tages", text: "Ein Glas Wasser vor dem ersten Kaffee wirkt Wunder."),
        DailyCard(title: "Impuls des Tages", text: "Vergleich dich mit dir von gestern, nicht mit allen anderen."),
        DailyCard(title: "Tipp des Tages", text: "Zehn Minuten aufräumen heute, ein ruhigerer Kopf morgen."),
        DailyCard(title: "Impuls des Tages", text: "Neugier ist ein Superkraft — folg ihr einfach mal."),
        DailyCard(title: "Tipp des Tages", text: "Vor dem Schlafen: Bildschirm aus, Gedanken auf Papier."),
        DailyCard(title: "Impuls des Tages", text: "Der beste Zeitpunkt war gestern. Der zweitbeste ist jetzt."),
        DailyCard(title: "Tipp des Tages", text: "Sag einmal öfter Nein zu Dingen, die dir Energie rauben."),
        DailyCard(title: "Impuls des Tages", text: "Auch Pausen sind Fortschritt — nur in die andere Richtung."),
        DailyCard(title: "Tipp des Tages", text: "Lieblingssong laut aufdrehen zählt als Mini-Urlaub."),
        DailyCard(title: "Impuls des Tages", text: "Was du heute säst, zockst du morgen in Leonida. Fast."),
        DailyCard(title: "Tipp des Tages", text: "Schreib eine Sache auf, die heute gut war. Jeden Tag eine."),
    ]

    static func today(for date: Date = Date()) -> DailyCard {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        return all[day % all.count]
    }
}
