import AppKit
import Shared

/// The small, bottom-centered dictation indicator. Recording shows ONLY a live blue waveform that
/// moves with your voice — no text, no wordmark. On release the waveform goes flat and a spinner
/// appears to its right (processing); then it closes as the text pastes. Error/clipboard states use
/// a tiny text pill. Non-activating, so focus stays in the app you're dictating into.
final class Overlay {
    static let shared = Overlay()

    private var panel: NSPanel?
    private var waveformView: MicWaveformView?
    private var spinner: Spinner?
    private var warnLabel: NSTextField? // the hold-cap countdown, updated in place each second
    private var autoCloseWork: DispatchWorkItem?

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
    func showListening() { mountWave(processing: false) }

    /// Feed the live mic level (0…1) to the recording waveform. No-op otherwise.
    func updateLevel(_ level: Float) { waveformView?.setLevel(CGFloat(level)) }

    /// Released — the waveform goes flat and a spinner spins on the right while we transcribe + polish.
    func showThinking() { mountWave(processing: true) }

    /// Long-session warning (ROADMAP 0.3): the countdown to the hold cap. The mic is still hot, so
    /// the waveform keeps reacting (motion stays honest) — the pill just widens to carry a warn
    /// glyph + countdown so the coming stop is never a surprise. Repeated ticks update the label
    /// in place (monospaced digits — no width wobble).
    func showCapCountdown(secondsLeft: Int) {
        let text = String(format: "stops in %d:%02d", secondsLeft / 60, secondsLeft % 60)
        if let warnLabel { warnLabel.stringValue = text; return }
        mountWave(processing: false, warnText: text)
    }

    /// Pasted — the text in your app is its own confirmation, so just dismiss.
    func showTyped() { autoClose(after: 0.2) }

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
        panel?.orderOut(nil); panel = nil
        waveformView = nil
    }

    // MARK: waveform pill (recording → cap warning → processing)

    private func mountWave(processing: Bool, warnText: String? = nil) {
        autoCloseWork?.cancel(); autoCloseWork = nil

        // Recording starts a fresh waveform; the cap warning and processing reuse it so the bars
        // carry over with continuity (still live under the warning, easing flat for processing).
        let wf: MicWaveformView
        if let existing = waveformView, processing || warnText != nil {
            wf = existing
            if processing { wf.goFlat() }
        } else {
            wf = MicWaveformView(bars: 7)
            wf.barColor = blue
        }
        wf.translatesAutoresizingMaskIntoConstraints = false
        wf.removeFromSuperview()
        waveformView = wf

        var views: [NSView] = [wf]
        var warnIcon: NSImageView?
        var warnWidth: CGFloat = 0
        if let warnText, !processing {
            // Warn + glyph (DESIGN.md: color is never the only signal) beside the live waveform.
            let icon = NSImageView()
            icon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "warning")?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
            icon.contentTintColor = warn
            icon.translatesAutoresizingMaskIntoConstraints = false
            warnIcon = icon
            let l = label(warnText, size: 12, weight: .medium, color: warn)
            l.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            warnLabel = l
            views += [icon, l]
            warnWidth = 8 + 14 + 8 + l.intrinsicContentSize.width
        } else {
            warnLabel = nil
        }
        if processing {
            let s = Spinner(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
            s.color = blue
            s.translatesAutoresizingMaskIntoConstraints = false
            spinner = s
            views.append(s)
        } else {
            spinner = nil
        }

        let rightInset: CGFloat = processing ? 10 : 12
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: rightInset)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let width = 12 + waveSize.width + warnWidth + (processing ? 8 + 16 : 0) + rightInset
        let content = makeCapsule(width: width, height: pillHeight)
        content.addSubview(stack)
        var cons = [
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            wf.widthAnchor.constraint(equalToConstant: waveSize.width),
            wf.heightAnchor.constraint(equalToConstant: waveSize.height),
        ]
        if let s = spinner {
            cons += [s.widthAnchor.constraint(equalToConstant: 16), s.heightAnchor.constraint(equalToConstant: 16)]
        }
        if let icon = warnIcon {
            cons += [icon.widthAnchor.constraint(equalToConstant: 14), icon.heightAnchor.constraint(equalToConstant: 14)]
        }
        NSLayoutConstraint.activate(cons)
        install(content: content, width: width, height: pillHeight)
    }

    // MARK: text pill (errors / clipboard fallback)

    private func presentText(_ message: String, detail: String?, error: Bool = false) {
        close()
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
        let height: CGFloat = 32
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = error ? 8 : 12
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = makeCapsule(width: width, height: height)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
        install(content: content, width: width, height: height)
    }

    // MARK: plumbing

    private func makeCapsule(width: CGFloat, height: CGFloat) -> NSView {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        content.wantsLayer = true
        content.layer?.backgroundColor = bg.cgColor
        content.layer?.cornerRadius = height / 2 // full capsule — very rounded
        content.layer?.borderWidth = 1
        content.layer?.borderColor = stroke.cgColor
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
