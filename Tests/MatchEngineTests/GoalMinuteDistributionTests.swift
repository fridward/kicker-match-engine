import XCTest
@testable import MatchEngine

/// Regressionswaechter fuer die Torminuten-Verteilung.
///
/// Frank-Bug 2026-09-01: In der zweiten Halbzeit fiel NIE ein Tor. Ursache war
/// `minutesPerHalf = ticks <= 12 ? 15 : 45` — die 32 Ticks der regulaeren
/// Spielzeit decken 90 Minuten ab, wurden aber ueber 45 verteilt. Gemessen:
/// 4758 Tore in Halbzeit 1, 0 in Halbzeit 2, hoechste Minute 44.
final class GoalMinuteDistributionTests: XCTestCase {

    private var skills: MatchEngine.TeamSkills {
        MatchEngine.TeamSkills(moral: 50, zusammenspiel: 50, kondition: 50,
                               torwart: 40, defense: 45, midfield: 45, attack: 45)
    }

    /// Beide Halbzeiten muessen Tore sehen — und zwar ungefaehr gleich viele.
    func testGoalsFallInBothHalves() {
        var firstHalf = 0
        var secondHalf = 0
        var rng = SeededRandom(seed: 4711)
        for _ in 0..<2000 {
            let r = MatchEngine.ermittleErgebnis(skills, skills, ticks: 32,
                                                 startMinute: 0, using: &rng)
            for gm in r.goalMinutes {
                if gm.minute <= 45 { firstHalf += 1 } else { secondHalf += 1 }
            }
        }
        XCTAssertGreaterThan(secondHalf, 0, "in der zweiten Halbzeit muessen Tore fallen")
        // Gleichverteilte Ticks → beide Haelften im selben Bereich. Grosszuegige
        // Schranke (±25 %), der Test soll den Totalausfall fangen, nicht rauschen.
        let ratio = Double(secondHalf) / Double(max(1, firstHalf))
        XCTAssertGreaterThan(ratio, 0.75, "zweite Halbzeit deutlich unterrepraesentiert (\(firstHalf):\(secondHalf))")
        XCTAssertLessThan(ratio, 1.25, "erste Halbzeit deutlich unterrepraesentiert (\(firstHalf):\(secondHalf))")
    }

    /// Regulaere Spielzeit spannt ueber die vollen 90 Minuten.
    func testRegulationSpansFullMatch() {
        var maxMinute = 0
        var minMinute = 999
        var rng = SeededRandom(seed: 99)
        for _ in 0..<2000 {
            let r = MatchEngine.ermittleErgebnis(skills, skills, ticks: 32,
                                                 startMinute: 0, using: &rng)
            for gm in r.goalMinutes {
                maxMinute = max(maxMinute, gm.minute)
                minMinute = min(minMinute, gm.minute)
            }
        }
        XCTAssertEqual(minMinute, 1, "die 1. Minute muss erreichbar sein")
        XCTAssertEqual(maxMinute, 90, "die 90. Minute muss erreichbar sein")
    }

    /// Verlaengerung: 12 Ticks = 15 Minuten, ab Minute 90.
    func testExtraTimeStaysInItsWindow() {
        var rng = SeededRandom(seed: 7)
        var sawGoal = false
        for _ in 0..<2000 {
            let r = MatchEngine.ermittleErgebnis(skills, skills, ticks: 12,
                                                 startMinute: 90, using: &rng)
            for gm in r.goalMinutes {
                sawGoal = true
                XCTAssertGreaterThanOrEqual(gm.minute, 91)
                XCTAssertLessThanOrEqual(gm.minute, 105, "erste Verlaengerungs-Halbzeit endet mit 105")
            }
        }
        XCTAssertTrue(sawGoal, "auch in der Verlaengerung muessen Tore fallen koennen")
    }

    /// Nachspielzeit: Tore jenseits der 90. Minute behalten `minute == 90` und
    /// tragen den Zuschlag in `stoppage` — sonst kollidierten sie mit der
    /// Verlaengerung, die ab Minute 91 zaehlt (Frank-Wunsch 2026-09-01).
    func testStoppageTimeGoalsStayAtMinute90() {
        var rng = SeededRandom(seed: 2024)
        var sawStoppage = false
        var maxStoppage = 0
        for _ in 0..<3000 {
            let r = MatchEngine.ermittleErgebnis(skills, skills, ticks: 32,
                                                 startMinute: 0, using: &rng)
            for gm in r.goalMinutes {
                XCTAssertLessThanOrEqual(gm.minute, 90, "Minute darf 90 nie ueberschreiten")
                if gm.stoppage > 0 {
                    sawStoppage = true
                    maxStoppage = max(maxStoppage, gm.stoppage)
                    XCTAssertEqual(gm.minute, 90, "Nachspielzeit haengt an der 90.")
                }
            }
        }
        XCTAssertTrue(sawStoppage, "es muss Tore in der Nachspielzeit geben")
        XCTAssertLessThanOrEqual(maxStoppage, 5, "Nachspielzeit ist auf 5 Minuten gedeckelt")
    }

    /// Die Verlaengerung kennt KEINE Nachspielzeit — ihre Minuten zaehlen
    /// normal weiter (91..105).
    func testExtraTimeHasNoStoppage() {
        var rng = SeededRandom(seed: 31)
        for _ in 0..<1000 {
            let r = MatchEngine.ermittleErgebnis(skills, skills, ticks: 12,
                                                 startMinute: 90, using: &rng)
            for gm in r.goalMinutes {
                XCTAssertEqual(gm.stoppage, 0)
            }
        }
    }

    /// Nachspielzeit schafft KEINE zusaetzlichen Torchancen — die Tick-Zahl
    /// bleibt bei 32, sonst bekaeme jedes Spiel mehr Tore als im Original.
    func testStoppageDoesNotIncreaseChances() {
        var rng = SeededRandom(seed: 5)
        for _ in 0..<200 {
            let r = MatchEngine.ermittleErgebnis(skills, skills, ticks: 32,
                                                 startMinute: 0, using: &rng)
            XCTAssertEqual(r.homeAttempts + r.awayAttempts, 32)
        }
    }

    /// Zentraler Formatierer — EINE Quelle fuer alle Oberflaechen.
    func testMinuteLabelFormatting() {
        XCTAssertEqual(MatchEngine.minuteLabel(minute: 45, stoppage: nil), "45")
        XCTAssertEqual(MatchEngine.minuteLabel(minute: 45, stoppage: 0), "45")
        XCTAssertEqual(MatchEngine.minuteLabel(minute: 90, stoppage: 3), "90+3")
    }
}
