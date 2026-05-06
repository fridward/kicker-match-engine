import Foundation

/// Engine-Repräsentation eines Teams für die Match-Sim. Plain Struct,
/// kein Fluent / SwiftUI — Storage-Layer projiziert bei Bedarf hierauf.
///
/// `moral` und `zusammenspiel` spiegeln Sp.info(N,6) und Sp.info(N,7) im
/// Original (KICKER.BAS:7675-7676 Init=50). Optional aus Backwards-Compat
/// — bei nil nimmt die Engine 50 als Default.
public struct EngineTeam: Identifiable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var moral: Int?
    public var zusammenspiel: Int?

    public init(
        id: UUID = UUID(),
        name: String,
        moral: Int? = 50,
        zusammenspiel: Int? = 50
    ) {
        self.id = id
        self.name = name
        self.moral = moral
        self.zusammenspiel = zusammenspiel
    }
}
