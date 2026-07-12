import ApplicationServices
import Foundation

/// The app's ONE focused-field Accessibility read, plus the correction-diff helpers — static
/// only, nothing here runs on its own. Two consumers share this file so a single discipline
/// governs both: `ContextAwareness.captureLive` (the opt-in context capture) uses the AX read,
/// and `KeystrokeLearner` (the live learn-from-edits mechanism — see its header) uses the
/// word/diff helpers to judge its keystroke shadow. This type's original AX-poll watcher — a
/// timer re-reading the field after a paste — was never wired into the app and has been deleted;
/// KeystrokeLearner is the one and only learn-from-edits watcher.
enum CorrectionListener {
    // MARK: Accessibility
    // Internal (not private) on purpose: ContextAwareness.captureLive reuses this exact
    // focused-field read rather than growing a second AX surface — one place in the app
    // reads focused text, with one discipline.

    static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var el: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &el) == .success,
              let e = el, CFGetTypeID(e) == AXUIElementGetTypeID() else { return nil }
        return (e as! AXUIElement)
    }

    /// Read the focused text as robustly as we can — many apps (incl. terminals like Ghostty) don't
    /// put the text on the focused element's AXValue directly, so fall back to its selected text and
    /// then to a text-bearing descendant. This is what lets edit-watching work beyond simple fields.
    static func value(of el: AXUIElement) -> String? {
        if let s = stringAttr(el, kAXValueAttribute), !s.isEmpty { return s }
        if let s = stringAttr(el, kAXSelectedTextAttribute), !s.isEmpty { return s }
        return firstTextValue(in: el, depth: 0)
    }

    static func stringAttr(_ el: AXUIElement, _ attr: String) -> String? {
        var v: AnyObject?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }

    /// Depth-bounded hunt for an AXTextArea/AXTextField descendant that exposes a value (terminals
    /// and many custom views nest their editable text below the "focused" container).
    private static func firstTextValue(in el: AXUIElement, depth: Int) -> String? {
        guard depth < 4 else { return nil }
        var childrenRef: AnyObject?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }
        for child in children.prefix(24) {
            let role = stringAttr(child, kAXRoleAttribute)
            if role == (kAXTextAreaRole as String) || role == (kAXTextFieldRole as String),
               let s = stringAttr(child, kAXValueAttribute), !s.isEmpty { return s }
            if let s = firstTextValue(in: child, depth: depth + 1) { return s }
        }
        return nil
    }

    /// Diagnostic for `--axprobe`: describe the frontmost app's focused element + whether warble can
    /// read text from it (used to figure out edit-watching support in a given app, e.g. a terminal).
    static func probe() -> String {
        guard AXIsProcessTrusted() else { return "accessibility: NOT granted — grant warble first" }
        guard let el = focusedElement() else { return "no focused UI element (click into a text area, then re-run)" }
        let role = stringAttr(el, kAXRoleAttribute) ?? "?"
        let sub = stringAttr(el, kAXSubroleAttribute) ?? "-"
        var lines = ["focused role=\(role) subrole=\(sub)"]
        if let v = stringAttr(el, kAXValueAttribute) { lines.append("AXValue: \(v.count) chars — \"\(snippet(v))\"") }
        else { lines.append("AXValue: (none)") }
        if let s = stringAttr(el, kAXSelectedTextAttribute), !s.isEmpty { lines.append("AXSelectedText: \"\(snippet(s))\"") }
        if let d = firstTextValue(in: el, depth: 0) { lines.append("descendant text: \(d.count) chars — \"\(snippet(d))\"") }
        let readable = value(of: el) != nil
        lines.append(readable ? "→ warble CAN read text here (edit-watching should work)" : "→ warble CANNOT read text here (edit-watching won't work in this app)")
        return lines.joined(separator: "\n")
    }

    private static func snippet(_ s: String) -> String {
        let one = s.replacingOccurrences(of: "\n", with: "⏎").trimmingCharacters(in: .whitespaces)
        return one.count > 80 ? String(one.prefix(80)) + "…" : one
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
