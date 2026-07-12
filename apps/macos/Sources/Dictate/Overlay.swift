import AppKit
import Shared

/// The hover-revealed gesture line (ROADMAP 0.4 "hover the pill → shows the hotkey"):
/// discoverability without a manual. Pure copy — unit-tested in DictateTests.
enum PillHint {
    /// While the mic is hot: the gesture that's driving it right now.
    static func listening(handsFree: Bool) -> String {
        handsFree ? "double-tap Fn to stop · Esc cancels" : "hold Fn · Esc cancels"
    }
    /// While transcribe/polish runs: the one act still available.
    static let processing = "Esc cancels"
    /// The resting states (landed / clipboard / error pills): the gesture to go again.
    static let idle = "hold Fn to dictate"
    /// The landed pill's read-back affordance (ROADMAP 0.5) — shown only while the transient ⌃R
    /// claim is actually armed, so the pill never advertises a dead key.
    static let readBack = "⌃R to hear it back"
}

/// The small, bottom-centered dictation indicator. Recording shows ONLY a live blue waveform that
/// moves with your voice — no text, no wordmark. On release the waveform goes flat and a spinner
/// appears to its right (processing); when the text lands, the spinner becomes a brief electric
/// checkmark, then the pill is gone (transient by default). Hovering any pill widens it to show
/// the active gesture. Error/clipboard states use a tiny text pill. Non-activating, so focus
/// stays in the app you're dictating into.
final class Overlay {
    static let shared = Overlay()

    private var panel: NSPanel?
    private var stackView: NSStackView?
    private var waveformView: MicWaveformView?
    private var spinner: Spinner?
    private var warnLabel: NSTextField? // the hold-cap countdown, updated in place each second
    private var hintLabel: NSTextField? // the hover-revealed gesture hint (built per state, shown on hover)
    private var autoCloseWork: DispatchWorkItem?
    private var hovering = false

    /// The wave pill's honest phases (DESIGN.md motion law): listening = bars react to the mic,
    /// processing = bars flat + spinner spins, landed = checkmark, no motion at all.
    private enum WaveState { case listening, processing, landed }
    private var waveState: WaveState?
    private var capText: String?   // the hold-cap countdown, when active
    private var landedNote: String? // auto-send confirmation ("sent — said 'press enter'"), when it fired
    private var readBackHint = false // "⌃R to hear it back" joins the landed pill while the claim is armed
    private var handsFree = false  // shapes the listening hint (hold vs double-tap)

    // Tokens from Shared/Theme — one canon (brand/tokens.md), no local literals.
    private let textHi = Theme.textHi.ns
    private let blue = Theme.electric.ns   // electric blue — the live waveform, accents
    private let muted = Theme.mist.ns
    private let bg = Theme.pillSurface.ns  // canon ink at 97% — the floating-capsule surface
    private let stroke = Theme.line.ns
    private let electricText = Theme.electricText.ns // the accent's AA-safe small-text tint
    private let warn = Theme.warn.ns       // true failures only, always with a glyph (DESIGN.md)

    private let pillHeight: CGFloat = 32
    private let waveSize = CGSize(width: 64, height: 20)

    // MARK: states

    /// Recording — a small rounded pill that is just the live waveform, reacting to your voice.
    func showListening(handsFree: Bool = false) {
        self.handsFree = handsFree
        waveState = .listening
        capText = nil
        landedNote = nil
        readBackHint = false
        mountWave()
    }

    /// Feed the live mic level (0…1) to the recording waveform. No-op otherwise.
    func updateLevel(_ level: Float) { waveformView?.setLevel(CGFloat(level)) }

    /// Released — the waveform goes flat and a spinner spins on the right while we transcribe + polish.
    func showThinking() {
        waveState = .processing
        capText = nil
        landedNote = nil
        readBackHint = false
        mountWave()
    }

    /// Long-session warning (ROADMAP 0.3): the countdown to the hold cap. The mic is still hot, so
    /// the waveform keeps reacting (motion stays honest) — the pill just widens to carry a warn
    /// glyph + countdown so the coming stop is never a surprise. Repeated ticks update the label
    /// in place (monospaced digits — no width wobble).
    func showCapCountdown(secondsLeft: Int) {
        let text = String(format: "stops in %d:%02d", secondsLeft / 60, secondsLeft % 60)
        capText = text
        if let warnLabel, waveState == .listening { warnLabel.stringValue = text; return }
        waveState = .listening
        mountWave()
    }

    /// Pasted — the spinner becomes a brief electric checkmark (success is a glyph, never a color —
    /// DESIGN.md), then the pill is gone. Motion stops the instant processing ends: the spinner is
    /// removed, the bars are already flat, nothing loops during the confirmation. `note` names an
    /// action the checkmark alone can't explain (currently just auto-send: "sent — said 'press
    /// enter'") — DESIGN.md's success rule ("a checkmark glyph beside text-hi text"), so the
    /// behavior it confirms is never mysterious (ROADMAP 0.5). `readBackHint` adds the quiet
    /// "⌃R to hear it back" affordance (electric-text — the ⌘V-to-paste idiom) while the
    /// transient read-back claim is armed; the note wins when both apply (one message at a time —
    /// ⌃R still works, the menu item stays discoverable).
    func showLanded(note: String? = nil, readBackHint: Bool = false) {
        waveState = .landed
        capText = nil
        landedNote = note
        self.readBackHint = readBackHint && note == nil
        mountWave()
        // A brief blink when it's just the checkmark; text needs a moment longer to actually read.
        autoClose(after: note == nil && !self.readBackHint ? 0.6 : 1.6)
    }

    /// Accessibility denied: text is on the clipboard. Tell the user to paste it.
    func showCopied(_ text: String) {
        presentText("⌘V to paste", detail: oneLine(text))
        autoClose(after: 3.0)
    }

    func flash(message: String) {
        presentText(message, detail: nil)
        autoClose(after: 1.4)
    }

    /// A true failure: the named cause in warn, paired with a glyph so color is never the only
    /// signal (warn is the single declared exception to the one-accent law — DESIGN.md). Dwell is
    /// longer than a notice so the cause can actually be read.
    func flashError(message: String) {
        presentText(message, detail: nil, error: true)
        autoClose(after: 2.6)
    }

    func close() {
        autoCloseWork?.cancel(); autoCloseWork = nil
        spinner = nil
        warnLabel = nil
        hintLabel = nil
        stackView = nil
        waveState = nil
        capText = nil
        landedNote = nil
        readBackHint = false
        hovering = false
        panel?.orderOut(nil); panel = nil
        waveformView = nil
    }

    // MARK: waveform pill (recording → cap warning → processing → landed)

    private func mountWave() {
        autoCloseWork?.cancel(); autoCloseWork = nil
        guard let built = waveContent() else { return }
        install(content: built.view, width: built.width, height: pillHeight)
        syncHover()
    }

    /// Build the wave pill's content for the current state. Shared verbatim by the live mount and
    /// the DEBUG --render-pill seam, so the QA PNGs are the exact pixels users see.
    private func waveContent() -> (view: NSView, width: CGFloat)? {
        guard let state = waveState else { return nil }

        // Recording starts a fresh waveform; the cap warning, processing, and landed reuse it so
        // the bars carry over with continuity (still live under the warning, easing flat after).
        let wf: MicWaveformView
        if let existing = waveformView, state != .listening || capText != nil {
            wf = existing
        } else {
            wf = MicWaveformView(bars: 7)
            wf.barColor = blue
        }
        if state != .listening { wf.goFlat() } // motion stops the instant listening ends
        wf.translatesAutoresizingMaskIntoConstraints = false
        wf.removeFromSuperview()
        waveformView = wf

        var views: [NSView] = [wf]
        var cons = [
            wf.widthAnchor.constraint(equalToConstant: waveSize.width),
            wf.heightAnchor.constraint(equalToConstant: waveSize.height),
        ]
        var width: CGFloat = 12 + waveSize.width

        if state == .listening, let capText {
            // Warn + glyph (DESIGN.md: color is never the only signal) beside the live waveform.
            let icon = NSImageView()
            icon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "warning")?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
            icon.contentTintColor = warn
            icon.translatesAutoresizingMaskIntoConstraints = false
            let l = label(capText, size: 12, weight: .medium, color: warn)
            l.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            warnLabel = l
            views += [icon, l]
            width += 8 + 14 + 8 + l.intrinsicContentSize.width
            cons += [icon.widthAnchor.constraint(equalToConstant: 14),
                     icon.heightAnchor.constraint(equalToConstant: 14)]
        } else {
            warnLabel = nil
        }

        switch state {
        case .listening:
            spinner = nil
            width += 12
        case .processing:
            let s = Spinner(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
            s.color = blue
            s.translatesAutoresizingMaskIntoConstraints = false
            spinner = s
            views.append(s)
            width += 8 + 16 + 10
            cons += [s.widthAnchor.constraint(equalToConstant: 16),
                     s.heightAnchor.constraint(equalToConstant: 16)]
        case .landed:
            spinner = nil
            let check = NSImageView()
            check.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "landed")?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .bold))
            check.contentTintColor = blue
            check.translatesAutoresizingMaskIntoConstraints = false
            views.append(check)
            width += 8 + 16 + 10
            cons += [check.widthAnchor.constraint(equalToConstant: 16),
                     check.heightAnchor.constraint(equalToConstant: 16)]
            // Auto-send confirmation (ROADMAP 0.5): "a checkmark glyph (electric) beside text-hi
            // text" is DESIGN.md's own success rule — this is that text, added only when it fired.
            if let landedNote {
                let l = label(landedNote, size: 12, weight: .medium, color: textHi)
                views.append(l)
                width += 8 + l.intrinsicContentSize.width
            }
            // Read-back affordance (ROADMAP 0.5): the quiet "hear it back" line beside the
            // checkmark, electric-text like the "⌘V to paste" copy — only while ⌃R is armed.
            if readBackHint {
                let l = label(PillHint.readBack, size: 12, weight: .medium, color: electricText)
                views.append(l)
                width += 8 + l.intrinsicContentSize.width
            }
        }

        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: state == .listening ? 12 : 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stackView = stack

        let content = makeCapsule(width: width, height: pillHeight)
        content.addSubview(stack)
        cons += [
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ]
        NSLayoutConstraint.activate(cons)

        switch state {
        case .listening: hintLabel = makeHint(PillHint.listening(handsFree: handsFree))
        case .processing: hintLabel = makeHint(PillHint.processing)
        case .landed: hintLabel = makeHint(PillHint.idle)
        }
        return (content, width)
    }

    // MARK: text pill (errors / clipboard fallback)

    private func presentText(_ message: String, detail: String?, error: Bool = false) {
        close()
        let built = textContent(message, detail: detail, error: error)
        install(content: built.view, width: built.width, height: pillHeight)
        syncHover()
    }

    /// Build a text pill's content — shared by the live mount and the DEBUG render seam.
    private func textContent(_ message: String, detail: String?, error: Bool) -> (view: NSView, width: CGFloat) {
        let hasDetail = detail != nil && !(detail!.isEmpty)
        let msg = label(message, size: 12, weight: .medium, color: error ? warn : (hasDetail ? electricText : muted))
        var views: [NSView] = [msg]
        if error { // failures pair the warn copy with a glyph — color is never the only signal
            let icon = NSImageView()
            icon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "error")?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
            icon.contentTintColor = warn
            icon.translatesAutoresizingMaskIntoConstraints = false
            views.insert(icon, at: 0)
        }
        if hasDetail {
            let d = label(detail!, size: 12, weight: .regular, color: textHi)
            d.maximumNumberOfLines = 1
            d.lineBreakMode = .byTruncatingTail
            d.setContentHuggingPriority(.defaultLow, for: .horizontal)
            d.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            views.append(d)
        }
        let width: CGFloat = hasDetail ? 460 : max(120, msg.intrinsicContentSize.width + 34 + (error ? 22 : 0))
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = error ? 8 : 12
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stackView = stack
        let content = makeCapsule(width: width, height: pillHeight)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
        hintLabel = makeHint(PillHint.idle)
        return (content, width)
    }

    // MARK: the hover hint — the pill widens to carry the gesture, the warn-label idiom

    private func makeHint(_ text: String?) -> NSTextField? {
        guard let text else { return nil }
        let l = label(text, size: 12, weight: .medium, color: muted)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }

    private func setHovering(_ inside: Bool) {
        guard inside != hovering else { return }
        hovering = inside
        applyHint()
    }

    /// A (re)mount replaces the tracked view, so recompute "is the pointer on the pill" from
    /// scratch instead of trusting a stale enter/exit pair.
    private func syncHover() {
        hovering = panel.map { $0.frame.contains(NSEvent.mouseLocation) } ?? false
        applyHint()
    }

    /// Reveal or retract the gesture hint: the label joins the capsule's stack and the pill
    /// widens around its center — no remount, so live waveforms and auto-close timers carry on.
    private func applyHint() {
        guard let panel, let stack = stackView, let hintLabel else { return }
        let want = hovering
        let shown = hintLabel.superview != nil
        guard want != shown else { return }
        let extra = 8 + ceil(hintLabel.intrinsicContentSize.width) + 4
        var frame = panel.frame
        if want {
            stack.addArrangedSubview(hintLabel)
            frame.origin.x -= extra / 2
            frame.size.width += extra
        } else {
            hintLabel.removeFromSuperview()
            frame.origin.x += extra / 2
            frame.size.width -= extra
        }
        panel.setFrame(frame, display: true, animate: false)
    }

    // MARK: plumbing

    private func makeCapsule(width: CGFloat, height: CGFloat) -> NSView {
        let content = CapsuleView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        content.fillColor = bg
        content.strokeColor = stroke
        content.onHover = { [weak self] inside in self?.setHovering(inside) }
        return content
    }

    /// Install content into the (reused) panel for a smooth recording→processing transition.
    private func install(content: NSView, width: CGFloat, height: CGFloat) {
        let origin: NSPoint
        if let screen = Self.activeScreen() {
            let f = screen.visibleFrame
            origin = NSPoint(x: f.midX - width / 2, y: f.minY + 28)
        } else {
            origin = .zero
        }
        if let p = panel {
            p.contentView = content
            p.setFrame(NSRect(origin: origin, size: CGSize(width: width, height: height)), display: true, animate: false)
            return
        }
        let p = NSPanel(contentRect: NSRect(origin: origin, size: CGSize(width: width, height: height)),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .floating
        p.contentView = content
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .transient]
        // Gentle pop-in: fade up with a small upward slide so the pill arrives, not blinks.
        p.alphaValue = 0
        p.setFrameOrigin(NSPoint(x: origin.x, y: origin.y - 10))
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1
            p.animator().setFrameOrigin(origin)
        }
        panel = p
    }

    private func autoClose(after seconds: TimeInterval) {
        autoCloseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.close() }
        autoCloseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    /// The screen the user is actually working on — the one under the pointer — so the pill appears
    /// near their context on multi-display setups, not always on the primary.
    static func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    private func oneLine(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.setContentHuggingPriority(.required, for: .horizontal)
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
        return l
    }
}

/// The pill's capsule surface. It DRAWS its fill/hairline (rather than styling a layer) so the
/// offscreen render seam captures exactly what users see, and it owns the pointer tracking that
/// reveals the gesture hint.
final class CapsuleView: NSView {
    var fillColor: NSColor = .black
    var strokeColor: NSColor = .white
    var onHover: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5) // hairline sits on the half-pixel — crisp at 1px
        let path = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
        fillColor.setFill()
        path.fill()
        strokeColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

#if DEBUG
/// The pill's UI-verification seam (`--render-pill <state> <out.png>`, DEBUG builds only):
/// rasterize any pill state offscreen at 2x — no panel, no window server ordering, no mic. The
/// content comes from the SAME builders the live pill mounts; only the live inputs (mic levels,
/// the spinner's animation) are frozen to representative fixtures so the snapshot is
/// deterministic. Asserted by scripts/regression.sh (check: listening).
extension Overlay {
    static let renderableStates = ["listening", "listening+hint", "listening+cap",
                                   "processing", "processing+hint", "landed", "landed+sent",
                                   "landed+readback", "copied", "error"]

    static func renderPill(_ state: String, to out: URL) {
        guard renderableStates.contains(state) else {
            FileHandle.standardError.write(Data("unknown pill state \"\(state)\" — states: \(renderableStates.joined(separator: " "))\n".utf8))
            exit(2)
        }
        let parts = state.split(separator: "+", maxSplits: 1)
        let base = String(parts[0])
        let variant = parts.count > 1 ? String(parts[1]) : ""

        Spinner.frozenForRender = true // a static arc draw() can capture, instead of a CA animation
        let o = Overlay()
        let content: NSView
        var width: CGFloat
        switch base {
        case "listening", "processing", "landed":
            o.waveState = base == "listening" ? .listening : (base == "processing" ? .processing : .landed)
            if variant == "cap" { o.capText = "stops in 0:59" }
            if variant == "sent" { o.landedNote = "sent — said 'press enter'" }
            if variant == "readback" { o.readBackHint = true }
            guard let built = o.waveContent() else { exit(1) }
            content = built.view
            width = built.width
            // A representative frame: the live ripple mid-speech, or the flat processing line.
            let live = (0..<7).map { (i: Int) -> CGFloat in
                let ripple = 0.5 + 0.5 * sin(CGFloat(i) * 1.15)
                return max(0.05, 0.85 * (0.40 + 0.60 * ripple))
            }
            o.waveformView?.freeze(levels: base == "listening" ? live : Array(repeating: 0.05, count: 7))
        case "copied":
            let built = o.textContent("⌘V to paste", detail: "so the quick brown fox jumps over the lazy dog", error: false)
            content = built.view
            width = built.width
        default: // error
            let built = o.textContent(DictateError.micBusy.message, detail: nil, error: true)
            content = built.view
            width = built.width
        }
        if variant == "hint", let hint = o.hintLabel, let stack = o.stackView {
            stack.addArrangedSubview(hint) // the hover reveal, injected
            width += 8 + ceil(hint.intrinsicContentSize.width) + 4
        }

        content.frame = NSRect(x: 0, y: 0, width: width, height: o.pillHeight)
        content.layoutSubtreeIfNeeded()
        let size = content.frame.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            FileHandle.standardError.write(Data("couldn't build the 2x bitmap\n".utf8))
            exit(1)
        }
        rep.size = size // 2x pixels over 1x points = @2x
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.cgContext.scaleBy(x: 2, y: 2) // the context alone doesn't map points onto the 2x pixels
        content.displayIgnoringOpacity(content.bounds, in: ctx)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]),
              (try? png.write(to: out)) != nil else {
            FileHandle.standardError.write(Data("couldn't write \(out.path)\n".utf8))
            exit(1)
        }
        print("rendered \(state) → \(out.path)")
    }
}
#endif
