import XCTest
@testable import Dictate

/// The engine chain-order resolution (ROADMAP 0.7 SpeechAnalyzer evaluation). `chainOrder` is the
/// single source of truth `run()` builds its chain in and `activeEngineName()` reports its head, so
/// its ordering is what a benchmark or a chain edit would silently break — proven here with no
/// engine installed. The live SpeechAnalyzer transcription path needs its macOS 26 model assets
/// installed and is exercised by hand (docs/testing.md); this is the pure logic.
final class SpeechAnalyzerTests: XCTestCase {
    func testFullChainOrder() {
        XCTAssertEqual(
            Transcribers.chainOrder(parakeetWarm: true, parakeet: true, whisper: true, speechAnalyzer: true),
            ["Parakeet (warm)", "Parakeet", "whisper.cpp", "Apple SpeechAnalyzer", "Apple Speech"])
    }

    func testFloorAlwaysPresentAndLast() {
        let none = Transcribers.chainOrder(parakeetWarm: false, parakeet: false, whisper: false, speechAnalyzer: false)
        XCTAssertEqual(none, ["Apple Speech"], "the install-free floor is never absent")
        for order in [
            Transcribers.chainOrder(parakeetWarm: true, parakeet: false, whisper: false, speechAnalyzer: false),
            Transcribers.chainOrder(parakeetWarm: false, parakeet: false, whisper: false, speechAnalyzer: true),
            Transcribers.chainOrder(parakeetWarm: true, parakeet: true, whisper: true, speechAnalyzer: true),
        ] {
            XCTAssertEqual(order.last, "Apple Speech", "Apple Speech is always the last resort")
        }
    }

    func testSpeechAnalyzerSitsBelowWhisperAndAboveTheFloor() {
        // The spec's placement: SpeechAnalyzer above the legacy SFSpeechRecognizer floor, below whisper.cpp.
        let order = Transcribers.chainOrder(parakeetWarm: false, parakeet: false, whisper: true, speechAnalyzer: true)
        XCTAssertEqual(order, ["whisper.cpp", "Apple SpeechAnalyzer", "Apple Speech"])
        let w = order.firstIndex(of: "whisper.cpp")!
        let sa = order.firstIndex(of: "Apple SpeechAnalyzer")!
        let floor = order.firstIndex(of: "Apple Speech")!
        XCTAssertTrue(w < sa && sa < floor, "whisper.cpp > SpeechAnalyzer > Apple Speech")
    }

    func testSpeechAnalyzerAloneIsTheZeroDownloadTierAboveTheFloor() {
        // On a Mac with only the SpeechAnalyzer assets installed, it becomes the active engine —
        // a better-than-legacy on-device tier with no third-party download.
        let order = Transcribers.chainOrder(parakeetWarm: false, parakeet: false, whisper: false, speechAnalyzer: true)
        XCTAssertEqual(order, ["Apple SpeechAnalyzer", "Apple Speech"])
        XCTAssertEqual(order.first, "Apple SpeechAnalyzer")
    }

    func testAbsentSpeechAnalyzerDropsCleanlyToTheFloor() {
        let order = Transcribers.chainOrder(parakeetWarm: false, parakeet: false, whisper: false, speechAnalyzer: false)
        XCTAssertFalse(order.contains("Apple SpeechAnalyzer"), "absent when its assets aren't installed")
        XCTAssertEqual(order.first, "Apple Speech")
    }
}
