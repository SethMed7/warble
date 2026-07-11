import XCTest
@testable import Dictate

/// The listening contract's audible half (ROADMAP 0.4): the ping synthesis is pure math, so its
/// promises are provable here — subtle by construction (amplitude is a hard ceiling), click-free
/// (starts and ends at silence), decaying (a ping, not a beep), and tiny (well under the 100 KB
/// asset budget — there is no asset at all). The toggle's cross-process persistence is proven by
/// regression.sh via `--sounds`; actually HEARING the pings is a by-hand item in docs/testing.md.
final class SoundsTests: XCTestCase {
    // The shipped parameters (Sounds.swift): start = A5, stop = D5 quieter — asserted here so a
    // retune keeps the contract's shape even if the numbers move.
    private let start = DictateSounds.tone(frequency: 880, seconds: 0.12, amplitude: 0.30)
    private let stop = DictateSounds.tone(frequency: 587.33, seconds: 0.10, amplitude: 0.18)

    func testToneShape() {
        XCTAssertEqual(start.count, Int(0.12 * DictateSounds.sampleRate))
        XCTAssertEqual(start.first, 0, "attack starts at silence — no thump")
        XCTAssertLessThan(abs(start.last ?? 1), 0.001, "fades to silence — no click")
        let peak = start.map(abs).max() ?? 1
        XCTAssertLessThanOrEqual(peak, 0.30, "amplitude is a ceiling — subtle by construction")
        XCTAssertGreaterThan(peak, 0.1, "and it's actually audible")
    }

    func testToneDecays() {
        // A ping, not a beep: the first half must carry the overwhelming share of the energy.
        let half = start.count / 2
        let early = start[..<half].reduce(0.0) { $0 + Double($1 * $1) }
        let late = start[half...].reduce(0.0) { $0 + Double($1 * $1) }
        XCTAssertGreaterThan(early, late * 4)
    }

    func testStopIsQuieterAndDistinct() {
        let startPeak = start.map(abs).max() ?? 0
        let stopPeak = stop.map(abs).max() ?? 1
        XCTAssertLessThan(stopPeak, startPeak, "the stop ping is the quieter of the pair")
        XCTAssertNotEqual(start.count, stop.count, "and shorter — two distinct events")
    }

    func testWavIsTinyAndWellFormed() {
        let d = DictateSounds.wav(start)
        XCTAssertEqual(d.count, 44 + start.count * 2, "44-byte PCM header + 16-bit samples")
        XCTAssertLessThan(d.count, 100_000, "the '< 100 KB, no asset, no networking' budget")
        XCTAssertEqual(String(data: d.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: d.subdata(in: 8..<12), encoding: .ascii), "WAVE")
    }
}

/// The hover-revealed gesture hints ("hover the pill → shows the hotkey") — pure copy, one line
/// per pill phase, so a wording change is deliberate (the --errors philosophy, in miniature).
final class PillHintTests: XCTestCase {
    func testGestureHints() {
        XCTAssertEqual(PillHint.listening(handsFree: false), "hold Fn · Esc cancels")
        XCTAssertEqual(PillHint.listening(handsFree: true), "double-tap Fn to stop · Esc cancels")
        XCTAssertEqual(PillHint.processing, "Esc cancels")
        XCTAssertEqual(PillHint.idle, "hold Fn to dictate")
    }
}
