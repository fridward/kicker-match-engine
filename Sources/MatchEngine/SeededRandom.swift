import Foundation

/// Deterministischer Pseudo-Zufallsgenerator für die Match-Engine-Portierung.
///
/// SplitMix64 — schnell, gut verteilt, zustandsklein (1 UInt64).
/// Wird pro Spieltag mit einem festen Seed initialisiert; gleicher Seed
/// → identische Sequenz → identischer Match-Output auf allen Geräten.
public struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    // SplitMix64-Konstanten. Skip/Kotlin gibt 64-Bit-Hex-Literale > 2^63 OHNE
    // `uL`-Suffix aus → Kotlin meldet "Value out of range". Deshalb setzen wir
    // die Konstanten aus zwei 32-Bit-Hälften (jede < 2^32, problemlos
    // transpilierbar) zusammen. Das Ergebnis ist BIT-IDENTISCH zum
    // Original-Literal — iOS-Verhalten bleibt damit unverändert:
    //   golden = 0x9E3779B97F4A7C15
    //   mix1   = 0xBF58476D1CE4E5B9
    //   mix2   = 0x94D049BB133111EB
    private static let golden: UInt64 = (UInt64(0x9E3779B9) << 32) | UInt64(0x7F4A7C15)
    private static let mix1:   UInt64 = (UInt64(0xBF58476D) << 32) | UInt64(0x1CE4E5B9)
    private static let mix2:   UInt64 = (UInt64(0x94D049BB) << 32) | UInt64(0x133111EB)

    public init(seed: UInt64) {
        // `UInt64(0)` statt Literal `0` — Skip verlangt einen expliziten Cast
        // beim Vergleich/der Zuweisung an unsigned Typen. Gleiches Ergebnis
        // wie das Original `(seed == 0) ? golden : seed`.
        let initial: UInt64 = (seed == UInt64(0)) ? SeededRandom.golden : seed
        self.state = initial
    }

    public mutating func next() -> UInt64 {
        state = state &+ SeededRandom.golden
        var z = state
        // `&>>` (masking shift) wird von Skip nicht nach Kotlin übersetzt.
        // Für UInt64 mit festem Shift < 64 ist `>>` identisch — gleiche Bits,
        // kein Maskierungs-Unterschied. iOS-Verhalten bleibt unverändert.
        z = (z ^ (z >> 30)) &* SeededRandom.mix1
        z = (z ^ (z >> 27)) &* SeededRandom.mix2
        return z ^ (z >> 31)
    }

    // Hinweis: `int(in:)` wird ausschliesslich vom nativen iOS-App-Code
    // (SpriteKit/Views) genutzt — in den geteilten Skip-Packages (Android)
    // gibt es KEINE Aufrufer (verifiziert). Auf Skip genügt daher eine
    // kompilierbare, selbst-konsistente Implementierung; das exakte
    // iOS-Verhalten liefert wie immer der `#else`-Zweig.

    #if !SKIP
    // Nur native (iOS): Skips generisches `ClosedRange<Int>` stellt keine
    // nutzbaren Grenz-Accessors bereit (`upperBound`/`first`/`count` lösen
    // alle auf String/unbekannt auf). Da diese Überladung in den geteilten
    // Skip-Packages KEINE Aufrufer hat (nur iOS-App-Code nutzt sie), wird sie
    // auf Android schlicht nicht mitkompiliert — die `Range<Int>`-Überladung
    // unten genügt dort. iOS-Verhalten unverändert.
    public mutating func int(in range: ClosedRange<Int>) -> Int {
        return Int.random(in: range, using: &self)
    }
    #endif

    public mutating func int(in range: Range<Int>) -> Int {
        #if SKIP
        let bound = range.upperBound - range.lowerBound
        if bound <= 1 { return range.lowerBound }
        let scaled = Int((Double(next() >> 11) * (1.0 / 9007199254740992.0)) * Double(bound))
        return range.lowerBound + (scaled >= bound ? bound - 1 : scaled)
        #else
        return Int.random(in: range, using: &self)
        #endif
    }

    public mutating func double() -> Double {
        #if SKIP
        // Skip/Kotlin: `Double.random(in:using:)` ist nicht verfügbar. Wir
        // leiten den Wert direkt aus `next()` ab — obere 53 Bits / 2^53 →
        // gleichverteilt in [0,1). Deterministisch je Seed (Android-Solo ist
        // unabhängig von iOS/Backend, daher genügt Selbst-Konsistenz).
        return Double(next() >> 11) * (1.0 / 9007199254740992.0)
        #else
        return Double.random(in: 0.0..<1.0, using: &self)
        #endif
    }

    public mutating func chance(_ probability: Double) -> Bool {
        double() < probability
    }
}

extension SeededRandom {
    /// Mischt einen Seed aus zwei Komponenten — typisch:
    /// `derive(season.seed, matchday)` für reproduzierbare Spieltag-Seeds.
    public static func derive(_ a: UInt64, _ b: Int) -> UInt64 {
        #if SKIP
        // `UInt64(bitPattern: Int64(b))` ist in Skip nicht verfügbar. b ist in
        // der Praxis ein kleiner positiver Spieltag-Index; Zwei-Komplement-
        // Bitmuster via &+ nachbilden, identisch zum Original.
        let bBits: UInt64 = b >= 0
            ? UInt64(b)
            : (UInt64.max &- UInt64(-(b + 1)))
        var s = SeededRandom(seed: a &+ bBits)
        return s.next()
        #else
        var s = SeededRandom(seed: a &+ UInt64(bitPattern: Int64(b)))
        return s.next()
        #endif
    }
}
