import AppKit

/// The little learn prompt: a rounded capsule that appears bottom-center when dictado notices
/// you fixed a word — "miele → Myela" between a ✕ (dismiss) and a ✓ (add to your dictionary).
/// Non-activating, so clicking it never steals focus from the app you're typing in.
final class LearnPill: NSObject {
    static let shared = LearnPill()

    private var panel: NSPanel?
    private var autoClose: DispatchWorkItem?
    private var onAccept: (() -> Void)?
    private var onRemove: (() -> Void)?

    private let ink = NSColor(srgbRed: 0.93, green: 0.94, blue: 0.96, alpha: 1)
    private let duskBlue = NSColor(srgbRed: 0x56 / 255.0, green: 0x81 / 255.0, blue: 0xB5 / 255.0, alpha: 1)
    private let muted = NSColor(srgbRed: 0.62, green: 0.66, blue: 0.72, alpha: 1)
    private let bg = NSColor(srgbRed: 0x1c / 255.0, green: 0x1c / 255.0, blue: 0x1e / 255.0, alpha: 0.98)
    private let circle = NSColor(srgbRed: 0.27, green: 0.28, blue: 0.30, alpha: 1)

    /// Show "from → to". ✓ runs onAccept (learn it); ✕ or a ~6s timeout dismisses without learning.
    func show(from: String, to: String, onAccept: @escaping () -> Void) {
        close()
        self.onAccept = onAccept

        let height: CGFloat = 44
        let dot: CGFloat = 30 // button diameter
        let center = label("\(from)  →  \(to)", size: 13, weight: .medium, color: ink)
        center.alignment = .center

        let reject = circleButton(symbol: "xmark", fg: ink, bgColor: circle, diameter: dot, action: #selector(rejectTapped))
        let accept = circleButton(symbol: "checkmark", fg: .white, bgColor: duskBlue, diameter: dot, action: #selector(acceptTapped))

        let stack = NSStackView(views: [reject, center, accept])
        stack.orientation = .horizontal
        stack.spacing = 14
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 7, bottom: 0, right: 7)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let width = min(560, max(260, center.intrinsicContentSize.width + dot * 2 + 14 * 2 + 7 * 2 + 24))
        mountCapsule(stack: stack, width: width, height: height)

        let work = DispatchWorkItem { [weak self] in self?.close() } // timeout = dismiss, don't learn
        autoClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    /// Shown right after a word is added (same spot as dictation): "Saved 'Myela'" with a Remove
    /// button so you can undo it on the spot. Auto-dismisses after a few seconds.
    func showAdded(word: String, onRemove: @escaping () -> Void) {
        close()
        self.onRemove = onRemove

        let height: CGFloat = 44
        let badge = circleButton(symbol: "checkmark", fg: .white, bgColor: duskBlue, diameter: 26, action: #selector(noop))
        badge.isEnabled = false
        let center = label("Saved “\(word)”", size: 13, weight: .medium, color: ink)
        let remove = textButton("Remove", action: #selector(removeTapped))

        let stack = NSStackView(views: [badge, center, remove])
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 9, bottom: 0, right: 9)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let width = min(520, max(240, center.intrinsicContentSize.width + 26 + remove.intrinsicContentSize.width + 12 * 2 + 9 * 2 + 16))
        mountCapsule(stack: stack, width: width, height: height)

        let work = DispatchWorkItem { [weak self] in self?.close() }
        autoClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    func close() {
        autoClose?.cancel(); autoClose = nil
        panel?.orderOut(nil); panel = nil
        onAccept = nil; onRemove = nil
    }

    @objc private func acceptTapped() { let cb = onAccept; close(); cb?() }
    @objc private func rejectTapped() { close() }
    @objc private func removeTapped() { let cb = onRemove; close(); cb?() }
    @objc private func noop() {}

    /// Wrap a horizontal stack in the floating, non-activating capsule and show it bottom-center.
    private func mountCapsule(stack: NSStackView, width: CGFloat, height: CGFloat) {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        content.wantsLayer = true
        content.layer?.backgroundColor = bg.cgColor
        content.layer?.cornerRadius = height / 2 // full capsule
        content.layer?.borderWidth = 1
        content.layer?.borderColor = NSColor(srgbRed: 0.24, green: 0.25, blue: 0.27, alpha: 1).cgColor
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])

        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .floating
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.contentView = content
        p.collectionBehavior = [.canJoinAllSpaces, .transient]
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.midX - width / 2, y: f.minY + 28))
        }
        p.orderFrontRegardless()
        panel = p
    }

    /// A small text button (e.g. "Remove") tinted in the brand.
    private func textButton(_ title: String, action: Selector) -> NSButton {
        let b = NSButton()
        b.translatesAutoresizingMaskIntoConstraints = false
        b.isBordered = false
        b.bezelStyle = .inline
        b.target = self
        b.action = action
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: duskBlue,
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
        ])
        b.setContentHuggingPriority(.required, for: .horizontal)
        return b
    }

    private func circleButton(symbol: String, fg: NSColor, bgColor: NSColor, diameter: CGFloat, action: Selector) -> NSButton {
        let b = NSButton()
        b.translatesAutoresizingMaskIntoConstraints = false
        b.bezelStyle = .regularSquare
        b.isBordered = false
        b.title = ""
        b.target = self
        b.action = action
        b.wantsLayer = true
        b.layer?.backgroundColor = bgColor.cgColor
        b.layer?.cornerRadius = diameter / 2
        var cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        cfg = cfg.applying(.init(paletteColors: [fg]))
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol)?
            .withSymbolConfiguration(cfg)
        b.imagePosition = .imageOnly
        b.contentTintColor = fg
        NSLayoutConstraint.activate([
            b.widthAnchor.constraint(equalToConstant: diameter),
            b.heightAnchor.constraint(equalToConstant: diameter),
        ])
        return b
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return l
    }
}
