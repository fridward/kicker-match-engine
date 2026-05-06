import Foundation

/// Deterministischer Pseudo-Zufallsgenerator für die Match-Engine-Portierung.
///
/// SplitMix64 — schnell, gut verteilt, zustandsklein (1 UInt64).
/// Wird pro Spieltag mit einem festen Seed initialisiert; gleicher Seed
/// → identische Sequenz → identischer Match-Output auf allen Geräten.
public struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = (seed == 0) ? 0x9E3779B97F4A7C15 : seed
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z &>> 27)) &* 0x94D049BB133111EB
        return z ^ (z &>> 31)
    }

    public mutating func int(in range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &self)
    }

    public mutating func int(in range: Range<Int>) -> Int {
        Int.random(in: range, using: &self)
    }

    public mutating func double() -> Double {
        Double.random(in: 0.0..<1.0, using: &self)
    }

    public mutating func chance(_ probability: Double) -> Bool {
        double() < probability
    }
}

extension SeededRandom {
    /// Mischt einen Seed aus zwei Komponenten — typisch:
    /// `derive(season.seed, matchday)` für reproduzierbare Spieltag-Seeds.
    public static func derive(_ a: UInt64, _ b: Int) -> UInt64 {
        var s = SeededRandom(seed: a &+ UInt64(bitPattern: Int64(b)))
        return s.next()
    }
}
