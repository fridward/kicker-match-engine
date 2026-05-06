import Foundation

/// Engine-Repräsentation eines Spielers — der minimale Subset von Feldern,
/// den `MatchEngine` für die Sim braucht. Bewusst KEIN Fluent-/SwiftUI-
/// Model — die Engine bleibt pure und unabhängig vom Storage-Layer.
/// Persistenz-Modelle (iOS-`Player`, Backend-`Player`) projizieren bei
/// Bedarf in diesen Typ.
public struct EnginePlayer: Identifiable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var position: EnginePosition

    /// Skills als Float (Original `Pl.skill(N, F)`, KICKER.BAS:13899-13911).
    public var skillGoalkeeping: Double
    public var skillDefense: Double
    public var skillMidfield: Double
    public var skillAttack: Double

    public var energy: Int
    public var form: Int

    public var status: EnginePlayerStatus
    /// Wochen bis Rückkehr aus dem Trainingslager (nil/0 = nicht verreist).
    public var trainingCampWeeks: Int?

    /// Verbleibende Spieltage Ausfall (Sperre/Verletzung/Krankheit).
    public var suspensionWeeks: Int = 0

    /// Sliding-Window-Counter für Spielerentwicklung — Original
    /// `Pl.leistung%(N,5)` (KICKER.BAS:4151-4194).
    public var pleistungCounter: Int = 4

    /// Saison-akkumulierte Karten — Sperren-Schwellen in
    /// `applyCardConsequences` (KICKER.BAS:4210).
    public var yellowCards: Int = 0
    public var redCards: Int = 0

    /// Verbleibende Vertragsdauer in Wochen (KICKER.BAS:3997-4002).
    public var contractWeeks: Int = 60

    /// Convenience-Init mit Int-Skills (Templates aus KDT, Test-Fixtures).
    public init(
        id: UUID = UUID(),
        name: String,
        position: EnginePosition,
        skillT: Int, skillV: Int, skillM: Int, skillA: Int,
        energy: Int = 15,
        form: Int = 15,
        status: EnginePlayerStatus = .ok,
        trainingCampWeeks: Int? = nil,
        suspensionWeeks: Int = 0,
        pleistungCounter: Int = 4,
        yellowCards: Int = 0,
        redCards: Int = 0,
        contractWeeks: Int = 60
    ) {
        self.init(
            id: id, name: name, position: position,
            skillT: Double(skillT), skillV: Double(skillV),
            skillM: Double(skillM), skillA: Double(skillA),
            energy: energy, form: form,
            status: status, trainingCampWeeks: trainingCampWeeks,
            suspensionWeeks: suspensionWeeks,
            pleistungCounter: pleistungCounter,
            yellowCards: yellowCards, redCards: redCards,
            contractWeeks: contractWeeks
        )
    }

    /// Voller Init mit Float-Skills (DB-Hydration, Skill-Drift-Tests).
    public init(
        id: UUID = UUID(),
        name: String,
        position: EnginePosition,
        skillT: Double, skillV: Double, skillM: Double, skillA: Double,
        energy: Int = 15,
        form: Int = 15,
        status: EnginePlayerStatus = .ok,
        trainingCampWeeks: Int? = nil,
        suspensionWeeks: Int = 0,
        pleistungCounter: Int = 4,
        yellowCards: Int = 0,
        redCards: Int = 0,
        contractWeeks: Int = 60
    ) {
        self.id = id
        self.name = name
        self.position = position
        self.skillGoalkeeping = skillT
        self.skillDefense = skillV
        self.skillMidfield = skillM
        self.skillAttack = skillA
        self.energy = energy
        self.form = form
        self.status = status
        self.trainingCampWeeks = trainingCampWeeks
        self.suspensionWeeks = suspensionWeeks
        self.pleistungCounter = pleistungCounter
        self.yellowCards = yellowCards
        self.redCards = redCards
        self.contractWeeks = contractWeeks
    }

    /// Skill-Wert an der eigenen Position als Int — `Pl.info(N,1)` im Original.
    public var primarySkill: Int {
        switch position {
        case .goalkeeper: return Int(skillGoalkeeping)
        case .defender:   return Int(skillDefense)
        case .midfielder: return Int(skillMidfield)
        case .forward:    return Int(skillAttack)
        }
    }

    /// Gewichtetes Skill-Mass für Auto-Aufstellung.
    public var overallSkill: Double {
        let t = Double(Int(skillGoalkeeping))
        let v = Double(Int(skillDefense))
        let m = Double(Int(skillMidfield))
        let a = Double(Int(skillAttack))
        let primary: Double
        switch position {
        case .goalkeeper: primary = t * 2 + v
        case .defender:   primary = v * 2 + m
        case .midfielder: primary = m * 2 + a
        case .forward:    primary = a * 2 + m
        }
        return primary / 3.0
    }

    /// KICKER.BAS:6858-6868 — Spieler im Trainingslager, krank, verletzt
    /// oder gesperrt sind nicht aufstellbar.
    public var isAvailable: Bool {
        status == .ok && (trainingCampWeeks ?? 0) == 0
    }
}

public enum EnginePlayerStatus: String, Codable, Equatable {
    case ok        = "OK"
    case injured   = "VERLETZT"
    case sick      = "KRANK"
    case suspended = "GESPERRT"
    case training  = "TRAINING"
}
