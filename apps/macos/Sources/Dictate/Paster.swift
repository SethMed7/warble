import AppKit
import Carbon.HIToolbox

/// Types cleaned text into the focused app by briefly borrowing the
/// clipboard: save it, set the text, synthesize ⌘V, restore. Posting key
/// events needs the Accessibility permission — we prompt once.
enum Paster {
    /// Returns false when Accessibility is denied; the text is left on the
    /// clipboard (unrestored) so the user can paste it themselves.
    @discardableResult
    static func paste(_ text: String) -> Bool {
        let pb = NSPasteboard.general
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            pb.clearContents()
            pb.setString(text, forType: .string)
            return false
        }

        let savedItems: [[NSPasteboard.PasteboardType: Data]] = (pb.pasteboardItems ?? []).map { item in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { copy[type] = data }
            }
            return copy
        }

        pb.clearContents()
        pb.setString(text, forType: .string)
        postCmdV()

        // Restore whatever the user had on the clipboard once ⌘V has landed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            pb.clearContents()
            let restored = savedItems.map { dict -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in dict { item.setData(data, forType: type) }
                return item
            }
            if !restored.isEmpty { pb.writeObjects(restored) }
        }
        return true
    }

    private static func postCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
