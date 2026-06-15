import ApplicationServices
import Foundation

/// Watches the field you dictated into for a few seconds after a paste. If you fix the spelling
/// of a single word that dictado typed (an in-place swap, e.g. "Miele" → "Myela"), it surfaces
/// that as a correction to learn. Everything is local: it reads the field's text via Accessibility
/// only to diff it, and only the corrected word PAIR is ever kept (on your OK) — never the
/// surrounding text. If the focused app doesn't expose its text to Accessibility, this does
/// nothing (no pill), so it degrades cleanly.
final class CorrectionListener {
    private var timer: Timer?
    private var element: AXUIElement?
    private var baseline: [String] = []     // field words right after the paste landed
    private var pasted: Set<String> = []    // lowercased words we inserted (only correct OUR output)
    private var deadline = Date.distantPast
    private var onDetect: ((String, String) -> Void)?

    /// Begin watching. Returns false if there's nothing watchable (AX text unavailable) so the
    /// caller knows not to bother. `onDetect(from, to)` fires at most once, on the main queue.
    @discardableResult
    func start(pasted text: String, onDetect: @escaping (String, String) -> Void) -> Bool {
        stop()
        guard AXIsProcessTrusted(),
              let el = Self.focusedElement(),
              let value = Self.value(of: el) else { return false }
        let words = Self.words(text).map { $0.lowercased() }
        guard !words.isEmpty else { return false }
        element = el
        baseline = Self.words(value)
        pasted = Set(words)
        self.onDetect = onDetect
        deadline = Date().addingTimeInterval(8)
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in self?.poll() }
        return true
    }

    func stop() {
        timer?.invalidate(); timer = nil
        element = nil; onDetect = nil; baseline = []; pasted = []
    }

    private func poll() {
        guard let el = element else { stop(); return }
        if Date() > deadline { stop(); return }
        guard let cur = Self.value(of: el) else { return }
        let current = Self.words(cur)
        guard let (from, to) = Self.detectCorrection(baseline: baseline, current: current, pasted: pasted) else { return }
        let cb = onDetect
        stop()
        cb?(from, to)
    }

    // MARK: Accessibility

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var el: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &el) == .success,
              let e = el else { return nil }
        return (e as! AXUIElement)
    }

    private static func value(of el: AXUIElement) -> String? {
        var v: AnyObject?
        guard AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &v) == .success else { return nil }
        return v as? String
    }

    // MARK: diff

    static func words(_ s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: "[A-Za-z][A-Za-z']*", options: []) else { return [] }
        let range = NSRange(s.startIndex..., in: s)
        return re.matches(in: s, range: range).compactMap {
            Range($0.range, in: s).map { String(s[$0]) }
        }
    }

    /// The edit between `baseline` (right after paste) and `current` (after you typed) is a
    /// correction only when EXACTLY one distinct word was removed and one added, the removed word
    /// was something we typed, and the two are spelling-close. Conservative on purpose — it should
    /// never learn a rephrase or a new sentence.
    static func detectCorrection(baseline: [String], current: [String], pasted: Set<String>) -> (String, String)? {
        let before = Set(baseline.map { $0.lowercased() })
        let after = Set(current.map { $0.lowercased() })
        let removed = before.subtracting(after)
        let added = after.subtracting(before)
        guard removed.count == 1, added.count == 1,
              let fromL = removed.first, let toL = added.first,
              pasted.contains(fromL),               // only fix words WE produced
              fromL.count >= 2, toL.count >= 2 else { return nil }
        let dist = levenshtein(fromL, toL)
        let maxLen = max(fromL.count, toL.count)
        guard dist >= 1, dist <= max(2, Int(ceil(Double(maxLen) * 0.5))) else { return nil }
        // Return original casing for display + storage.
        let fromOrig = baseline.first { $0.lowercased() == fromL } ?? fromL
        let toOrig = current.first { $0.lowercased() == toL } ?? toL
        return (fromOrig, toOrig)
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        var cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                cur[j] = x[i - 1] == y[j - 1]
                    ? prev[j - 1]
                    : Swift.min(prev[j - 1], prev[j], cur[j - 1]) + 1
            }
            swap(&prev, &cur)
        }
        return prev[y.count]
    }
}
