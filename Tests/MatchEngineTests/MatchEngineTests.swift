import XCTest
import Foundation   // UUID — Skip mappt auf SkipFoundation
@testable import MatchEngine

final class MatchEngineTests: XCTestCase {

    // MARK: - Skip-taugliche Throw-Helfer
    // Skips XCTest-Shim kennt XCTAssertThrowsError / XCTAssertNoThrow nicht →
    // via do/catch + XCTAssertTrue/False (beide werden transpiliert).

    // Closure als LETZTER Parameter — Kotlin bindet Trailing-Lambdas ans letzte
    // Argument (Swift ebenso), sonst landet die Closure beim String.
    private func assertThrows(_ msg: String = "erwarteter Fehler blieb aus",
                              _ body: () throws -> Void) {
        var threw = false
        do { try body() } catch { threw = true }
        XCTAssertTrue(threw, msg)
    }

    private func assertNoThrow(_ msg: String = "unerwarteter Fehler",
                               _ body: () throws -> Void) {
        var threw = false
        do { try body() } catch { threw = true }
        XCTAssertFalse(threw, msg)
    }

    // MARK: - Fixtures

    /// 22 Spieler: 1 GK + 5 V + 5 M + 5 A pro Team — reicht für Lineup + Bank.
    private func makeSquad(prefix: String) -> [EnginePlayer] {
        var players: [EnginePlayer] = []
        players.append(.init(name: "\(prefix)-GK1", position: .goalkeeper, skillT: 60, skillV: 0, skillM: 0, skillA: 0))
        players.append(.init(name: "\(prefix)-GK2", position: .goalkeeper, skillT: 40, skillV: 0, skillM: 0, skillA: 0))
        for i in 0..<5 { players.append(.init(name: "\(prefix)-V\(i)", position: .defender,   skillT: 0, skillV: 50 + i, skillM: 10, skillA: 0)) }
        for i in 0..<5 { players.append(.init(name: "\(prefix)-M\(i)", position: .midfielder, skillT: 0, skillV: 10, skillM: 50 + i, skillA: 20)) }
        for i in 0..<5 { players.append(.init(name: "\(prefix)-A\(i)", position: .forward,    skillT: 0, skillV: 0,  skillM: 20, skillA: 50 + i)) }
        return players
    }

    private func lineupIDs(_ players: [EnginePlayer]) -> Set<UUID> {
        // Nimm den stärksten GK + die ersten 10 Feldspieler.
        let gk = players.first { $0.position == .goalkeeper }!
        let field = players.filter { $0.position != .goalkeeper }.prefix(10)
        return Set([gk.id] + field.map(\.id))
    }

    // MARK: - SeededRandom

    func test_seededRandom_isDeterministic_forSameSeed() {
        var a = SeededRandom(seed: UInt64(42))
        var b = SeededRandom(seed: UInt64(42))
        for _ in 0..<100 {
            XCTAssertEqual(a.next(), b.next())
        }
    }

    func test_seededRandom_differs_forDifferentSeeds() {
        var a = SeededRandom(seed: UInt64(1))
        var b = SeededRandom(seed: UInt64(2))
        XCTAssertNotEqual(a.next(), b.next())
    }

    func test_seededRandom_zeroSeed_isReplacedWithGoldenRatio() {
        // Seed 0 wird intern durch 0x9E37… ersetzt (sonst stuck-state).
        // Konstante aus zwei 32-Bit-Hälften gebaut — Skip/Kotlin kann kein
        // UInt64-Literal > Int64.max direkt parsen (0x9E37… > Int64.max).
        let golden = (UInt64(0x9E3779B9) << 32) | UInt64(0x7F4A7C15)
        var a = SeededRandom(seed: UInt64(0))
        var b = SeededRandom(seed: golden)
        XCTAssertEqual(a.next(), b.next())
    }

    // MARK: - LineupValidator

    private let players = (0..<15).map { i in
        EnginePlayer(name: "P\(i)", position: .midfielder, skillT: 0, skillV: 0, skillM: 50, skillA: 0)
    }

    func test_lineupValidator_acceptsValidSubmission() {
        assertNoThrow {
            try LineupValidator.validate(
                playerIDs: players.prefix(11).map(\.id),
                tactic: 2, matchDay: 5, currentMatchDay: 4,
                clubPlayers: players)
        }
    }

    func test_lineupValidator_rejectsPastMatchDay() {
        assertThrows {
            try LineupValidator.validate(
                playerIDs: players.prefix(11).map(\.id),
                tactic: 2, matchDay: 3, currentMatchDay: 5,
                clubPlayers: players)
        }
    }

    func test_lineupValidator_rejectsMatchDayBeyond34() {
        assertThrows {
            try LineupValidator.validate(
                playerIDs: players.prefix(11).map(\.id),
                tactic: 2, matchDay: 35, currentMatchDay: 0,
                clubPlayers: players)
        }
    }

    func test_lineupValidator_rejectsMoreThan11Players() {
        assertThrows {
            try LineupValidator.validate(
                playerIDs: players.prefix(12).map(\.id),
                tactic: 2, matchDay: 1, currentMatchDay: 0,
                clubPlayers: players)
        }
    }

    func test_lineupValidator_rejectsDuplicates() {
        let id = players[0].id
        assertThrows {
            try LineupValidator.validate(
                playerIDs: [id, id],
                tactic: 2, matchDay: 1, currentMatchDay: 0,
                clubPlayers: players)
        }
    }

    func test_lineupValidator_rejectsForeignIDs() {
        assertThrows {
            try LineupValidator.validate(
                playerIDs: [UUID()],
                tactic: 2, matchDay: 1, currentMatchDay: 0,
                clubPlayers: players)
        }
    }

    func test_lineupValidator_rejectsTacticOutOfRange() {
        assertThrows {
            try LineupValidator.validate(
                playerIDs: [], tactic: 5, matchDay: 1, currentMatchDay: 0, clubPlayers: players)
        }
        assertThrows {
            try LineupValidator.validate(
                playerIDs: [], tactic: -1, matchDay: 1, currentMatchDay: 0, clubPlayers: players)
        }
    }

    /// Frank-Bug 2026-05-09: KRANK/VERLETZT/GESPERRT-Spieler dürfen in der
    /// gespeicherten Aufstellung stehen — sonst kann nach plötzlicher Krankheit
    /// kein Spieltag mehr abgesendet werden.
    func test_lineupValidator_acceptsInjuredSickSuspendedInLineup() {
        var squad = players
        squad[0].status = .injured
        squad[1].status = .sick
        squad[2].status = .suspended
        assertNoThrow {
            try LineupValidator.validate(
                playerIDs: squad.prefix(11).map(\.id),
                tactic: 2, matchDay: 1, currentMatchDay: 0,
                clubPlayers: squad)
        }
    }

    // MARK: - pickLineup

    func test_pickLineup_autoPick_selectsBestGKAndTop10Field() {
        let squad = makeSquad(prefix: "H")
        let picked = MatchEngine.pickLineup(from: squad, lineupIDs: nil)
        XCTAssertEqual(picked.count, 11)
        XCTAssertEqual(picked.filter { $0.position == .goalkeeper }.count, 1)
        // Bester Torwart = "H-GK1" (skillT 60 > 40)
        XCTAssertEqual(picked.first { $0.position == .goalkeeper }?.name, "H-GK1")
    }

    func test_pickLineup_explicitLineup_returnsOnlyThose() {
        let squad = makeSquad(prefix: "H")
        let ids = Set(squad.prefix(11).map(\.id))
        let picked = MatchEngine.pickLineup(from: squad, lineupIDs: ids)
        XCTAssertEqual(Set(picked.map(\.id)), ids)
    }

    func test_pickLineup_filtersUnavailable() {
        var squad = makeSquad(prefix: "H")
        squad[0].status = .injured                // GK1
        squad[2].status = .sick                   // V0
        let picked = MatchEngine.pickLineup(from: squad, lineupIDs: nil)
        XCTAssertFalse(picked.contains { $0.status != .ok })
    }

    /// Frank-Bug 2026-05-23: vorher griff Auto-Top-11 als Fallback, wenn
    /// alle explizit aufgestellten Spieler unavailable wurden — dadurch
    /// konnten Bank-Spieler Tore schießen.
    func test_pickLineup_explicitLineup_doesNotFallbackToAutoPick() {
        let squad = makeSquad(prefix: "H")
        var modifiable = squad
        // Aufstellung: nur 3 Spieler, einer davon krank.
        let lineup = Set(squad.prefix(3).map(\.id))
        modifiable[0].status = .sick
        let picked = MatchEngine.pickLineup(from: modifiable, lineupIDs: lineup)
        // Erwartet: 2 Spieler (3 - 1 krank), KEIN Auto-Fill auf 11.
        XCTAssertEqual(picked.count, 2)
        XCTAssertTrue(picked.allSatisfy { lineup.contains($0.id) })
    }

    // MARK: - applyTactic

    func test_applyTactic_defensiveBoostsDefense() {
        var s = MatchEngine.TeamSkills(moral: 50, zusammenspiel: 50, kondition: 50,
                                       torwart: 50, defense: 50, midfield: 50, attack: 50)
        let before = s
        MatchEngine.applyTactic(&s, tactic: 0)   // sehr defensiv
        XCTAssertGreaterThan(s.defense, before.defense)
        XCTAssertLessThan(s.attack, before.attack)
    }

    func test_applyTactic_offensiveBoostsAttack() {
        var s = MatchEngine.TeamSkills(moral: 50, zusammenspiel: 50, kondition: 50,
                                       torwart: 50, defense: 50, midfield: 50, attack: 50)
        let before = s
        MatchEngine.applyTactic(&s, tactic: 4)   // sehr offensiv
        XCTAssertGreaterThan(s.attack, before.attack)
        XCTAssertLessThan(s.defense, before.defense)
    }

    func test_applyTactic_neutralIsNoop() {
        var s = MatchEngine.TeamSkills(moral: 50, zusammenspiel: 50, kondition: 50,
                                       torwart: 50, defense: 50, midfield: 50, attack: 50)
        let before = s
        MatchEngine.applyTactic(&s, tactic: 2)   // kontrolliert = Default
        XCTAssertEqual(s, before)
    }

    func test_applyTactic_clampsTo100() {
        var s = MatchEngine.TeamSkills(moral: 50, zusammenspiel: 50, kondition: 50,
                                       torwart: 50, defense: 90, midfield: 90, attack: 90)
        MatchEngine.applyTactic(&s, tactic: 4)
        XCTAssertLessThanOrEqual(s.attack, 100)
        XCTAssertLessThanOrEqual(s.midfield, 100)
        XCTAssertGreaterThanOrEqual(s.defense, 1)
    }

    // MARK: - aggregateTeamSkills

    func test_aggregateTeamSkills_emptyLineup_fallsBackToMinimum() {
        let squad = makeSquad(prefix: "H")
        let skills = MatchEngine.aggregateTeamSkills(players: squad, lineupIDs: [])
        // Σ über leeres Lineup → alle 0, clamp() hebt auf min(1).
        XCTAssertEqual(skills.kondition, 1)
        XCTAssertEqual(skills.torwart, 1)
    }

    func test_aggregateTeamSkills_clampsTo100() {
        let squad = makeSquad(prefix: "H")
        let skills = MatchEngine.aggregateTeamSkills(players: squad, lineupIDs: lineupIDs(squad))
        XCTAssertLessThanOrEqual(skills.attack, 100)
        XCTAssertLessThanOrEqual(skills.defense, 100)
        XCTAssertLessThanOrEqual(skills.midfield, 100)
        XCTAssertLessThanOrEqual(skills.torwart, 100)
    }

    // MARK: - simulate — Determinismus

    func test_simulate_isDeterministic_forSameSeed() {
        let home = makeSquad(prefix: "H")
        let away = makeSquad(prefix: "A")
        let homeIDs = lineupIDs(home)
        let awayIDs = lineupIDs(away)
        let homeTeam = EngineTeam(name: "Home")
        let awayTeam = EngineTeam(name: "Away")

        var rng1 = SeededRandom(seed: UInt64(12345))
        var rng2 = SeededRandom(seed: UInt64(12345))
        let r1 = MatchEngine.simulate(
            homeTeam: homeTeam, awayTeam: awayTeam,
            homePlayers: home, awayPlayers: away,
            matchDay: 1, leagueIndex: 0,
            homeLineup: homeIDs, awayLineup: awayIDs,
            using: &rng1
        )
        let r2 = MatchEngine.simulate(
            homeTeam: homeTeam, awayTeam: awayTeam,
            homePlayers: home, awayPlayers: away,
            matchDay: 1, leagueIndex: 0,
            homeLineup: homeIDs, awayLineup: awayIDs,
            using: &rng2
        )
        XCTAssertEqual(r1, r2)
    }

    /// Frank-Bug 2026-05-09: Tor-Schützen müssen aus dem Lineup kommen,
    /// nicht aus dem Gesamtkader.
    func test_simulate_goalScorers_areAlwaysInLineup() {
        let home = makeSquad(prefix: "H")
        let away = makeSquad(prefix: "A")
        let homeIDs = lineupIDs(home)
        let awayIDs = lineupIDs(away)

        // Über mehrere Seeds, um Tore wahrscheinlich zu machen.
        for seed in [1, 2, 3, 7, 11, 42, 99, 1000] {
            var rng = SeededRandom(seed: UInt64(seed))
            let r = MatchEngine.simulate(
                homeTeam: EngineTeam(name: "Home"),
                awayTeam: EngineTeam(name: "Away"),
                homePlayers: home, awayPlayers: away,
                matchDay: 1, leagueIndex: 0,
                homeLineup: homeIDs, awayLineup: awayIDs,
                using: &rng
            )
            for goal in r.goalScorers {
                let pool = goal.isHome ? homeIDs : awayIDs
                XCTAssertTrue(pool.contains(goal.scorerID),
                              "Torschütze \(goal.scorerName) (\(goal.scorerID)) ist nicht im Lineup (seed=\(seed))")
            }
        }
    }

    /// Frank-Bug 2026-05-09: Karten dürfen nur an Feldspieler aus dem Lineup gehen.
    func test_simulate_cards_areAlwaysInLineupAndNotGoalkeeper() {
        let home = makeSquad(prefix: "H")
        let away = makeSquad(prefix: "A")
        let homeIDs = lineupIDs(home)
        let awayIDs = lineupIDs(away)
        let homeGKs = Set(home.filter { $0.position == .goalkeeper }.map(\.id))
        let awayGKs = Set(away.filter { $0.position == .goalkeeper }.map(\.id))

        for seed in [1, 2, 3, 7, 11, 42] {
            var rng = SeededRandom(seed: UInt64(seed))
            let r = MatchEngine.simulate(
                homeTeam: EngineTeam(name: "Home"),
                awayTeam: EngineTeam(name: "Away"),
                homePlayers: home, awayPlayers: away,
                matchDay: 1, leagueIndex: 0,
                homeLineup: homeIDs, awayLineup: awayIDs,
                using: &rng
            )
            for card in r.yellowCards + r.redCards {
                let inHome = homeIDs.contains(card.playerID)
                let inAway = awayIDs.contains(card.playerID)
                XCTAssertTrue(inHome || inAway, "Karte an Spieler außerhalb beider Lineups (seed=\(seed))")
                XCTAssertFalse(homeGKs.contains(card.playerID), "Karte an Heim-Torwart (seed=\(seed))")
                XCTAssertFalse(awayGKs.contains(card.playerID), "Karte an Gast-Torwart (seed=\(seed))")
            }
        }
    }

    func test_simulate_cards_noPlayerBookedTwiceInSameMatch() {
        let home = makeSquad(prefix: "H")
        let away = makeSquad(prefix: "A")
        let homeIDs = lineupIDs(home)
        let awayIDs = lineupIDs(away)

        for seed in (1...50) {
            var rng = SeededRandom(seed: UInt64(seed))
            let r = MatchEngine.simulate(
                homeTeam: EngineTeam(name: "Home"),
                awayTeam: EngineTeam(name: "Away"),
                homePlayers: home, awayPlayers: away,
                matchDay: 1, leagueIndex: 0,
                homeLineup: homeIDs, awayLineup: awayIDs,
                using: &rng
            )
            let all = (r.yellowCards + r.redCards).map(\.playerID)
            XCTAssertEqual(Set(all).count, all.count, "Spieler doppelt gebucht bei seed=\(seed)")
        }
    }

    func test_simulate_extraTime_onlyAppliedOnDraw() {
        let home = makeSquad(prefix: "H")
        let away = makeSquad(prefix: "A")
        let homeIDs = lineupIDs(home)
        let awayIDs = lineupIDs(away)

        var rng = SeededRandom(seed: UInt64(1))
        let r = MatchEngine.simulate(
            homeTeam: EngineTeam(name: "Home"),
            awayTeam: EngineTeam(name: "Away"),
            homePlayers: home, awayPlayers: away,
            matchDay: 1, leagueIndex: 0,
            homeLineup: homeIDs, awayLineup: awayIDs,
            extraTimeOnDraw: true,
            using: &rng
        )
        // Wenn das Ergebnis kein Unentschieden ist, dürfen keine 90+ Minuten existieren.
        if r.homeGoals != r.awayGoals {
            XCTAssertFalse(r.goalScorers.contains(where: { $0.minute > 90 }))
        }
    }

    func test_simulate_goalCount_matchesScorerEvents() {
        let home = makeSquad(prefix: "H")
        let away = makeSquad(prefix: "A")
        let homeIDs = lineupIDs(home)
        let awayIDs = lineupIDs(away)

        for seed in (1...20) {
            var rng = SeededRandom(seed: UInt64(seed))
            let r = MatchEngine.simulate(
                homeTeam: EngineTeam(name: "Home"),
                awayTeam: EngineTeam(name: "Away"),
                homePlayers: home, awayPlayers: away,
                matchDay: 1, leagueIndex: 0,
                homeLineup: homeIDs, awayLineup: awayIDs,
                using: &rng
            )
            XCTAssertEqual(r.goalScorers.filter { $0.isHome }.count, r.homeGoals, "seed=\(seed)")
            XCTAssertEqual(r.goalScorers.filter { !$0.isHome }.count, r.awayGoals, "seed=\(seed)")
        }
    }

    func test_simulate_injuryProbability_zero_neverInjures() {
        let home = makeSquad(prefix: "H")
        let away = makeSquad(prefix: "A")
        for seed in (1...30) {
            var rng = SeededRandom(seed: UInt64(seed))
            let r = MatchEngine.simulate(
                homeTeam: EngineTeam(name: "Home"),
                awayTeam: EngineTeam(name: "Away"),
                homePlayers: home, awayPlayers: away,
                matchDay: 1, leagueIndex: 0,
                homeLineup: lineupIDs(home), awayLineup: lineupIDs(away),
                injuryProbabilityPercent: 0,
                using: &rng
            )
            XCTAssertNil(r.injury, "Verletzung trotz 0%% bei seed=\(seed)")
        }
    }

    // MARK: - Difficulty-Skalierung

    func test_injuryProbability_monotonicAndClamped() {
        XCTAssertEqual(MatchEngine.injuryProbability(for: 0), 3)
        XCTAssertEqual(MatchEngine.injuryProbability(for: 4), 22)
        XCTAssertEqual(MatchEngine.injuryProbability(for: -1), 3)
        XCTAssertEqual(MatchEngine.injuryProbability(for: 99), 22)
        XCTAssertLessThan(MatchEngine.injuryProbability(for: 0),
                          MatchEngine.injuryProbability(for: 4))
    }

    func test_energyDrainFactor_neutralAtLevel2() {
        XCTAssertEqual(MatchEngine.energyDrainFactor(for: 2), 1.0)
        XCTAssertLessThan(MatchEngine.energyDrainFactor(for: 0), 1.0)
        XCTAssertGreaterThan(MatchEngine.energyDrainFactor(for: 4), 1.0)
    }
}
