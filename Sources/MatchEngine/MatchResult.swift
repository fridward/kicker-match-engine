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
    /// Angezeigte Spielminute. In der Nachspielzeit bleibt sie auf 90 stehen,
    /// der Zuschlag steckt in `stoppage`.
    public let minute: Int
    /// Nachspielzeit-Zuschlag in Minuten; 0/nil = regulaer.
    ///
    /// OPTIONAL aus Kompatibilitaetsgruenden: Das Backend legt Tor-Events als
    /// JSON in der Datenbank ab (`goalScorersJSON`). Alte Zeilen haben das Feld
    /// nicht — als Optional decodiert `JSONDecoder` sie weiterhin fehlerfrei.
    public let stoppage: Int?
    public let scoreAtTime: String
    public let isHome: Bool

    public init(scorerID: UUID, scorerName: String, minute: Int,
                stoppage: Int? = nil, scoreAtTime: String, isHome: Bool) {
        self.scorerID = scorerID
        self.scorerName = scorerName
        self.minute = minute
        self.stoppage = stoppage
        self.scoreAtTime = scoreAtTime
        self.isHome = isHome
    }

    /// EINE Quelle fuer die Minuten-Beschriftung, damit iOS, Android, Replay
    /// und Kurier nicht je eigene Regeln erfinden: `"45"` bzw. `"90+3"`.
    /// Der Punkt dahinter gehoert dem Aufrufer (mal `"45."`, mal `"45. MIN"`).
    public var minuteLabel: String {
        MatchEngine.minuteLabel(minute: minute, stoppage: stoppage)
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

    public init(playerID: UUID, playerName: String, isRed: Bool, teamName: String, minute: Int = 0) {
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

    public init(playerID: UUID, playerName: String, isHome: Bool, weeks: Int, minute: Int = 0) {
        self.playerID = playerID
        self.playerName = playerName
        self.isHome = isHome
        self.weeks = weeks
        self.minute = minute
    }
}
