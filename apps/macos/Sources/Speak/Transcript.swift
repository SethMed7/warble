import AppKit

/// The read-along text view. Not selectable — a click anywhere jumps playback to that selection
/// (so you can skip around), while the enclosing scroll view still scrolls freely with the wheel.
final class TranscriptTextView: NSTextView {
    var onPick: ((Int) -> Void)?
    var segmentRanges: [NSRange] = []

    override func mouseDown(with event: NSEvent) {
        guard let lm = layoutManager, let tc = textContainer else { return }
        var p = convert(event.locationInWindow, from: nil)
        p.x -= textContainerInset.width
        p.y -= textContainerInset.height
        let idx = lm.characterIndex(for: p, in: tc, fractionOfDistanceBetweenInsertionPoints: nil)
        if let seg = segmentRanges.firstIndex(where: { NSLocationInRange(idx, $0) }) { onPick?(seg) }
        // No super call: clicking skips, it doesn't place a caret or select.
    }
}
