import Foundation

// MARK: - Skip-kompatible Random/Math-Helfer
//
// Skip/Kotlin kann weder `Int.random(in:using:)`/`Bool.random(using:)`/
// `Collection.randomElement(using:)` mit einem generischen `inout R:
// RandomNumberGenerator` aufrufen, noch `Double.squareRoot()`. Diese
// Helfer kapseln das: Auf Apple/native (`#else`) rufen sie EXAKT die
// Original-Stdlib-API auf → iOS-Verhalten bleibt byte-identisch. Auf
// Skip/Android (`#if SKIP`) leiten sie das Ergebnis direkt aus
// `rng.next()` ab. Die Server-/iOS-Sequenz wird dadurch auf Android nicht
// bit-genau repliziert — Android-Solo ist von iOS/Backend unabhängig,
// daher genügt geräte-interne Selbst-Konsistenz (gleiche Begründung wie
// beim bereits bestehenden `SeededRandom.double()`-Split).

#if SKIP
/// Skip-only: liefert eine gleichverteilte Ganzzahl in `0..<bound`.
/// Rechnet ausschliesslich über `Double(ULong)` + Double-Arithmetik +
/// `Int(Double)` — Skip/Kotlin hat keinen verlässlichen ULong-`%`/
/// ULong→Int-Pfad (`%` ist dort optional, `Int(ULong)` mappt auf den
/// String-Ctor). 2^64 als Normierungs-Konstante. `bound` ist im Match-
/// Engine immer klein (< 2^31), die Double-Auflösung ist somit unkritisch.
func engineNextBounded<R: RandomNumberGenerator>(_ bound: Int, _ rng: inout R) -> Int {
    if bound <= 1 { return 0 }
    // `>> 11` reduziert auf 53 Bits, damit `Double(ULong)` in Skip nicht
    // optional/failable wird (volle 64 Bit liefern dort `Double?`). Identische
    // Normierung wie `SeededRandom.double()`.
    let frac = Double(rng.next() >> 11) * (1.0 / 9007199254740992.0)   // [0,1)
    let scaled = Int(frac * Double(bound))
    return scaled >= bound ? bound - 1 : scaled
}
#endif

func engineRandomInt<R: RandomNumberGenerator>(_ range: Range<Int>, _ rng: inout R) -> Int {
    #if SKIP
    return range.lowerBound + engineNextBounded(range.upperBound - range.lowerBound, &rng)
    #else
    return Int.random(in: range, using: &rng)
    #endif
}

/// Inklusiver Bereich `lower...upper` über explizite Int-Grenzen — Skips
/// `ClosedRange<Int>` lässt sich im generischen Kontext nicht zuverlässig
/// auslesen, deshalb übergeben die Aufrufer die Grenzen direkt.
func engineRandomIntClosed<R: RandomNumberGenerator>(_ lower: Int, _ upper: Int, _ rng: inout R) -> Int {
    #if SKIP
    return lower + engineNextBounded(upper - lower + 1, &rng)
    #else
    return Int.random(in: lower...upper, using: &rng)
    #endif
}

func engineRandomBool<R: RandomNumberGenerator>(_ rng: inout R) -> Bool {
    #if SKIP
    return engineNextBounded(2, &rng) == 1
    #else
    return Bool.random(using: &rng)
    #endif
}

/// Wählt einen zufälligen Index in `0..<count` oder `nil` bei leerem Bereich.
func engineRandomIndex<R: RandomNumberGenerator>(_ count: Int, _ rng: inout R) -> Int? {
    guard count > 0 else { return nil }
    #if SKIP
    return engineNextBounded(count, &rng)
    #else
    return (0..<count).randomElement(using: &rng)
    #endif
}

/// Fisher-Yates-Shuffle über `rng`. Auf Apple/native exakt das Stdlib-
/// `shuffled(using:)`; auf Skip eine eigene Fisher-Yates-Implementierung
/// (Stdlib-`shuffled(using:)` mit generischem RNG ist dort nicht verfügbar).
func engineShuffled<E, R: RandomNumberGenerator>(_ array: [E], _ rng: inout R) -> [E] {
    #if SKIP
    var result = array
    var i = result.count - 1
    while i > 0 {
        let j = engineNextBounded(i + 1, &rng)
        let tmp = result[i]
        result[i] = result[j]
        result[j] = tmp
        i -= 1
    }
    return result
    #else
    return array.shuffled(using: &rng)
    #endif
}

func engineSqrt(_ x: Double) -> Double {
    #if SKIP
    // `Double.squareRoot()` ist in Skip nicht verfügbar; `Foundation.sqrt`
    // (→ kotlin.math.sqrt) liefert denselben IEEE-754-Wert.
    return sqrt(x)
    #else
    return x.squareRoot()
    #endif
}

/// Server-seitige Match-Engine — Port der iOS-`MatchEngine` (Tribute-
/// Edition Build 400), die wiederum 1:1 aus KICKER.BAS portiert ist.
///
/// **Unterschied zum iOS-Port:**
/// - Alle Random-Aufrufe gehen über einen `inout RandomNumberGenerator`
///   per Generic-Parameter. Damit ist jeder Match-Tag deterministisch
///   reproduzierbar (Server-Anforderung: Replay, Crash-Recovery).
/// - Drift-Korrekturen gegenüber dem iOS-Port (Memory-Vorgabe „alle Drifts
///   beim Server-Port zum Original-Verhalten zurück"):
///   - **D-3:** Keine Edition-/Schwierigkeits-Skalierung von
///     `injuryProbabilityPercent`. Default 15 (= Original
///     KICKER.BAS:3933-3947). Aufrufer können beim Bedarf überschreiben.
///   - **D-4:** Karten-Random nutzt `0..<N` (Original-GFA-Semantik
///     `Random(N)` = 0..N-1), nicht `1...N` wie iOS.
///   - **D-5:** `pickGoalScorer` liefert Spieler-ID + -Name, nicht nur
///     Name (verhindert Name-Kollisions-Bug bei gleichnamigen Spielern).
/// - **D-6:** Original-Tippfehler `bA + bA/4` im Gast-Tor-Wurf wird 1:1
///   beibehalten (Frank-Regel: nicht „besser machen", siehe Memory
///   feedback_original_source_fidelity).
public enum MatchEngine {

    // MARK: - TeamSkills (Errechne_aufstellung — KICKER.BAS:7440-7468)

    public struct TeamSkills: Equatable {
        public var moral:         Int   // Sp.info(N, 6)
        public var zusammenspiel: Int   // Sp.info(N, 7)
        public var kondition:     Int   // Sp.info(N, 8) — Σ energy / 2.2
        public var torwart:       Int   // Sp.info(N, 9) — Suche_awert(0)
        public var defense:       Int   // Sp.info(N,10) — Suche_awert(1) / 3.34
        public var midfield:      Int   // Sp.info(N,11) — Suche_awert(2) / 3.34
        public var attack:        Int   // Sp.info(N,12) — Suche_awert(3) / 3.34

        public init(moral: Int, zusammenspiel: Int, kondition: Int, torwart: Int, defense: Int, midfield: Int, attack: Int) {
            self.moral = moral
            self.zusammenspiel = zusammenspiel
            self.kondition = kondition
            self.torwart = torwart
            self.defense = defense
            self.midfield = midfield
            self.attack = attack
        }

        /// Original clampt F=6..12 auf [1, 100] am Ende von Errechne_aufstellung.
        public mutating func clamp() {
            moral         = max(1, min(100, moral))
            zusammenspiel = max(1, min(100, zusammenspiel))
            kondition     = max(1, min(100, kondition))
            torwart       = max(1, min(100, torwart))
            defense       = max(1, min(100, defense))
            midfield      = max(1, min(100, midfield))
            attack        = max(1, min(100, attack))
        }
    }

    // MARK: - HalfResult (Output von Ermittle_ergebnis)

    public struct HalfResult: Equatable {
        public var homeGoals: Int = 0
        public var awayGoals: Int = 0
        public var homeAttempts: Int = 0
        public var awayAttempts: Int = 0
        public var goalMinutes: [GoalMinute] = []

        public init() {}

        public struct GoalMinute: Equatable {
            public let minute: Int
            public let isHome: Bool
            public init(minute: Int, isHome: Bool) {
                self.minute = minute
                self.isHome = isHome
            }
        }
    }

    // MARK: - aggregateTeamSkills (KICKER.BAS:7440 + 7111 + 7675-7676)

    /// Pure — keine Randomness, keine Side-Effects.
    /// Lineup-Semantik wie im iOS-Port:
    /// - `lineupIDs == nil` → CPU-Auto-Pick (bester Torwart + Top-10 Feldspieler)
    /// - `lineupIDs == .nonEmpty` → exakt diese, gefiltert auf isAvailable
    /// - `lineupIDs == []` → leere Aufstellung, Skills fallen auf 1
    ///   (entspricht „Manager hat nie aufgestellt", bewusst)
    public static func aggregateTeamSkills(
        players: [EnginePlayer],
        lineupIDs: Set<UUID>? = nil,
        teamMoral: Int = 50,
        teamZusammenspiel: Int = 50
    ) -> TeamSkills {
        let lineup: [EnginePlayer]
        if let ids = lineupIDs {
            lineup = players.filter { ids.contains($0.id) && $0.isAvailable }
        } else {
            lineup = pickLineup(from: players, lineupIDs: nil)
        }

        // Sp.info(N, 8) = Σ energy / 2.2 über Lineup
        let kondition = Int(Double(lineup.reduce(0) { $0 + $1.energy }) / 2.2)

        // Suche_awert(pos) = (Σ über Lineup an dieser Position von
        //   (primarySkill+1)*4 + energy + form) * 1.25
        // Skills werden truncated als Int verwendet — Original `Pl.info(N,1)`
        // ist die Int-Sicht der Float-Skills (siehe primarySkill).
        func sucheAwert(_ pos: EnginePosition) -> Int {
            let sum = lineup
                .filter { $0.position == pos }
                .reduce(0) { acc, p in
                    let primary: Int
                    switch pos {
                    case .goalkeeper: primary = Int(p.skillGoalkeeping)
                    case .defender:   primary = Int(p.skillDefense)
                    case .midfielder: primary = Int(p.skillMidfield)
                    case .forward:    primary = Int(p.skillAttack)
                    }
                    return acc + (primary + 1) * 4 + p.energy + p.form
                }
            return Int(Double(sum) * 1.25)
        }

        let torwart  = sucheAwert(.goalkeeper)
        let defense  = Int(Double(sucheAwert(.defender))   / 3.34)
        let midfield = Int(Double(sucheAwert(.midfielder)) / 3.34)
        let attack   = Int(Double(sucheAwert(.forward))    / 3.34)

        var result = TeamSkills(
            moral: max(1, min(100, teamMoral)),
            zusammenspiel: max(1, min(100, teamZusammenspiel)),
            kondition: kondition,
            torwart: torwart,
            defense: defense,
            midfield: midfield,
            attack: attack
        )
        result.clamp()
        return result
    }

    /// Aufstellung auswählen. Bei `lineupIDs == nil` Auto-Pick (CPU).
    /// Original: `Auto_aufstellung` für CPU, `Pl.info(p,15)=1`-Flag für Manager.
    public static func pickLineup(
        from players: [EnginePlayer],
        lineupIDs: Set<UUID>?
    ) -> [EnginePlayer] {
        let available = players.filter { $0.isAvailable }

        // Frank-Bug 2026-05-23: vorher fiel der Fallback auf Auto-Top-11
        // aus dem GESAMTEN Kader, sobald `chosen` leer war (z.B. weil alle
        // aufgestellten Spieler unavailable wurden). Folge: Bank-Spieler
        // konnten Tore schießen, die nie auf dem Feld standen.
        // Jetzt strikt: wenn der Caller ein Lineup übergibt, gilt
        // ausschließlich dieses Lineup — auch wenn dadurch <11 Spieler
        // bleiben. Forfeit (<7 verfügbar) ist Aufgabe des Callers.
        if let ids = lineupIDs {
            return available.filter { ids.contains($0.id) }
        }

        // Kein explizites Lineup übergeben → Auto-Top-11 als
        // Default-Aufstellung (Solo-Fallback bei fehlender Aufstellung).
        var picked: [EnginePlayer] = []
        if let bestGK = available
            .filter({ $0.position == EnginePosition.goalkeeper })
            .sorted(by: { $0.skillGoalkeeping > $1.skillGoalkeeping })
            .first
        {
            picked.append(bestGK)
        }
        let remaining = available
            .filter { $0.position != EnginePosition.goalkeeper }
            .sorted { $0.overallSkill > $1.overallSkill }
            .prefix(11 - picked.count)
        picked.append(contentsOf: remaining)
        return picked
    }

    // MARK: - applyTactic (KICKER.BAS:1994-2003)

    /// Pure. Tactic 0..4 (Default 2 = kontrolliert), intern + 1 → 1..5
    /// um die GFA-Semantik mit Default 3 zu treffen.
    public static func applyTactic(_ skills: inout TeamSkills, tactic: Int) {
        let t = tactic + 1

        if t < 3 {
            skills.defense  += skills.defense  / (2 + t)
            skills.attack   -= skills.attack   / (2 + t)
            skills.midfield -= skills.midfield / (2 + t)
        }
        if t > 3 {
            skills.defense  -= skills.defense  / (8 - t)
            skills.attack   += skills.attack   / (8 - t)
            skills.midfield += skills.midfield / (9 - t)
        }

        skills.defense  = max(1, min(100, skills.defense))
        skills.midfield = max(1, min(100, skills.midfield))
        skills.attack   = max(1, min(100, skills.attack))
    }

    // MARK: - ermittleErgebnis (KICKER.BAS:8000-8037)

    /// Kern-Simulationsschleife. `ticks` = 32 für 90', = 12 für ET-Hälfte.
    /// `startMinute` versetzt die Tor-Minuten (0=H1, 45=H2, 90=ET1, 105=ET2).
    /// `isUefaAway` schaltet den Heimvorteil von +75 auf 0 ab.
    public static func ermittleErgebnis<R: RandomNumberGenerator>(
        _ a: TeamSkills,
        _ b: TeamSkills,
        ticks: Int,
        startMinute: Int,
        isUefaAway: Bool = false,
        using rng: inout R
    ) -> HalfResult {
        var result = HalfResult()

        // Possession-Würfel (BAS:8003-8005). moral*1.5 + zusammenspiel +
        // kondition + midfield*7, +75 Heimvorteil bei A.
        let heimvorteil = isUefaAway ? 0 : 75
        var antA = a.moral * 3 / 2 + a.zusammenspiel + a.kondition + a.midfield * 7 + heimvorteil
        var antB = b.moral * 3 / 2 + b.zusammenspiel + b.kondition + b.midfield * 7
        antA = max(1, antA)
        antB = max(1, antB)
        let antI = antA + antB

        // „Normung auf 50" (BAS:8006-8009). Halbierung NUR auf den lokalen
        // Skill-Vars für die Tor-Würfel — Possession-Werte oben bleiben.
        let aT  = a.torwart  / 2
        let aV  = a.defense  / 2
        let aM  = a.midfield / 2
        let aA  = a.attack   / 2
        let bT  = b.torwart  / 2
        let bV  = b.defense  / 2
        let bM  = b.midfield / 2
        let bA  = b.attack   / 2

        // Tor-Minuten-Spreading (Tribute-Erweiterung — Original kennt nur Tor.A/Tor.B)
        let minutesPerHalf = ticks <= 12 ? 15 : 45
        let minuteStep = Double(minutesPerHalf) / Double(ticks)

        // Tick-Loop (BAS:8010-8036)
        for i in 0..<ticks {
            let angriff = engineRandomInt(0..<antI, &rng)
            let attackerIsHome = angriff < antA
            let minute = startMinute + Int(Double(i) * minuteStep) + 1

            if attackerIsHome {
                result.homeAttempts += 1
                var tor = aA + aM / 4 - bV - bM / 4 + 62
                if tor > engineRandomInt(0..<300, &rng) {
                    tor = aA + aM / 4 - bT * 3 / 2 + 75
                    if tor > engineRandomInt(0..<200, &rng) {
                        result.homeGoals += 1
                        result.goalMinutes.append(HalfResult.GoalMinute(minute: minute, isHome: true))
                    }
                }
            } else {
                result.awayAttempts += 1
                var tor = bA + bM / 4 - aV - bM / 4 + 62
                if tor > engineRandomInt(0..<300, &rng) {
                    // D-6: Original-Tippfehler `B%(6)/4` (zweimal bA/4) statt
                    // `B%(5)/4` (mid). 1:1 übernommen — Frank-Regel.
                    tor = bA + bA / 4 - aT * 3 / 2 + 75
                    if tor > engineRandomInt(0..<200, &rng) {
                        result.awayGoals += 1
                        result.goalMinutes.append(HalfResult.GoalMinute(minute: minute, isHome: false))
                    }
                }
            }
        }

        return result
    }

    // MARK: - simulate (Public Entry Point)

    /// Kompletter Match-Lauf inkl. Karten + optionaler Verletzung + ET.
    /// Pure relativ zur Eingabe (keine Game-Mutation) — alle Side-Effects
    /// landen im Caller (z.B. SeasonEngine.playLeagueMatchDay, kommt
    /// in einer späteren Iteration).
    public static func simulate<R: RandomNumberGenerator>(
        homeTeam: EngineTeam,
        awayTeam: EngineTeam,
        homePlayers: [EnginePlayer],
        awayPlayers: [EnginePlayer],
        matchDay: Int,
        leagueIndex: Int,
        homeLineup: Set<UUID>? = nil,
        awayLineup: Set<UUID>? = nil,
        homeTactic: Int = 2,
        awayTactic: Int = 2,
        homeSkillsOverride: TeamSkills? = nil,
        awaySkillsOverride: TeamSkills? = nil,
        extraTimeOnDraw: Bool = false,
        injuryProbabilityPercent: Int = 15,
        using rng: inout R
    ) -> EngineMatchResult {
        var result = EngineMatchResult(
            homeTeamID: homeTeam.id,
            awayTeamID: awayTeam.id,
            matchDay: matchDay,
            leagueIndex: leagueIndex
        )

        var homeSkills: TeamSkills = homeSkillsOverride ?? aggregateTeamSkills(
            players: homePlayers,
            lineupIDs: homeLineup,
            teamMoral: homeTeam.moral ?? 50,
            teamZusammenspiel: homeTeam.zusammenspiel ?? 50
        )
        var awaySkills: TeamSkills = awaySkillsOverride ?? aggregateTeamSkills(
            players: awayPlayers,
            lineupIDs: awayLineup,
            teamMoral: awayTeam.moral ?? 50,
            teamZusammenspiel: awayTeam.zusammenspiel ?? 50
        )
        applyTactic(&homeSkills, tactic: homeTactic)
        applyTactic(&awaySkills, tactic: awayTactic)

        // 32 Ticks = 90 Minuten (BAS: @Ermittle_ergebnis(32))
        let outcome = ermittleErgebnis(
            homeSkills, awaySkills,
            ticks: 32, startMinute: 0,
            using: &rng
        )
        result.homeGoals = outcome.homeGoals
        result.awayGoals = outcome.awayGoals

        // Aufgestellte ermitteln — `pickGoalScorer` und der Karten-Pool
        // operieren AUF DER AUFSTELLUNG (KICKER.BAS:9438 `Pl.info(A,15)=1`).
        // Frank-Bug 2026-05-09: vorher reichten wir `homePlayers/awayPlayers`
        // (Gesamtkader) ins `pickGoalScorer`, deshalb konnten Reserve-Spieler
        // Tore schießen, die gar nicht im Lineup standen.
        let homeLineupPlayers = pickLineup(from: homePlayers, lineupIDs: homeLineup)
        let awayLineupPlayers = pickLineup(from: awayPlayers, lineupIDs: awayLineup)

        // Schützen aus der Aufstellung wählen (Original-Gewicht
        // siehe `pickGoalScorer`).
        var homeTally = 0
        var awayTally = 0
        for gm in outcome.goalMinutes.sorted(by: { $0.minute < $1.minute }) {
            if gm.isHome { homeTally += 1 } else { awayTally += 1 }
            let scorer = gm.isHome
                ? pickGoalScorer(from: homeLineupPlayers, using: &rng)
                : pickGoalScorer(from: awayLineupPlayers, using: &rng)
            result.goalScorers.append(EngineGoalEvent(
                scorerID: scorer.id,
                scorerName: scorer.name,
                minute: gm.minute,
                scoreAtTime: "\(homeTally):\(awayTally)",
                isHome: gm.isHome
            ))
        }

        // Karten (KICKER.BAS:2639/2705) — nur Feldspieler aus dem Lineup
        let homeOnField = homeLineupPlayers.filter { $0.position != EnginePosition.goalkeeper }
        let awayOnField = awayLineupPlayers.filter { $0.position != EnginePosition.goalkeeper }

        // D-4: 0..<N Range (Original GFA `Random(N)` = 0..N-1).
        // Gelb total: A% = Random(40)^(1/3) + 2 - Sqr(Random(9))
        let totalYellow = max(0,
            Int(pow(Double(engineRandomInt(0..<40, &rng)), 1.0 / 3.0))
            + 2
            - Int(engineSqrt(Double(engineRandomInt(0..<9, &rng))))
        )
        let yellowHome = totalYellow > 0 ? engineRandomIntClosed(0, totalYellow, &rng) : 0
        let yellowAway = totalYellow - yellowHome

        // Rot total: A% = 3 - Sqr(Sqr(Random(230)+1))
        let totalRed = max(0,
            3 - Int(engineSqrt(engineSqrt(Double(engineRandomInt(0..<230, &rng) + 1))))
        )
        let redHome = totalRed > 0 ? engineRandomIntClosed(0, totalRed, &rng) : 0
        let redAway = totalRed - redHome

        // Globaler Dedupe über alle vier Vergaben (BAS:2650-2657 — kein
        // Spieler bekommt zwei Karten im selben Spiel)
        var bookedIDs: Set<UUID> = []
        appendUniqueCards(count: yellowHome, from: homeOnField,
                          into: &result.yellowCards, bookedIDs: &bookedIDs,
                          isRed: false, teamName: homeTeam.name, using: &rng)
        appendUniqueCards(count: yellowAway, from: awayOnField,
                          into: &result.yellowCards, bookedIDs: &bookedIDs,
                          isRed: false, teamName: awayTeam.name, using: &rng)
        appendUniqueCards(count: redHome, from: homeOnField,
                          into: &result.redCards, bookedIDs: &bookedIDs,
                          isRed: true, teamName: homeTeam.name, using: &rng)
        appendUniqueCards(count: redAway, from: awayOnField,
                          into: &result.redCards, bookedIDs: &bookedIDs,
                          isRed: true, teamName: awayTeam.name, using: &rng)

        // Verletzung (KICKER.BAS:3933-3947). Default 15% pro Match
        // (= Original-Wert, keine Edition-Skalierung — D-3-Fix).
        if engineRandomInt(0..<100, &rng) < injuryProbabilityPercent {
            let pickHome = engineRandomBool(&rng)
            let pool: [EnginePlayer] = pickHome ? homeOnField : awayOnField
            if !pool.isEmpty,
               let victimIdx = engineRandomIndex(pool.count, &rng)
            {
                let victim = pool[victimIdx]
                // Pausendauer (BAS:3944): Random(3)+6-Sqr(Random(25))
                let raw = engineRandomInt(0..<3, &rng) + 6
                    - Int(engineSqrt(Double(engineRandomInt(0..<25, &rng))))
                let weeks = max(1, min(8, raw))
                result.injury = EngineInjuryEvent(
                    playerID: victim.id,
                    playerName: victim.name,
                    isHome: pickHome,
                    weeks: weeks,
                    minute: engineRandomIntClosed(5, 85, &rng)
                )
            }
        }

        // Verlängerung bei Pokal-Match mit Draw (KICKER.BAS:3079-3095).
        // ET-Tore landen mit Minuten 90+ in goalScorers.
        if extraTimeOnDraw && result.homeGoals == result.awayGoals {
            let et = ermittleErgebnis(
                homeSkills, awaySkills,
                ticks: 12, startMinute: 90,
                using: &rng
            )
            for gm in et.goalMinutes.sorted(by: { $0.minute < $1.minute }) {
                if gm.isHome { homeTally += 1 } else { awayTally += 1 }
                let scorer = gm.isHome
                    ? pickGoalScorer(from: homeLineupPlayers, using: &rng)
                    : pickGoalScorer(from: awayLineupPlayers, using: &rng)
                result.goalScorers.append(EngineGoalEvent(
                    scorerID: scorer.id,
                    scorerName: scorer.name,
                    minute: gm.minute,
                    scoreAtTime: "\(homeTally):\(awayTally)",
                    isHome: gm.isHome
                ))
            }
            result.homeGoals = homeTally
            result.awayGoals = awayTally
        }

        return result
    }

    // MARK: - Helpers

    /// `count` distinkte Spieler ziehen, jeweils eine Karte vergeben.
    /// `bookedIDs` wird über alle Vergaben eines Matches geteilt.
    private static func appendUniqueCards<R: RandomNumberGenerator>(
        count: Int,
        from candidates: [EnginePlayer],
        into list: inout [EngineCardEvent],
        bookedIDs: inout Set<UUID>,
        isRed: Bool,
        teamName: String,
        using rng: inout R
    ) {
        guard count > 0 else { return }
        let pool = candidates.filter { !bookedIDs.contains($0.id) }
        guard !pool.isEmpty else { return }
        let picks = engineShuffled(pool, &rng).prefix(count)
        for p in picks {
            list.append(EngineCardEvent(
                playerID: p.id,
                playerName: p.name,
                isRed: isRed,
                teamName: teamName,
                minute: engineRandomIntClosed(5, 90, &rng)
            ))
            bookedIDs.insert(p.id)
        }
    }

    /// Torschütze auswählen — Port von `Torschuetze_bestimmen`
    /// (KICKER.BAS:9425-9469). Drei wichtige Original-Eigenschaften:
    ///
    /// 1. **Pool = nur Aufgestellte**, nicht der Gesamtkader.
    ///    Original-Filter `Pl.info(A%,15)=1` (Aufstellungsmarker).
    ///    Frank-Bug 2026-05-09: bisher nahmen wir `players` (Kader),
    ///    deshalb konnten Reserve-Spieler Tore schießen.
    ///
    /// 2. **Gewicht = (mid/5 + attack) / 2** — original Zeile 9456:
    ///    `B%=(Pl.info%(A%,19)/5+Pl.info%(A%,20))/2`. Mittelfeldspieler
    ///    bekommen so einen kleinen Bonus über ihren Mittelfeld-Skill;
    ///    Verteidiger schießen praktisch nie (kleine attack + kleine mid),
    ///    Torwart hat alle Skill-Felder ≈ 0 → wird natürlich aussortiert.
    ///
    /// 3. **Rejection-Sampling**: Spieler ziehen, B% ≥ Random(0..7) → Treffer,
    ///    sonst weiter würfeln (Original Zeilen 9433-9460). Wir limitieren
    ///    auf `maxAttempts`, damit ein extrem schwacher Pool nicht endlos
    ///    würfelt — Fallback ist dann der Spieler mit höchstem Gewicht.
    ///
    /// Fallback bei komplett leerem Pool: synthetisches „Unbekannt"-Sentinel
    /// (verhindert Crash, sollte in der Praxis nie erreicht werden, weil
    /// Tore nur entstehen wenn 11 Spieler aufgestellt sind).
    public static func pickGoalScorer<R: RandomNumberGenerator>(
        from lineup: [EnginePlayer],
        using rng: inout R
    ) -> (id: UUID, name: String) {
        // Aufgestellte ohne Torwart — Original-Algorithmus würde den Torwart
        // theoretisch zulassen (B%-Würfel filtert ihn über Skill ≈ 0 raus),
        // aber expliziter Position-Filter ist defensiver und auch gegenüber
        // KDT-Daten mit unerwarteten Skill-Werten robust.
        let candidates = lineup.filter { $0.isAvailable && $0.position != EnginePosition.goalkeeper }
        guard !candidates.isEmpty else {
            return (id: UUID(), name: "Unbekannt")
        }

        // Original `B%=(Pl.info(A,19)/5+Pl.info(A,20))/2` — Int-Division
        // wie in GFA. `+1` damit auch ein Spieler mit 0/0 noch ziehen kann
        // (sonst Endlosschleife im Reject-Sampling bei sehr schwachem Pool).
        func weight(_ p: EnginePlayer) -> Int {
            (Int(p.skillMidfield) / 5 + Int(p.skillAttack)) / 2
        }

        // Rejection-Sampling — Original-Pfad. `Random(8)` = 0..7 (GFA-Semantik
        // wie D-4-Drift). Wir cappen auf 32 Versuche; danach greift der
        // Fallback (max-Gewicht), damit bei pathologischen Lineups kein
        // Live-Lock entsteht.
        for _ in 0..<32 {
            let idx = engineRandomInt(0..<candidates.count, &rng)
            let p = candidates[idx]
            let b = weight(p)
            if b >= engineRandomInt(0..<8, &rng) {
                return (id: p.id, name: p.name)
            }
        }
        // Fallback: stärksten Schützen wählen (deterministisch, nicht
        // random — sonst rührt der Fallback-Pfad das RNG-State noch weiter
        // auf und bricht den Replay-Determinismus).
        let best = candidates.max(by: { weight($0) < weight($1) }) ?? candidates[0]
        return (id: best.id, name: best.name)
    }

    // MARK: - Difficulty-Skalierung (Tribute-Edition)

    /// Verletzungswahrscheinlichkeit pro Match in Prozent.
    /// Anfänger 3 % → Experte 22 %. Default-Stufe 2 = 11 %.
    public static func injuryProbability(for difficulty: Int) -> Int {
        switch max(0, min(4, difficulty)) {
        case 0: return 3
        case 1: return 7
        case 2: return 11
        case 3: return 15
        case 4: return 22
        default: return 15
        }
    }

    /// Energie-Drain-Faktor pro Spieltag. Multipliziert die Original-
    /// Drain-Formel KICKER.BAS:4006 — bei Stufe 2 unverändert (1.0).
    public static func energyDrainFactor(for difficulty: Int) -> Double {
        switch max(0, min(4, difficulty)) {
        case 0: return 0.5
        case 1: return 0.7
        case 2: return 1.0
        case 3: return 1.2
        case 4: return 1.5
        default: return 1.0
        }
    }
}
