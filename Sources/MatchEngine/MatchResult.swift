import Foundation

/// Output einer Match-Simulation. Enthält das Endergebnis plus alle
/// Einzel-Ereignisse die der Client für die Highlight-Anzeige braucht.
public struct EngineMatchResult: Codable, Equatable {
    public let homeTeamID: UUID
    public let awayTeamID: UUID
    public let matchDay: Int
    public let leagueIndex: Int

    public var homeGoals: Int = 0
    public var awayGoals: Int = 0

    public var goalScorers: [EngineGoalEvent] = []
    public var yellowCards: [EngineCardEvent] = []
    public var redCards: [EngineCardEvent] = []
    public var injury: EngineInjuryEvent?

    public init(
        homeTeamID: UUID,
        awayTeamID: UUID,
        matchDay: Int,
        leagueIndex: Int
    ) {
        self.homeTeamID = homeTeamID
        self.awayTeamID = awayTeamID
        self.matchDay = matchDay
        self.leagueIndex = leagueIndex
    }
}

public struct EngineGoalEvent: Codable, Equatable {
    /// Drift D-5-Fix gegenüber iOS: Schütze wird über ID referenziert,
    /// nicht über Name. Verhindert latenten Bug bei gleichnamigen
    /// Spielern in verschiedenen Vereinen.
    public let scorerID: UUID
    public let scorerName: String
    public let minute: Int
    public let scoreAtTime: String
    public let isHome: Bool

    public init(scorerID: UUID, scorerName: String, minute: Int, scoreAtTime: String, isHome: Bool) {
        self.scorerID = scorerID
        self.scorerName = scorerName
        self.minute = minute
        self.scoreAtTime = scoreAtTime
        self.isHome = isHome
    }
}

public struct EngineCardEvent: Codable, Equatable {
    public let playerID: UUID
    public let playerName: String
    public let isRed: Bool
    public let teamName: String
    /// Spielminute der Karte (5..90). Original trackt das nicht akkurat;
    /// für den Replay-Ticker ist eine plausible Minute nötig.
    public let minute: Int

    public init(playerID: UUID, playerName: String, isRed: Bool, teamName: String, minute: Int) {
        self.playerID = playerID
        self.playerName = playerName
        self.isRed = isRed
        self.teamName = teamName
        self.minute = minute
    }
}

public struct EngineInjuryEvent: Codable, Equatable {
    public let playerID: UUID
    public let playerName: String
    public let isHome: Bool
    /// Ausfall-Wochen (1..8), entsprechend KICKER.BAS:3944.
    public let weeks: Int
    /// Spielminute der Verletzung (5..85).
    public let minute: Int

    public init(playerID: UUID, playerName: String, isHome: Bool, weeks: Int, minute: Int) {
        self.playerID = playerID
        self.playerName = playerName
        self.isHome = isHome
        self.weeks = weeks
        self.minute = minute
    }
}
