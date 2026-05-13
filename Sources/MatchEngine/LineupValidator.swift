import Foundation

/// Pure-Validation für Aufstellungs-Submits. DB-Layer (Endpoint im
/// Backend) lädt erst den Verein und dessen Spieler, dann diese
/// Validierung über die Engine-Sicht.
public enum LineupValidator {

    public struct ValidationError: Error, CustomStringConvertible {
        public let reason: String
        public init(reason: String) { self.reason = reason }
        public var description: String { reason }
    }

    /// - playerIDs: Aufstellung (max 11)
    /// - tactic: 0..4
    /// - matchDay: gewünschter Spieltag (1..34)
    /// - currentMatchDay: bereits gespielter Spieltag der Saison (0 = noch nichts)
    /// - clubPlayers: alle Spieler des Vereins (Engine-Sicht)
    public static func validate(
        playerIDs: [UUID],
        tactic: Int,
        matchDay: Int,
        currentMatchDay: Int,
        clubPlayers: [EnginePlayer]
    ) throws {
        guard matchDay > currentMatchDay else {
            throw ValidationError(reason: "Spieltag \(matchDay) liegt in der Vergangenheit (aktuell \(currentMatchDay))")
        }
        guard matchDay <= 34 else {
            throw ValidationError(reason: "Spieltag \(matchDay) > 34 (Saison hat nur 34 Spieltage)")
        }
        guard playerIDs.count <= 11 else {
            throw ValidationError(reason: "Aufstellung darf maximal 11 Spieler enthalten (eingereicht: \(playerIDs.count))")
        }
        guard Set(playerIDs).count == playerIDs.count else {
            throw ValidationError(reason: "Doppelte Spieler in der Aufstellung")
        }
        guard (0...4).contains(tactic) else {
            throw ValidationError(reason: "Taktik muss zwischen 0 und 4 liegen (eingereicht: \(tactic))")
        }
        let clubIDs = Set(clubPlayers.map(\.id))
        let foreign = playerIDs.filter { !clubIDs.contains($0) }
        guard foreign.isEmpty else {
            throw ValidationError(reason: "Spieler-IDs gehören nicht zum Verein: \(foreign)")
        }
        // KRANK/VERLETZT/GESPERRT sind im Lineup ZULÄSSIG, werden in
        // `MatchEngine.pickLineup` durch `isAvailable` rausgefiltert. Frank-
        // Bug 2026-05-09: vorher wurde der Submit hart abgelehnt, sobald
        // ein gerade-erkrankter Spieler in der gespeicherten Aufstellung
        // stand — dadurch konnte Frank keinen Spieltag mehr senden, ohne
        // den Squad neu aufzustellen. Solo-Pendant (`Game.lineupCheck`,
        // `MainMenuView.swift:947ff`) filtert silent. Wir matchen das.
    }
}
