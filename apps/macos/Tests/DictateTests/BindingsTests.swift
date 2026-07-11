import XCTest
import Carbon.HIToolbox
@testable import Dictate

/// Multi-shortcut + mouse bindings (ROADMAP 0.5): the binding model's pure halves — spec
/// parse/format round-trips, the reserved/conflict rejections (each with its plain reason), the
/// load-time hygiene for the defaults seam, and the event-matching facts HotKey routes real
/// events with. No monitors, no events, no UI. The store's cross-process persistence is proven
/// end to end by regression.sh's `bindings` check; the live tap is by-hand (docs/testing.md).
final class BindingsTests: XCTestCase {
    // MARK: spec round-trips — every expressible trigger and gesture

    func testEveryTriggerAndGestureRoundTripsThroughItsSpec() {
        for trigger in BindingTrigger.allCases {
            for gesture in BindingGesture.allCases {
                let b = DictationBinding(trigger: trigger, gesture: gesture)
                XCTAssertEqual(Bindings.parse(b.spec), .ok(b), "spec \"\(b.spec)\" should round-trip")
            }
        }
    }

    func testSpecsAndDisplayNamesAreStable() {
        XCTAssertEqual(BindingTrigger.rightCommand.spec, "right-command")
        XCTAssertEqual(BindingTrigger.rightOption.spec, "right-option")
        XCTAssertEqual(BindingTrigger.fkey(13).spec, "f13")
        XCTAssertEqual(BindingTrigger.mouse(4).spec, "mouse-4")
        XCTAssertEqual(BindingTrigger.rightCommand.display, "right ⌘")
        XCTAssertEqual(BindingTrigger.rightOption.display, "right ⌥")
        XCTAssertEqual(BindingTrigger.fkey(19).display, "F19")
        XCTAssertEqual(BindingTrigger.mouse(3).display, "mouse button 3 (middle)")
        XCTAssertEqual(BindingTrigger.mouse(4).display, "mouse button 4")
        XCTAssertEqual(BindingGesture.hold.display, "hold to talk")
        XCTAssertEqual(BindingGesture.doubleTap.display, "double-tap to toggle")
    }

    func testParseIsCaseInsensitive() {
        XCTAssertEqual(Bindings.parse("Right-Command:HOLD"),
                       .ok(DictationBinding(trigger: .rightCommand, gesture: .hold)))
        XCTAssertEqual(Bindings.parse("F13:Double-Tap"),
                       .ok(DictationBinding(trigger: .fkey(13), gesture: .doubleTap)))
    }

    // MARK: rejections — reserved combos and garbage, each with a plain reason

    private func reason(_ spec: String) -> String? {
        if case .bad(let r) = Bindings.parse(spec) { return r }
        return nil
    }

    func testReservedTriggersAreRejectedWithPlainReasons() {
        XCTAssertTrue(reason("fn:hold")?.contains("built in") == true, "Fn can't be re-bound")
        XCTAssertTrue(reason("esc:hold")?.contains("Esc cancels") == true, "Esc is the cancel key")
        XCTAssertTrue(reason("mouse-1:hold")?.contains("your Mac's own clicks") == true)
        XCTAssertTrue(reason("mouse-2:double-tap")?.contains("your Mac's own clicks") == true)
        XCTAssertTrue(reason("mouse-11:hold")?.contains("pick button 3–10") == true)
        XCTAssertTrue(reason("f12:hold")?.contains("F13–F19") == true, "lower F-keys belong to macOS")
        XCTAssertTrue(reason("f20:hold")?.contains("F13–F19") == true)
    }

    func testGarbageIsRejectedNotCrashed() {
        XCTAssertNotNil(reason(""), "empty spec")
        XCTAssertNotNil(reason("right-command"), "no gesture")
        XCTAssertNotNil(reason("ctrl-v:hold"), "the read-aloud key can't be expressed")
        XCTAssertNotNil(reason("right-command:triple-tap"), "unknown gesture")
        XCTAssertNotNil(reason("f:hold"), "not an F-key number")
        XCTAssertNotNil(reason("mouse-:hold"), "not a button number")
    }

    // MARK: add validation — duplicates and the cap (the dashboard's exact path)

    func testDuplicateAddIsRejected() {
        let b = DictationBinding(trigger: .rightCommand, gesture: .hold)
        let reason = Bindings.rejectionReason(adding: b, to: [b])
        XCTAssertTrue(reason?.contains("already bound") == true)
    }

    func testSameTriggerOtherGestureIsAllowed() {
        // One key, both gestures — exactly Fn's own shape; timing disambiguates (HotKey).
        let hold = DictationBinding(trigger: .rightCommand, gesture: .hold)
        let tap = DictationBinding(trigger: .rightCommand, gesture: .doubleTap)
        XCTAssertNil(Bindings.rejectionReason(adding: tap, to: [hold]))
    }

    func testCapIsEnforced() {
        let three: [DictationBinding] = [
            .init(trigger: .rightCommand, gesture: .hold),
            .init(trigger: .fkey(13), gesture: .hold),
            .init(trigger: .mouse(4), gesture: .doubleTap),
        ]
        let reason = Bindings.rejectionReason(adding: .init(trigger: .fkey(14), gesture: .hold), to: three)
        XCTAssertTrue(reason?.contains("up to 3") == true)
        XCTAssertNil(Bindings.rejectionReason(adding: .init(trigger: .fkey(14), gesture: .hold),
                                              to: Array(three.prefix(2))))
    }

    // MARK: decode — the defaults seam's load-time hygiene

    func testDecodeDropsInvalidDedupesAndCaps() {
        XCTAssertEqual(Bindings.decode([]), [])
        XCTAssertEqual(Bindings.decode(["garbage", "mouse-2:hold", "esc:hold", "f5:hold"]), [],
                       "a hand-planted invalid array degrades to Fn-only, never wedges the tap")
        XCTAssertEqual(Bindings.decode(["right-command:hold", "right-command:hold"]),
                       [DictationBinding(trigger: .rightCommand, gesture: .hold)], "exact repeats dedupe")
        XCTAssertEqual(Bindings.decode(["right-command:hold", "f13:hold", "mouse-4:hold", "f14:hold"]).count,
                       Bindings.maxExtra, "over the cap: the valid prefix wins")
        XCTAssertEqual(Bindings.decode(["garbage", "right-command:double-tap"]),
                       [DictationBinding(trigger: .rightCommand, gesture: .doubleTap)],
                       "valid entries survive their invalid neighbors")
    }

    // MARK: event matching — the facts HotKey routes real events with

    func testFKeyKeyCodesMatchCarbon() {
        XCTAssertEqual(BindingTrigger.fkey(13).fkeyKeyCode, UInt16(kVK_F13))
        XCTAssertEqual(BindingTrigger.fkey(14).fkeyKeyCode, UInt16(kVK_F14))
        XCTAssertEqual(BindingTrigger.fkey(15).fkeyKeyCode, UInt16(kVK_F15))
        XCTAssertEqual(BindingTrigger.fkey(16).fkeyKeyCode, UInt16(kVK_F16))
        XCTAssertEqual(BindingTrigger.fkey(17).fkeyKeyCode, UInt16(kVK_F17))
        XCTAssertEqual(BindingTrigger.fkey(18).fkeyKeyCode, UInt16(kVK_F18))
        XCTAssertEqual(BindingTrigger.fkey(19).fkeyKeyCode, UInt16(kVK_F19))
        XCTAssertNil(BindingTrigger.rightCommand.fkeyKeyCode)
        XCTAssertNil(BindingTrigger.mouse(4).fkeyKeyCode)
    }

    func testMouseButtonNumbersAreZeroBased() {
        // User-facing button N is NSEvent.buttonNumber N−1: button 3 is the middle button (2).
        XCTAssertEqual(BindingTrigger.mouse(3).mouseButtonNumber, 2)
        XCTAssertEqual(BindingTrigger.mouse(4).mouseButtonNumber, 3)
        XCTAssertEqual(BindingTrigger.mouse(10).mouseButtonNumber, 9)
        XCTAssertNil(BindingTrigger.rightCommand.mouseButtonNumber)
        XCTAssertNil(BindingTrigger.fkey(13).mouseButtonNumber)
    }

    func testModifierTriggersCarryTheirFlagsAndDeviceBits() {
        XCTAssertTrue(BindingTrigger.rightCommand.isModifier)
        XCTAssertTrue(BindingTrigger.rightOption.isModifier)
        XCTAssertFalse(BindingTrigger.fkey(13).isModifier)
        XCTAssertFalse(BindingTrigger.mouse(4).isModifier)
        XCTAssertEqual(BindingTrigger.rightCommand.modifierFlag, .command)
        XCTAssertEqual(BindingTrigger.rightOption.modifierFlag, .option)
        XCTAssertEqual(BindingTrigger.rightCommand.deviceBit, 0x0010) // NX_DEVICERCMDKEYMASK
        XCTAssertEqual(BindingTrigger.rightOption.deviceBit, 0x0040)  // NX_DEVICERALTKEYMASK
        XCTAssertNil(BindingTrigger.fkey(13).deviceBit)
        XCTAssertNil(BindingTrigger.mouse(4).deviceBit)
    }

    // MARK: persistence round-trip — this test process's own defaults domain, saved and restored

    private var savedBindings: [String]?
    override func setUp() {
        super.setUp()
        savedBindings = UserDefaults.standard.stringArray(forKey: Bindings.defaultsKey)
    }
    override func tearDown() {
        if let savedBindings {
            UserDefaults.standard.set(savedBindings, forKey: Bindings.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Bindings.defaultsKey)
        }
        super.tearDown()
    }

    func testStoreRoundTripsThroughUserDefaults() {
        UserDefaults.standard.removeObject(forKey: Bindings.defaultsKey)
        let store = Bindings()
        XCTAssertEqual(store.list, [], "default = Fn only (nothing stored)")
        XCTAssertEqual(store.add("right-command:hold"),
                       .added(DictationBinding(trigger: .rightCommand, gesture: .hold)))
        XCTAssertEqual(store.add("mouse-4:double-tap"),
                       .added(DictationBinding(trigger: .mouse(4), gesture: .doubleTap)))
        let reread = Bindings() // a fresh load, as the next process would see it
        XCTAssertEqual(reread.list, store.list)
        XCTAssertTrue(reread.remove(DictationBinding(trigger: .mouse(4), gesture: .doubleTap)))
        XCTAssertFalse(reread.remove(DictationBinding(trigger: .mouse(4), gesture: .doubleTap)), "already gone")
        XCTAssertEqual(Bindings().list, [DictationBinding(trigger: .rightCommand, gesture: .hold)])
    }

    // MARK: teardown law — a test binary must never leave a monitor installed

    func testHotKeyRegisterUnregisterLeavesNothingBehind() {
        let hk = HotKey.shared
        XCTAssertFalse(hk.isRegistered, "nothing installed before the test touches it")
        hk.register()
        hk.register() // idempotent: never stacks monitors
        XCTAssertTrue(hk.isRegistered)
        hk.unregister()
        XCTAssertFalse(hk.isRegistered, "unregister tears every monitor down")
    }
}
