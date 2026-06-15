import AppKit
import Carbon.HIToolbox

/// Grabs the current selection in whatever app is frontmost by briefly
/// borrowing the clipboard: save it, synthesize ⌘C, read, restore.
/// Posting key events needs the Accessibility permission — we prompt once.
enum SelectionGrabber {
    static func grab(completion: @escaping (String?) -> Void) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            completion(nil)
            return
        }

        let pb = NSPasteboard.general
        let savedItems: [[NSPasteboard.PasteboardType: Data]] = (pb.pasteboardItems ?? []).map { item in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { copy[type] = data }
            }
            return copy
        }
        let before = pb.changeCount

        postCmdC()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            let text = pb.changeCount != before ? pb.string(forType: .string) : nil
            // Restore whatever the user had on the clipboard.
            pb.clearContents()
            let restored = savedItems.map { dict -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in dict { item.setData(data, forType: type) }
                return item
            }
            if !restored.isEmpty { pb.writeObjects(restored) }
            completion(text)
        }
    }

    private static func postCmdC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
