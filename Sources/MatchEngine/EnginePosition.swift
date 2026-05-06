import Foundation

/// Spieler-Position. RawValue 0..3 entspricht direkt der Zelle 1
/// im Original `Pl.info(N, 1)` (KICKER.BAS:14117).
public enum EnginePosition: Int, Codable, CaseIterable, Sendable {
    case goalkeeper = 0
    case defender
    case midfielder
    case forward
}
