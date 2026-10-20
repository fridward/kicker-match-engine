// Tribute: Rote und Gelb-Rote Karten schwaechen das Team ab der Minute des
// Platzverweises (Frank-Entscheid 2026-10-07). Bewusste Abweichung vom
// Original — dort steht das Ergebnis vor den Karten fest (KICKER.BAS:2250 vs.
// 2639-2707). Klassik/PLUS (`cardImpact == false`) muessen bitgenau beim
// bisherigen Ablauf bleiben.
import XCTest
import Foundation
@testable import MatchEngine

final class CardImpactTests: XCTestCase {

    private func uuid(_ team: Int, _ n: Int) -> UUID {
        // Skip-tauglich: kein String(format:).
        var digits = String(team * 100 + n)
        while digits.count < 12 { digits = "0" + digits }
        return UUID(uuidString: "00000000-0000-0000-0000-" + digits)!
    }

    private func squad(_ team: Int, skill: Int) -> [EnginePlayer] {
        var players: [EnginePlayer] = []
        let positions: [EnginePosition] = [.goalkeeper, .defender, .defender, .defender, .defender,
                                           .midfielder, .midfielder, .midfielder, .midfielder,
                                           .forward, .forward]
        for i in 0..<positions.count {
            players.append(EnginePlayer(id: uuid(team, i), name: "P\(team)-\(i)", position: positions[i],
                                        skillT: skill, skillV: skill, skillM: skill, skillA: skill))
        }
        return players
    }

    private func play(seed: Int, cardImpact: Bool, extraTime: Bool = false) -> EngineMatchResult {
        var rng = SeededRandom(seed: UInt64(seed))
        return MatchEngine.simulate(
            homeTeam: EngineTeam(id: uuid(9, 1), name: "Heim"),
            awayTeam: EngineTeam(id: uuid(9, 2), name: "Gast"),
            homePlayers: squad(1, skill: 10), awayPlayers: squad(2, skill: 10),
            matchDay: 1, leagueIndex: 0,
            extraTimeOnDraw: extraTime,
            cardImpact: cardImpact,
            using: &rng)
    }

    /// Fingerabdruck des bisherigen Ablaufs (cardImpact == false) ueber 300
    /// Seeds. Der Wert wurde VOR dem Einbau von `cardImpact` gemessen — aendert
    /// er sich, hat sich das Original-Verhalten verschoben.
    /// 2026-10-19 neu gemessen (150008953 → 470976553): Karten-Totale werden
    /// jetzt wie in GFA gerundet statt einzeln abgeschnitten (Rot-Rate halbiert).
    func test_ohneCardImpact_bleibtDerBisherigeAblauf() {
        // Nur Swift: Kotlin rechnet `Int` mit 32 Bit und leitet den Zufall
        // ueber eigene Helfer ab — der Fingerabdruck ist plattformgebunden.
        #if SKIP
        return
        #else
        var sum = 0
        for seed in 1...300 {
            let r = play(seed: seed, cardImpact: false, extraTime: seed % 3 == 0)
            sum = (sum &* 31 &+ r.homeGoals &* 7 &+ r.awayGoals) % 1_000_000_007
            for g in r.goalScorers { sum = (sum &* 31 &+ g.minute) % 1_000_000_007 }
            for c in r.yellowCards { sum = (sum &* 31 &+ c.minute &+ 1) % 1_000_000_007 }
            for c in r.redCards { sum = (sum &* 31 &+ c.minute &+ 2) % 1_000_000_007 }
            XCTAssertTrue(r.redCards.allSatisfy { $0.isSecondYellow == nil })
        }
        XCTAssertEqual(sum, CardImpactTests.fingerprintBefore)
        #endif
    }
    static let fingerprintBefore = 470976553

    /// Rot-Rate wie im Original (KICKER.BAS:2705: `A%=3-Sqr(Sqr(Random(230)+1))`,
    /// GFA rundet bei der Integer-Zuweisung): 0,19 glatte Platzverweise pro
    /// Spiel (beide Teams), zwei Rote in 2,2 % der Spiele. Bis 2026-10-19
    /// schnitt der Port die Wurzel einzeln ab und lag bei 0,41 pro Spiel
    /// (Testerin: zwei Spiele hintereinander mit je zwei Platzverweisen).
    func test_rotRateEntsprichtDemOriginal() {
        #if SKIP
        return
        #else
        let games = 3000
        var reds = 0
        var twoReds = 0
        for seed in 1...games {
            let r = play(seed: seed, cardImpact: true)
            let straight = r.redCards.filter { $0.isSecondYellow != true }.count
            reds += straight
            if straight >= 2 { twoReds += 1 }
        }
        let perGame = Double(reds) / Double(games)
        XCTAssertEqual(perGame, 0.19, accuracy: 0.04, "Rote pro Spiel: \(perGame)")
        XCTAssertLessThan(Double(twoReds) / Double(games), 0.04, "Spiele mit zwei Roten: \(twoReds)")
        #endif
    }

    /// Reproduzierbar mit cardImpact.
    func test_cardImpact_gleicherSeedGleichesErgebnis() {
        for seed in 1...50 {
            let a = play(seed: seed, cardImpact: true)
            let b = play(seed: seed, cardImpact: true)
            XCTAssertEqual(a, b)
        }
    }

    /// Gelb-Rot entsteht, liegt nach der ersten Gelben desselben Spielers und
    /// kein Spieler fliegt zweimal.
    func test_gelbRot_folgtAufErsteGelbe() {
        var gelbRot = 0
        for seed in 1...3000 {
            let r = play(seed: seed, cardImpact: true)
            let offIDs = r.redCards.map { $0.playerID }
            XCTAssertEqual(Set(offIDs).count, offIDs.count, "Seed \(seed): doppelter Platzverweis")
            for c in r.redCards where c.isSecondYellow == true {
                gelbRot += 1
                let first = r.yellowCards.first { $0.playerID == c.playerID }
                XCTAssertNotNil(first, "Seed \(seed): Gelb-Rot ohne erste Gelbe")
                XCTAssertGreaterThan(c.minute, first?.minute ?? 999)
            }
        }
        XCTAssertGreaterThan(gelbRot, 0, "in 3000 Spielen muss es Gelb-Rot geben")
    }

    /// Wer vom Platz ist, schiesst kein Tor mehr.
    func test_keinTorNachPlatzverweis() {
        for seed in 1...3000 {
            let r = play(seed: seed, cardImpact: true, extraTime: true)
            for c in r.redCards {
                for g in r.goalScorers where g.scorerID == c.playerID {
                    XCTAssertLessThanOrEqual(g.minute, c.minute, "Seed \(seed): Tor nach Platzverweis")
                }
            }
        }
    }

    /// Ein frueher Platzverweis senkt die Torerwartung des Teams.
    func test_platzverweisSchwaechtTeam() {
        let base = MatchEngine.aggregateTeamSkills(players: squad(1, skill: 10))
        let phases = MatchEngine.dismissalPhases(
            lineup: squad(1, skill: 10),
            dismissals: [EngineCardEvent(playerID: uuid(1, 9), playerName: "P1-9", isRed: true,
                                         teamName: "Heim", minute: 1)],
            override: nil, teamMoral: 50, teamZusammenspiel: 50, tactic: 2)
        XCTAssertEqual(phases.count, 1)
        XCTAssertLessThan(phases[0].skills.attack, base.attack)

        var goalsFull = 0
        var goalsShort = 0
        for seed in 1...2000 {
            var r1 = SeededRandom(seed: UInt64(seed))
            var r2 = SeededRandom(seed: UInt64(seed))
            var sk = base
            MatchEngine.applyTactic(&sk, tactic: 2)
            goalsFull += MatchEngine.ermittleErgebnis(sk, sk, ticks: 32, startMinute: 0, using: &r1).homeGoals
            goalsShort += MatchEngine.ermittleErgebnis(sk, sk, ticks: 32, startMinute: 0,
                                                       homePhases: phases, using: &r2).homeGoals
        }
        XCTAssertLessThan(goalsShort, goalsFull)
    }
}
