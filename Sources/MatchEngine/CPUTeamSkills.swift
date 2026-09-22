import Foundation

// CPU-Gegner-Skills — die EINE Quelle für Solo und Online.
//
// Port von KICKER.BAS:1536-1560. Ein Verein ohne eigenen Kader (im Original
// jeder CPU-Gegner, bei uns vor allem die internationalen Europapokal-Vereine)
// hat keine Einzelspieler, aus denen sich Mannschaftswerte aggregieren
// liessen. Das Original würfelt sie stattdessen aus `Team.skill%` und der
// Tabellenposition zusammen.
//
// Warum hier und nicht in `kicker-game-core`: Solo rechnete die Formel bisher
// in `CupEngine.cpuTeamSkills`, das Backend gar nicht — es kennt game-core
// nicht, sondern nur dieses Paket. Ohne gemeinsame Quelle hätte der
// Europapokal online andere Ergebnisse geliefert als Solo, und genau das
// verbietet Regel A („das gilt genauso online"). Deshalb liegt die Formel
// jetzt in der MatchEngine, die alle drei Seiten teilen — iOS, Android und
// das Backend.
//
// Der Zufall kommt als `inout RandomNumberGenerator` herein: Solo gibt den
// System-Zufall, das Backend seinen `SeededRandom`, damit ein Spieltag
// reproduzierbar bleibt.
extension MatchEngine {

    /// Match-Kontext der Formel — Liga rechnet die Moral anders als die Pokale.
    public enum CPUSkillContext {
        case liga
        case dfb
        case uefa
    }

    /// CPU-Gegner-Skills gemäss KICKER.BAS:1536-1560.
    ///
    ///   Pkt           = strength · 4/7 − 8
    ///   Moral         = 53 + (18−Pos)·1.5 + Random(Runde·4) + Runde·6   (Pokal)
    ///                 | (10 + (18−Pos)·4 + Random((16−Pos)·2)) · 1.4    (Liga)
    ///   Zusammenspiel = (25 + (18−Pos)·2 + Random((16−Pos)·3)) · 1.4
    ///   Kondition     = 60 + Random(80)
    ///   T,V,M,A       = 1 (Start)
    ///   Pkt/6 × Punkte á 6 auf zufällige T..A verteilen (je bis < 160)
    ///   alle 7 Werte / 1.6 (Normalisierung)
    ///
    /// - Parameters:
    ///   - strength: `Team.skill%` des Vereins (100…950).
    ///   - position: Tabellenplatz 1…18. Wer keinen hat — internationale
    ///     Vereine, Aufsteiger ohne Spiele —, bekommt 9 (Mittelfeld).
    ///   - round: Pokalrunde 1…6; verstärkt die Moral in DFB/UEFA.
    public static func cpuTeamSkills<R: RandomNumberGenerator>(
        strength: Int,
        position: Int,
        context: CPUSkillContext,
        round: Int,
        using rng: inout R
    ) -> TeamSkills {
        // Rohwerte in die 7 Gegn-Felder: 0=Moral, 1=Zusammenspiel,
        // 2=Kondition, 3=Torwart, 4=V, 5=M, 6=A.
        // ACHTUNG, Branch-Unterschied: dieser Zweig (`backend-engine-fix`)
        // ist die Skip-freie Linux-Fassung der Engine und hat die
        // `engineRandom*`-Helfer NICHT — hier steht `Int.random(in:using:)`
        // direkt. Auf `main` benutzt dieselbe Formel die Helfer, weil sie
        // dort nach Kotlin transpiliert wird. Wer die Formel aendert, muss
        // BEIDE Zweige anfassen.
        var g: [Int] = [1, 1, 1, 1, 1, 1, 1]

        let posF = max(0, 18 - position)                  // 0..17
        let pos16 = max(0, 16 - position)                 // 0..15
        let runde = max(1, round)

        switch context {
        case .dfb, .uefa:
            g[0] = 53 + Int(Double(posF) * 1.5)
                 + Int.random(in: 0..<max(1, runde * 4), using: &rng)
                 + runde * 6
        case .liga:
            let raw = 10 + posF * 4 + Int.random(in: 0..<max(1, pos16 * 2), using: &rng)
            g[0] = Int(Double(raw) * 1.4)
        }

        let zrRaw = 25 + posF * 2 + Int.random(in: 0..<max(1, pos16 * 3), using: &rng)
        g[1] = Int(Double(zrRaw) * 1.4)

        g[2] = 60 + Int.random(in: 0..<80, using: &rng)

        var pkt = strength * 4 / 7 - 8
        if pkt < 0 { pkt = 0 }
        let iterations = pkt / 6
        for _ in 0..<iterations {
            // Einen Slot 3..6 suchen, der noch unter 160 liegt.
            var tries = 0
            while tries < 20 {
                let a = Int.random(in: 3...6, using: &rng)
                if g[a] < 160 {
                    g[a] += 6
                    break
                }
                tries += 1
            }
        }

        // Normalisierung /1.6.
        for i in 0..<7 {
            g[i] = Int(Double(g[i]) / 1.6)
        }

        var s = TeamSkills(
            moral: g[0],
            zusammenspiel: g[1],
            kondition: g[2],
            torwart: g[3],
            defense: g[4],
            midfield: g[5],
            attack: g[6]
        )
        s.clamp()
        return s
    }

    /// Skills eines Vereins, über den wir gar nichts wissen. Bewusst
    /// defensiv und ohne Zufall — der Pfad soll nie „stark" wirken.
    public static func unknownTeamSkills() -> TeamSkills {
        var s = TeamSkills(
            moral: 50, zusammenspiel: 50, kondition: 50,
            torwart: 30, defense: 30, midfield: 30, attack: 30
        )
        s.clamp()
        return s
    }
}
