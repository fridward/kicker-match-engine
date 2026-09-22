// K.-o.-Spiel mit Verlaengerung und Elfmeterschiessen.
//
// Playoff-Serien (KICKER.BAS:3397-3511) und Relegationsspiele
// (KICKER.BAS:3514-3614) simuliert das Original abstrakt — ohne Aufstellung,
// Karten und Zuschauer. Solo tat das schon immer; seit 2026-09-22 liegt die
// Komposition hier, damit das Backend fuer die Online-Ligen exakt dieselbe
// Rechnung benutzt.
import XCTest
import Foundation
@testable import MatchEngine

final class KnockoutLegTests: XCTestCase {

    private func skills(_ v: Int) -> MatchEngine.TeamSkills {
        MatchEngine.TeamSkills(moral: v, zusammenspiel: v, kondition: v,
                               torwart: v, defense: v, midfield: v, attack: v)
    }

    /// Reproduzierbar: derselbe Seed, dasselbe Ergebnis. Ein Cheat-Sprung
    /// oder ein wiederholter Spieltag darf nicht wuerfeln.
    func test_gleicherSeed_gleichesErgebnis() {
        var r1 = SeededRandom(seed: 4711)
        var r2 = SeededRandom(seed: 4711)
        let a = MatchEngine.playKnockoutLeg(skills(60), skills(55), tieBreak: true, using: &r1)
        let b = MatchEngine.playKnockoutLeg(skills(60), skills(55), tieBreak: true, using: &r2)
        XCTAssertEqual(a.homeGoals, b.homeGoals)
        XCTAssertEqual(a.awayGoals, b.awayGoals)
        XCTAssertEqual(a.wentToPenalties, b.wentToPenalties)
    }

    /// Mit `tieBreak` steht IMMER ein Sieger fest — notfalls per Elfmeter.
    func test_mitTieBreak_niemalsUnentschieden() {
        for seed in 1...200 {
            var rng = SeededRandom(seed: UInt64(seed))
            let r = MatchEngine.playKnockoutLeg(skills(50), skills(50), tieBreak: true, using: &rng)
            XCTAssertNotEqual(r.homeGoals, r.awayGoals, "Seed \(seed) endete unentschieden")
        }
    }

    /// Ohne `tieBreak` bleibt ein Unentschieden stehen — Playoff-Spiel 1-4
    /// und Relegationsspiel 1-2 entscheidet erst die Serie bzw. das Aggregat.
    func test_ohneTieBreak_unentschiedenBleibtStehen() {
        var draws = 0
        for seed in 1...200 {
            var rng = SeededRandom(seed: UInt64(seed))
            let r = MatchEngine.playKnockoutLeg(skills(50), skills(50), tieBreak: false, using: &rng)
            XCTAssertFalse(r.wentToExtraTime)
            XCTAssertFalse(r.wentToPenalties)
            if r.homeGoals == r.awayGoals { draws += 1 }
        }
        XCTAssertGreaterThan(draws, 0, "bei 200 Spielen gleich starker Teams muss es Remis geben")
    }

    /// Der 90-Minuten-Stand bleibt erhalten, auch wenn Verlaengerung und
    /// Elfmeter den Endstand hochziehen.
    func test_regulaererStandBleibtLesbar() {
        for seed in 1...50 {
            var rng = SeededRandom(seed: UInt64(seed))
            let r = MatchEngine.playKnockoutLeg(skills(50), skills(50), tieBreak: true, using: &rng)
            XCTAssertGreaterThanOrEqual(r.homeGoals, r.regularHomeGoals)
            XCTAssertGreaterThanOrEqual(r.awayGoals, r.regularAwayGoals)
            if r.wentToExtraTime {
                XCTAssertEqual(r.regularHomeGoals, r.regularAwayGoals,
                               "Verlaengerung nur bei Gleichstand nach 90")
            }
        }
    }

    /// Die staerkere Mannschaft gewinnt ueber viele Spiele oefter — sonst
    /// waere die Aggregation wirkungslos.
    func test_staerkereMannschaftGewinntHaeufiger() {
        var starke = 0
        var schwache = 0
        for seed in 1...300 {
            var rng = SeededRandom(seed: UInt64(seed))
            let r = MatchEngine.playKnockoutLeg(skills(90), skills(30), tieBreak: true, using: &rng)
            if r.homeGoals > r.awayGoals { starke += 1 } else { schwache += 1 }
        }
        XCTAssertGreaterThan(starke, schwache)
    }
}
