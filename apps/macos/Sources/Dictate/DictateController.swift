import AppKit
import Carbon.HIToolbox
import Shared

public final class DictateController: NSObject {
    static private(set) var shared: DictateController!

    /// The app coordinator owns the shared status item; we report icon/menu changes up.
    /// Icon updates carry a priority so the coordinator can arbitrate between the two
    /// capabilities (higher wins): 0 = idle, 3 = recording (the mic must never be ambiguous).
    public var onIcon: ((Int, String) -> Void)?
    public var onMenuRebuild: (() -> Void)?

    /// Read-back (ROADMAP 0.5): the coordinator routes a fired read-back into the Speak module's
    /// one-shot read pipeline (dictate never talks to Speak directly). Nil → read-back never arms.
    public var onReadBack: ((String) -> Void)?
    /// Whether the read-aloud capability is on — read-back's target. Off → the menu row disables
    /// and ⌃R never registers (per-mode law, product.md §4.5). Wired by the coordinator.
    public var readAloudIsOn: (() -> Bool)?

    private var started = false

    /// idle -> listening (key held, recording) -> finishing (transcribe + paste) -> idle
    private enum State { case idle, listening, finishing }
    private var state: State = .idle { didSet { updateStatusIcon() } }

    private let recorder = Recorder()
    private let learner = KeystrokeLearner() // learns corrections from keystrokes — works in terminals too
    private var handsFree = false // true while a double-tap-⌃ (no-hold) session is recording
    private var micWentHot = false // this session's mic actually opened — gates the stop ping (no stop without a start)
    private var capClock: HoldCapClock? // counts down to, then cleanly enforces, the long-session cap
    private var sessionCapped = false   // this session was stopped by the cap — deliver() names why
    /// Bumped whenever a session ends or is cancelled, so a late transcribe/polish completion from a
    /// superseded run is ignored — both Esc-to-cancel and the processing watchdog rely on this.
    private var workGen = 0
    private var processingWatchdog: DispatchWorkItem? // force-resets if transcribe/polish wedges on a stuck engine

    // In-memory safety net: the last few cleaned dictations, so a paste that lands in the wrong app or
    // field isn't lost forever (you'd otherwise have to re-say it). Never written to disk — consistent
    // with "no recording is ever saved" — and cleared when warble quits. Retrieve from the menu via
    // "Copy Last Dictation" / "Recent Dictations".
    private var recentTranscripts: [String] = []
    private let maxRecent = 10

    // Read-back (ROADMAP 0.5): the availability machine plus the timer that releases the
    // transient ⌃R claim at the grace window's end. The machine is pure; everything Carbon lives
    // in ReadBackKey and is registered ONLY between armReadBack and disarmReadBack.
    private var readBack = ReadBackAvailability()
    private var readBackExpiry: DispatchWorkItem?

    /// The last failure, named (the taxonomy in DictateError). Shown as a disabled row in the
    /// Dictate submenu until the next successful dictation, so a missed pill is still explained.
    private var lastError: DictateError?

    /// An orphaned in-flight clip found at launch — evidence of an unclean exit mid-dictation.
    /// Surfaced as one quiet "Recover Last Dictation" menu item (never a dialog — product.md §4.5).
    private var pendingRecovery: URL?

    /// The app being dictated INTO, captured at recording start (before focus can change) for per-app stats.
    private var dictationApp: (bundleId: String?, name: String?)?
    /// Whether a secure (password) field was focused at recording start — so Insights can keep metrics only.
    private var dictationSecure = false
    /// Whether this session is an onboarding rehearsal (the practice card is up and warble itself
    /// was frontmost at recording start) — the result goes to the card, never to paste/History.
    private var dictationSandbox = false
    private static let passwordManagerBundleIDs: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.agilebits.onepassword",
        "com.bitwarden.desktop", "org.keepassxc.keepassxc", "com.lastpass.LastPass", "com.apple.keychainaccess",
    ]

    /// Whether double-tap ⌃ starts a hands-free dictation. On by default; toggle in the menu.
    private var handsFreeEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "handsFreeEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "handsFreeEnabled") }
    }

    public override init() { super.init() }

    /// Whether dictation is on at all. When off, the hold-to-talk hotkey is never registered,
    /// so Fn does nothing and the Microphone / Accessibility prompts are never reached — the
    /// permission for a capability is only ever asked once you've turned it on. On by default.
    private var dictateEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "dictateEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "dictateEnabled") }
    }

    /// Watch the field after a paste and offer to learn spelling fixes. On by default; toggle in the menu.
    private var learnEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "learnFromEdits") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "learnFromEdits") }
    }

    // Guards so an accidental tap or a silent hold never reaches whisper (which
    // hallucinates on silence) or pastes garbage. Starting points — tune to taste.
    private let minClipSeconds = 0.4
    private let silenceFloor: Float = 0.01 // peak sample magnitude (-1...1)

    /// Wire up the dictation capability: the hold-to-talk hotkey and recorder.
    /// The status item + menu are owned by the app coordinator.
    public func start() {
        guard !started else { return } // idempotent: never double-register the hotkey
        started = true
        DictateController.shared = self
        updateStatusIcon()

        HotKey.shared.onPress = { [weak self] in self?.hotKeyPressed() }
        HotKey.shared.onRelease = { [weak self] in self?.hotKeyReleased() }
        HotKey.shared.onDoubleTap = { [weak self] viaBinding in self?.handsFreeToggle(viaBinding: viaBinding) }
        recorder.onDisconnect = { [weak self] in self?.micDisconnected() }
        // The listening contract's start ping (ROADMAP 0.4): tied to the mic ACTUALLY opening —
        // a session whose mic fails stays silent (its error state speaks instead).
        recorder.onHot = { [weak self] in
            self?.micWentHot = true
            DictateSounds.playStart()
        }
        if dictateEnabled { HotKey.shared.register() } // off → no monitor, no permission prompt
        pendingRecovery = Recovery.scan() // an unclean exit mid-dictation? offer the quiet Recover row
    }

    /// Tear down background helpers (the warm ASR + LLM servers) when the app quits.
    public func shutdown() { WarmASR.shared.shutdown(); WarmLLM.shared.shutdown() }

    /// Menu-bar glyph reflects state so the mic is never ambiguously "on": idle = mic,
    /// recording/processing = mic.fill. (A common complaint in this app class is not knowing
    /// whether it's listening.)
    private func updateStatusIcon() {
        // Recording outranks any read-aloud state so the hot mic is never masked.
        onIcon?(state == .idle ? 0 : 3, state == .idle ? "mic" : "mic.fill")
    }

    /// The dictation block of the shared menu: the on/off toggle plus a "Dictate" submenu carrying
    /// the detail rows. Rebuilt by the coordinator on demand. When the capability is off the toggle
    /// stands alone (no submenu) so the menu reads as "this mode is parked".
    public func menuItems() -> [NSMenuItem] {
        let toggle = NSMenuItem(title: "Dictate — hold Fn to record", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = dictateEnabled ? .on : .off
        guard dictateEnabled else { return [toggle] }

        let sub = NSMenu()
        sub.autoenablesItems = false // the root's setting doesn't propagate; the Engine info row needs it

        // The Engine row is honest about the floor: on Apple Speech it says WHY (no premium engine).
        let engineName = Transcribers.activeEngineName()
        let engine = NSMenuItem(title: engineName == "Apple Speech"
            ? "Engine: Apple Speech — premium not installed"
            : "Engine: \(engineName)", action: nil, keyEquivalent: "")
        engine.isEnabled = false
        sub.addItem(engine)

        // The last failure, named — so a pill that vanished before it was read is still explained.
        if let err = lastError {
            let item = NSMenuItem(title: "Last error: \(err.message)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "error")
            sub.addItem(item)
        }

        // Recovery: an in-flight clip survived an unclean exit. One quiet affordance — recovering
        // transcribes it into History, never a paste into whatever happens to be focused now.
        if pendingRecovery != nil {
            let recover = NSMenuItem(title: "Recover Last Dictation",
                                     action: #selector(recoverLastDictation), keyEquivalent: "")
            recover.target = self
            recover.toolTip = "A dictation was interrupted — transcribe it into History"
            sub.addItem(recover)
        }

        // Recovery: if a dictation pasted somewhere wrong, grab it here instead of re-saying it.
        if let last = recentTranscripts.first {
            sub.addItem(.separator())
            let copyLast = NSMenuItem(title: "Copy Last Dictation", action: #selector(copyLastTranscript), keyEquivalent: "")
            copyLast.target = self
            copyLast.toolTip = oneLine(last)
            sub.addItem(copyLast)
            // The proofreading loop (ROADMAP 0.5): hear the last dictation back through the real
            // read-aloud pipeline — the menu twin of the transient ⌃R, minus the grace window, so
            // the loop stays discoverable and hotkey-optional. Disabled (never hidden) while
            // read-aloud is off — the same idiom as the LLM-less cleanup levels; ⌃R doesn't arm
            // then either (per-mode law).
            let readBackItem = NSMenuItem(title: "Read Last Dictation Back",
                                          action: #selector(readLastDictationBack), keyEquivalent: "")
            readBackItem.target = self
            if readAloudIsOn?() ?? false {
                readBackItem.toolTip = "⌃R right after a dictation lands does the same"
            } else {
                readBackItem.isEnabled = false
                readBackItem.toolTip = "Turn on Read aloud to hear it back"
            }
            sub.addItem(readBackItem)
            if recentTranscripts.count > 1 {
                let recent = NSMenuItem(title: "Recent Dictations", action: nil, keyEquivalent: "")
                let recentMenu = NSMenu()
                recentMenu.autoenablesItems = false
                for (i, t) in recentTranscripts.enumerated() {
                    let it = NSMenuItem(title: preview(t), action: #selector(copyRecent(_:)), keyEquivalent: "")
                    it.target = self
                    it.tag = i
                    it.toolTip = oneLine(t)
                    recentMenu.addItem(it)
                }
                recent.submenu = recentMenu
                sub.addItem(recent)
            }
        }

        sub.addItem(.separator())
        // Cleanup levels (radio): None/Light are always available; Medium/High need the on-device
        // polish model, so without it they sit disabled with a pointer to Setup — never a silent no-op.
        let cleanupMenu = NSMenu()
        cleanupMenu.autoenablesItems = false
        let llmReady = Cleaners.llmAvailable
        for level in CleanupLevel.allCases {
            let it = NSMenuItem(title: level.menuTitle, action: #selector(setCleanupLevel(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = level.rawValue
            it.state = Cleaners.level == level ? .on : .off
            if level.usesLLM, !llmReady {
                it.isEnabled = false
                it.toolTip = "Needs the on-device AI — menu → Set up better engines…"
            }
            cleanupMenu.addItem(it)
        }
        let cleanup = NSMenuItem(title: "Cleanup", action: nil, keyEquivalent: "")
        cleanup.submenu = cleanupMenu
        sub.addItem(cleanup)
        let hands = NSMenuItem(title: "Hands-free — double-tap Fn", action: #selector(toggleHandsFree), keyEquivalent: "")
        hands.target = self
        hands.state = handsFreeEnabled ? .on : .off
        sub.addItem(hands)
        let learn = NSMenuItem(title: "Learn from edits", action: #selector(toggleLearn), keyEquivalent: "")
        learn.target = self
        learn.state = learnEnabled ? .on : .off
        sub.addItem(learn)
        let sounds = NSMenuItem(title: "Sounds", action: #selector(toggleSounds), keyEquivalent: "")
        sounds.target = self
        sounds.state = DictateSounds.enabled ? .on : .off
        sounds.toolTip = "A soft ping when the mic goes hot; a quieter one on a clean stop"
        sub.addItem(sounds)
        let autoSend = NSMenuItem(title: "Press Enter to Send", action: #selector(toggleAutoSend), keyEquivalent: "")
        autoSend.target = self
        autoSend.state = AutoSend.enabled ? .on : .off
        autoSend.toolTip = "End a dictation by saying \"press enter\" — warble sends it. Off by default; never fires in a password field."
        sub.addItem(autoSend)
        sub.addItem(.separator())
        let dash = NSMenuItem(title: "Dictionary…", action: #selector(openDictionary), keyEquivalent: "d")
        dash.target = self
        sub.addItem(dash)
        // The bindings editor (ROADMAP 0.5): extra triggers besides Fn, managed in the dashboard.
        let keys = NSMenuItem(title: "Shortcuts…", action: #selector(openShortcuts), keyEquivalent: "")
        keys.target = self
        sub.addItem(keys)

        let subItem = NSMenuItem(title: "Dictate", action: nil, keyEquivalent: "")
        subItem.submenu = sub
        return [toggle, subItem]
    }

    // MARK: session

    /// Turn the whole capability on or off. Off → unregister the hotkey and tear down any
    /// in-flight session, so the Fn hotkey is inert and no mic/Accessibility prompt can be reached.
    @objc private func toggleEnabled() {
        dictateEnabled.toggle()
        if dictateEnabled {
            HotKey.shared.register()
        } else {
            HotKey.shared.unregister()
            workGen &+= 1 // invalidate any in-flight transcribe/polish
            capClock?.cancel(); capClock = nil
            processingWatchdog?.cancel(); processingWatchdog = nil
            unregisterEsc() // and don't leave Esc consumed if we were recording
            disarmReadBack() // an off mode registers nothing — the transient ⌃R claim included
            micWentHot = false // torn down, not cleanly stopped — no ping
            if let clip = recorder.stop() { try? FileManager.default.removeItem(at: clip.url) }
            state = .idle
            learner.stop(); LearnPill.shared.close()
            Overlay.shared.close()
        }
        onMenuRebuild?()
    }

    @objc private func setCleanupLevel(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let level = CleanupLevel(rawValue: raw) else { return }
        Cleaners.level = level
        onMenuRebuild?() // move the radio checkmark in the shared menu
    }

    @objc private func toggleHandsFree() {
        handsFreeEnabled.toggle()
        onMenuRebuild?() // refresh the checkmark in the shared menu
    }

    @objc private func toggleLearn() {
        learnEnabled.toggle()
        if !learnEnabled { learner.stop(); LearnPill.shared.close() }
        onMenuRebuild?() // refresh the checkmark in the shared menu
    }

    /// The start/stop pings (the audible half of the listening contract). Off stays off —
    /// nothing ever re-enables it (product.md §4.5).
    @objc private func toggleSounds() {
        DictateSounds.enabled.toggle()
        onMenuRebuild?() // refresh the checkmark in the shared menu
    }

    /// "Press enter" auto-send (ROADMAP 0.5). Off stays off — nothing ever re-enables it
    /// (product.md §4.5); flipped on, it applies starting with the very next dictation.
    @objc private func toggleAutoSend() {
        AutoSend.enabled.toggle()
        onMenuRebuild?() // refresh the checkmark in the shared menu
    }

    @objc private func openDictionary() { InsightsWindow.shared.open(section: .dictionary) }

    @objc private func openShortcuts() { InsightsWindow.shared.open(section: .shortcuts) }

    // MARK: recent dictations — a safety net for a mis-targeted paste

    private func remember(_ text: String) {
        recentTranscripts.removeAll { $0 == text }     // most-recent-first, de-duplicated
        recentTranscripts.insert(text, at: 0)
        if recentTranscripts.count > maxRecent { recentTranscripts.removeLast() }
        onMenuRebuild?() // keep "Copy Last Dictation" / the submenu current
    }

    /// Transcribe the orphaned in-flight clip into History — never auto-paste (the field those
    /// words were meant for is long gone). The pill shows processing; the outcome is named either
    /// way, and a transcription failure keeps the audio as a FAILED history item.
    @objc private func recoverLastDictation() {
        guard let orphan = pendingRecovery else { return }
        pendingRecovery = nil
        onMenuRebuild?()
        Overlay.shared.showThinking()
        Recovery.recover(orphan) { [weak self] outcome in
            guard let self, self.state == .idle else { return } // a live dictation owns the pill now
            switch outcome {
            case .recovered(let text):
                self.remember(text) // recoverable from the menu too, like any dictation
                Overlay.shared.flash(message: "recovered — it's in History")
            case .failedKept:
                self.noteError(.transcribeFailedKept)
            case .failedLost:
                self.noteError(.transcribeFailed)
            case .nothingHeard:
                Overlay.shared.flash(message: "nothing heard in the recovered clip")
            }
        }
    }

    @objc private func copyLastTranscript() {
        guard let t = recentTranscripts.first else { return }
        copyToClipboard(t)
    }
    @objc private func copyRecent(_ sender: NSMenuItem) {
        guard recentTranscripts.indices.contains(sender.tag) else { return }
        copyToClipboard(recentTranscripts[sender.tag])
    }
    private func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        Overlay.shared.flash(message: "copied — ⌘V to paste")
    }
    private func preview(_ s: String) -> String {
        let one = oneLine(s)
        return one.count > 48 ? String(one.prefix(47)) + "…" : one
    }
    private func oneLine(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
    }

    // MARK: read-back — the proofreading loop (ROADMAP 0.5)
    // Speak it, hear it back: deliver() arms a transient ⌃R claim for the grace window after a
    // dictation lands; firing routes the text (via the coordinator) into the Speak module's
    // one-shot read. The availability machine is pure (ReadBackAvailability — unit-tested,
    // storied by --readback-state); this block is only the live wiring around it.

    /// Arm read-back for a just-landed dictation. Returns true when ⌃R actually registered —
    /// false when read-aloud is off (an off mode registers nothing, product.md §4.5) or the
    /// field was secure (a spoken password is never read back aloud).
    private func armReadBack(_ text: String, secure: Bool) -> Bool {
        guard readBack.landed(text, at: Date().timeIntervalSince1970,
                              speakEnabled: readAloudIsOn?() ?? false, secure: secure) else {
            releaseReadBackKey()
            return false
        }
        ReadBackKey.shared.register { [weak self] in self?.readBackKeyFired() }
        readBackExpiry?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.disarmReadBack() }
        readBackExpiry = w
        DispatchQueue.main.asyncAfter(deadline: .now() + ReadBackAvailability.graceSeconds, execute: w)
        return true
    }

    /// ⌃R inside the grace window: consume the availability (one-shot), release the claim, and
    /// hand the text to the coordinator for the real read.
    private func readBackKeyFired() {
        let text = readBack.consume(at: Date().timeIntervalSince1970)
        disarmReadBack()
        guard let text else { return } // expired between the press and the hop to main — stale, drop it
        onReadBack?(text)
    }

    /// Withdraw any read-back availability and release the ⌃R claim (new session, mode off, expiry).
    private func disarmReadBack() {
        readBack.cancel()
        releaseReadBackKey()
    }

    private func releaseReadBackKey() {
        readBackExpiry?.cancel(); readBackExpiry = nil
        ReadBackKey.shared.unregister()
    }

    /// The read-aloud capability was toggled off (the coordinator relays it): per-mode law —
    /// an off mode registers nothing — so an armed ⌃R claim releases immediately, not at expiry.
    public func readBackModeOff() {
        disarmReadBack()
    }

    /// Menu "Read Last Dictation Back" — the loop, hotkey-optional: reads whatever "Copy Last
    /// Dictation" would copy, through the same one-shot pipeline ⌃R uses. Works any time a last
    /// dictation exists (no grace window); an armed ⌃R claim is spent — the read it promised is
    /// happening.
    @objc private func readLastDictationBack() {
        guard let t = recentTranscripts.first, readAloudIsOn?() ?? false else { return }
        disarmReadBack()
        onReadBack?(t)
    }

    // Hold Fn: press starts, release stops.
    private func hotKeyPressed() {
        guard state == .idle else { return } // debounce key-repeat / re-press
        handsFree = false
        beginRecording()
    }
    private func hotKeyReleased() {
        guard state == .listening, !handsFree else { return } // a release only ends a *hold* session
        finishRecording()
    }

    /// Double-tap — hands-free mode: the first toggle starts recording (no need to hold), the next
    /// stops and delivers. Lets you dictate without keeping the key down. The menu's Hands-free
    /// toggle governs Fn's double-tap only; a BINDING with the double-tap gesture was added
    /// deliberately in the Shortcuts editor, so removing it — not that toggle — is how it's
    /// turned off (product.md §4.5: the user's explicit intent wins).
    private func handsFreeToggle(viaBinding: Bool) {
        guard dictateEnabled, viaBinding || handsFreeEnabled else { return }
        if state == .idle { handsFree = true; beginRecording() }
        else if state == .listening, handsFree { finishRecording() }
    }

    private func beginRecording() {
        // Capture the app being dictated into NOW, before anything can change focus — the per-app signal.
        let app = NSWorkspace.shared.frontmostApplication
        // If warble's own window (Insights/Dictionary) is frontmost, don't attribute the dictation to warble.
        let isSelf = app?.bundleIdentifier == Bundle.main.bundleIdentifier
        dictationApp = isSelf ? (nil, nil) : (app?.bundleIdentifier, app?.localizedName)
        dictationSecure = IsSecureEventInputEnabled()
            || ((app?.bundleIdentifier).map(Self.passwordManagerBundleIDs.contains) ?? false)
        // The onboarding practice card: a dictation that starts while the rehearsal card is up AND
        // warble itself is frontmost belongs to the card. Frontmost anywhere else = a real
        // dictation (the user left the tour mid-card) — recorded and pasted normally.
        dictationSandbox = PracticeSandbox.shared.isActive && isSelf
        learner.stop(); LearnPill.shared.close() // a new dictation supersedes any pending learn prompt
        disarmReadBack() // …and any armed read-back — this session re-arms it when it lands
        workGen &+= 1 // a fresh session; any straggler completion from before is now stale
        sessionCapped = false
        micWentHot = false
        registerEsc() // Esc cancels — while recording, and through processing
        state = .listening
        Overlay.shared.showListening(handsFree: handsFree) // shapes the pill's hover hint
        // Warm the engines now so their load overlaps with you speaking, not the paste path:
        // the warm Parakeet ASR server and the LLM polish model.
        DispatchQueue.global(qos: .utility).async {
            WarmASR.shared.ensureRunning()
            if Cleaners.level.usesLLM, MLXCleaner.isAvailable() { WarmLLM.shared.ensureRunning() }
        }
        recorder.onLevel = { Overlay.shared.updateLevel($0) }
        recorder.start(onError: { [weak self] err in
            self?.capClock?.cancel(); self?.capClock = nil
            self?.unregisterEsc() // don't leave Esc globally consumed if the mic couldn't start
            self?.state = .idle
            self?.noteError(err)
        })
        // Long-session hardening (ROADMAP 0.3): the pill counts down the final minute, then the
        // session stops CLEANLY at the cap — everything captured is transcribed and lands
        // normally, and deliver() names why it stopped. Never a silent truncation. This is also
        // the safety net for a dropped Fn key-up (a known Carbon hot-key failure mode).
        capClock = HoldCapClock(onTick: { [weak self] secs in
            guard let self, self.state == .listening else { return }
            Overlay.shared.showCapCountdown(secondsLeft: secs)
        }, onCap: { [weak self] in
            guard let self, self.state == .listening else { return }
            self.sessionCapped = true
            Log.dictate.notice("reason=hold-cap — stopping cleanly at the \(Int(HoldCap.maxSeconds), privacy: .public)s cap")
            self.finishRecording()
        })
    }

    private func finishRecording(playStopSound: Bool = true) {
        capClock?.cancel(); capClock = nil
        state = .finishing // Esc stays claimed → it now cancels the transcribe/polish (see escapePressed)
        let stopped = recorder.stop()
        // The stop ping — a clean, user-intended end only (release / hands-free stop / the cap's
        // clean stop). After recorder.stop(), so it can never leak into the clip; gated on the mic
        // having actually opened; skipped on the disconnect path (that error names itself).
        if micWentHot, playStopSound { DictateSounds.playStop() }
        micWentHot = false
        guard let clip = stopped else { // nothing captured
            unregisterEsc(); state = .idle
            Log.dictate.info("reason=no-clip — recorder had nothing")
            Overlay.shared.close()
            return
        }
        if clip.capped { // the runaway ceiling engaged — the cap clock should have stopped us 30s earlier
            Log.dictate.error("reason=runaway-ceiling — audio past the ceiling was not written")
        }
        // Too short, or silent: drop it silently rather than paste a phantom.
        if clip.duration < minClipSeconds {
            try? FileManager.default.removeItem(at: clip.url)
            unregisterEsc(); state = .idle
            Log.dictate.info("reason=too-short — \(clip.duration, privacy: .public)s clip dropped")
            Overlay.shared.close()
            return
        }
        if clip.peak < silenceFloor {
            try? FileManager.default.removeItem(at: clip.url)
            unregisterEsc(); state = .idle
            Log.dictate.info("reason=silent-clip — peak \(clip.peak, privacy: .public) under the floor")
            Overlay.shared.flash(message: "nothing heard")
            return
        }
        transcribeAndDeliver(clip)
    }

    /// The input device vanished mid-dictation (unplugged, Bluetooth drop). Name the cause, then run
    /// the normal finish path — whatever was captured before the drop is transcribed and delivered,
    /// never lost (product.md §4.10). The short delay lets the cause actually be read before the
    /// pill switches to the processing spinner.
    private func micDisconnected() {
        guard state == .listening else { return }
        noteError(.micDisconnected)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, self.state == .listening else { return } // released or cancelled meanwhile
            self.finishRecording(playStopSound: false) // an error path — the named cause speaks, not a chime
        }
    }

    /// One gate every failure passes through: remember it for the menu row, log its distinguishable
    /// reason, and flash the named cause in the pill (warn + glyph — DESIGN.md failure styling).
    private func noteError(_ err: DictateError) {
        lastError = err
        Log.dictate.error("reason=\(err.reason, privacy: .public)")
        Overlay.shared.flashError(message: err.message)
        onMenuRebuild?()
    }

    /// Esc while recording — discard the clip, paste nothing. Works for both hold and hands-free.
    fileprivate func cancelRecording() {
        guard state == .listening else { return }
        workGen &+= 1
        capClock?.cancel(); capClock = nil
        unregisterEsc()
        handsFree = false
        micWentHot = false // cancelled — no stop ping (only clean stops chime)
        recorder.onLevel = nil
        if let clip = recorder.stop() { try? FileManager.default.removeItem(at: clip.url) }
        state = .idle
        Log.dictate.info("reason=cancelled — Esc while recording")
        Overlay.shared.flash(message: "cancelled")
    }

    /// Esc while processing — abandon a transcribe/polish that's taking too long (or has wedged). The
    /// in-flight subprocess finishes harmlessly in the background; bumping workGen makes its result a
    /// no-op (no paste), so the UI is free immediately and a new dictation can start.
    fileprivate func cancelProcessing() {
        guard state == .finishing else { return }
        workGen &+= 1
        processingWatchdog?.cancel(); processingWatchdog = nil
        unregisterEsc()
        state = .idle
        Log.dictate.info("reason=cancelled — Esc while processing")
        Overlay.shared.flash(message: "cancelled")
    }

    // MARK: Esc-to-cancel — via the shared EscapeKey owner, so it never collides with read-aloud's Esc.
    // Claimed from recording start and held through processing; the handler routes by state so the same
    // key discards a recording mid-capture OR cancels a stuck transcribe/polish.

    private func registerEsc() { EscapeKey.shared.claim(self) { [weak self] in self?.escapePressed() } }
    private func unregisterEsc() { EscapeKey.shared.release(self) }
    private func escapePressed() {
        switch state {
        case .listening: cancelRecording()
        case .finishing: cancelProcessing()
        case .idle: break
        }
    }

    /// Safety net for the processing phase: if transcribe/polish wedges on a stuck engine, force back to
    /// idle (and free Esc) after a generous, clip-scaled bound, so the pill can never spin forever.
    private func startProcessingWatchdog(gen: Int, clipDuration: TimeInterval) {
        processingWatchdog?.cancel()
        let bound = Fault.isActive(.engineWarming) ? 3 : max(30, clipDuration * 3 + 25)
        let wd = DispatchWorkItem { [weak self] in
            guard let self, self.state == .finishing, self.workGen == gen else { return }
            self.workGen &+= 1
            self.processingWatchdog = nil
            self.unregisterEsc()
            self.state = .idle
            // Name the likeliest cause: a warm engine that's installed but not answering yet is
            // still loading its model. The health probe is a 1s one-shot on an already-failed path.
            let warming = Fault.isActive(.engineWarming)
                || (WarmASR.isInstalled() && !WarmASR.shared.isHealthy())
            self.noteError(warming ? .engineWarming : .processingTimeout)
        }
        processingWatchdog = wd
        DispatchQueue.main.asyncAfter(deadline: .now() + bound, execute: wd)
    }

    /// Tear down the processing phase for a normal non-paste exit (e.g. "nothing heard"), if still current.
    private func endProcessing(gen: Int) {
        guard workGen == gen else { return }
        processingWatchdog?.cancel(); processingWatchdog = nil
        unregisterEsc()
        state = .idle
    }

    /// One pass over the whole recorded clip, off the main thread, then clean + paste. The temp WAV
    /// is deleted once it's handled: copied into history's audio store when saving is on, kept
    /// there too when transcription FAILS (the words must never cost a re-say — product.md §4.10),
    /// deleted outright otherwise. Esc (or the watchdog) can cancel mid-flight: each completion
    /// re-checks `workGen`, so a superseded run never pastes.
    private func transcribeAndDeliver(_ clip: Recorder.Result) {
        Overlay.shared.showThinking()
        let gen = workGen
        startProcessingWatchdog(gen: gen, clipDuration: clip.duration)
        // Snapshot the metrics deliver() doesn't otherwise have — the clip's duration (→WPM), the
        // engine, and the app captured at recording start — so per-dictation stats can be recorded.
        let ctx = DictationContext(durationMs: Int(clip.duration * 1000),
                                   engine: Transcribers.activeEngineName(),
                                   appBundleId: dictationApp?.bundleId,
                                   appName: dictationApp?.name,
                                   secure: dictationSecure,
                                   sandbox: dictationSandbox)
        let wav = clip.url
        Transcribers.run(wav, clipDuration: clip.duration) { [weak self] outcome in
            guard let self else { try? FileManager.default.removeItem(at: wav); return }
            guard self.workGen == gen else { try? FileManager.default.removeItem(at: wav); return } // cancelled
            switch outcome {
            case .failed:
                // Every engine errored on a clip that HAD voice (the silence gate passed it).
                // Land a FAILED history event that keeps the recording — replay + Re-transcribe
                // live in the dashboard's History — and say so.
                let kept = InsightStore.shared.recordFailed(audioSource: wav, ctx: ctx) != nil
                try? FileManager.default.removeItem(at: wav)
                self.endProcessing(gen: gen)
                self.noteError(kept ? .transcribeFailedKept : .transcribeFailed)
            case .silence:
                try? FileManager.default.removeItem(at: wav) // genuinely nothing heard — don't keep the audio
                self.endProcessing(gen: gen)
                Log.dictate.info("reason=nothing-heard — engines ran, no speech found")
                Overlay.shared.flash(message: "nothing heard")
            case .text(let raw):
                DispatchQueue.global(qos: .utility).async { // LLM / bun cleaner may block
                    let spell = SpellOut.process(raw) // resolve any spoken spelling first
                    let cleaner = Cleaners.best(for: spell.text) // the chosen cleanup level; off main
                    // cleanup, then your dictionary, then any snippet triggers, then "press enter"
                    // auto-send (ROADMAP 0.5) — in that order, always, regardless of cleanup level:
                    // a snippet or the auto-send phrase is explicit user intent, not AI rewriting,
                    // so each fires whenever it applies (a snippet whenever any is defined; the
                    // phrase only when the toggle is on AND it's in the final position).
                    let cleaned = Snippets.shared.expand(Lexicon.shared.apply(cleaner.clean(spell.text)))
                    let auto = AutoSend.apply(cleaned)
                    DispatchQueue.main.async {
                        guard self.workGen == gen else { try? FileManager.default.removeItem(at: wav); return } // cancelled during polish
                        for rule in spell.learned { Lexicon.shared.learnExplicit(from: rule.from, to: rule.to) }
                        // `raw` is the verbatim transcript — history keeps it so any cleanup is undoable.
                        self.deliver(auto.pasted, raw: raw, ctx: ctx, audio: wav,
                                     autoSendSaid: auto.send ? auto.said : nil) // record copies the recording (when saving is on)
                        try? FileManager.default.removeItem(at: wav) // then drop the temp WAV
                        if let word = spell.learned.first?.to { // confirm what spelling was locked in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                LearnPill.shared.showAdded(word: word) { spell.learned.forEach { Lexicon.shared.forget($0.from) } }
                            }
                        }
                    }
                }
            }
        }
    }

    /// `autoSendSaid` is non-nil only when the "press enter" toggle is on AND the dictation ended
    /// with the phrase (AutoSend.apply already stripped it out of `cleaned`) — its value is the
    /// phrase itself ("press enter" / "press return"), for the pill's landed copy.
    private func deliver(_ cleaned: String, raw: String, ctx: DictationContext, audio: URL?, autoSendSaid: String? = nil) {
        processingWatchdog?.cancel(); processingWatchdog = nil
        unregisterEsc()
        state = .idle
        guard !cleaned.isEmpty else {
            Log.dictate.info("reason=cleaned-empty — cleanup produced nothing")
            Overlay.shared.flash(message: "nothing heard")
            return
        }
        lastError = nil // this dictation landed — the menu's "Last error" row retires
        if ctx.sandbox {
            // An onboarding rehearsal: the practice card shows the raw → cleaned transformation.
            // Nothing is pasted (focus may have wandered mid-hold — never type into an app the
            // user didn't aim at), nothing remembered or learned; InsightStore.record
            // double-guards on ctx.sandbox so History/stats can't move either.
            PracticeSandbox.shared.deliver(raw: raw, cleaned: cleaned)
            Overlay.shared.showLanded()
            return
        }
        remember(cleaned)                                                // in-memory safety net for a mis-targeted paste
        InsightStore.shared.record(cleaned, raw: raw, ctx: ctx, audioSource: audio) // local stats + history (+ saved recording)
        // Read-back (ROADMAP 0.5): the just-landed words are available to hear back — ⌃R for the
        // grace window (a transient claim, never standing), the menu item any time. Never armed
        // for a secure-field dictation (a spoken password must not be read out loud) — the same
        // ctx.secure gate auto-send and the store already honor; armReadBack's `secure` parameter
        // is the unit-tested twin of this exact gate (ReadBackAvailability.landed).
        let readBackArmed = armReadBack(cleaned, secure: ctx.secure)
        if Paster.paste(cleaned) {
            // Auto-send (ROADMAP 0.5): the Return keystroke fires only after this successful
            // paste, and NEVER in a secure field — reusing ctx.secure, the same signal
            // InsightStore already gates on to keep secure-field dictations to metrics-only.
            // AutoSend.mayFireReturn is the unit-tested twin of this exact gate.
            let sending = AutoSend.mayFireReturn(said: autoSendSaid, secure: ctx.secure)
            if sending { Paster.postReturn() }
            if sessionCapped {
                sessionCapped = false
                // The stop was warble's doing, not the user's — say why (warn + glyph so it can't
                // be missed after a 20-minute session), and keep the cause in the menu row too.
                noteError(.holdCapReached)
            } else if sending {
                // So the behavior is never mysterious: the checkmark alone can't say "and it sent".
                Overlay.shared.showLanded(note: "sent — said '\(autoSendSaid!)'")
            } else if shouldNoteAppleFloor(ctx) {
                Overlay.shared.flash(message: DictateError.engineMissing.message) // notice, not a failure
            } else {
                // The quiet affordance line — shown only while ⌃R is actually armed, so the pill
                // can never advertise a dead key (read-aloud off, secure field).
                Overlay.shared.showLanded(readBackHint: readBackArmed)
            }
            startLearning(pasted: cleaned)
        } else {
            // Accessibility denied: text is on the clipboard. Echo it so the user
            // can confirm what was captured before pasting manually — the one
            // place the old live preview earned its keep.
            Log.dictate.error("reason=paste-denied — Accessibility not granted; text left on the clipboard")
            Overlay.shared.showCopied(cleaned)
        }
    }

    /// One-time honesty note (once ever — never a nag, principle 5): the dictation worked, but on
    /// the zero-install Apple engine because no premium engine is installed. The menu's Engine row
    /// carries the same fact persistently; Setup is one menu away.
    private func shouldNoteAppleFloor(_ ctx: DictationContext) -> Bool {
        guard ctx.engine == "Apple Speech",
              !UserDefaults.standard.bool(forKey: "notedAppleEngine") else { return false }
        UserDefaults.standard.set(true, forKey: "notedAppleEngine")
        Log.dictate.notice("reason=engine-missing — dictated on Apple Speech; no premium engine installed")
        return true
    }

    /// After a paste, watch the field for a few seconds; if Seth fixes a word's spelling,
    /// offer to remember it. Waits for the paste to land first, and bails if a new dictation
    /// started in the meantime.
    private func startLearning(pasted: String) {
        guard learnEnabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.state == .idle else { return }
            let watching = self.learner.start(pasted: pasted) { from, to in
                // Frequency-gated: each in-place fix is tallied; a word only becomes a
                // permanent rule once you've corrected it the same way enough times.
                switch Lexicon.shared.recordCorrection(from: from, to: to) {
                case .promoted(let word):
                    LearnPill.shared.showAdded(word: word) { Lexicon.shared.forgetTarget(word) }
                case .pending(let word, let count, let threshold):
                    LearnPill.shared.showProgress(word: word, count: count, of: threshold)
                case .ignored:
                    break
                }
            }
            // If warble can't read this app's text (most browsers/Electron apps), it can't learn edits
            // here — say so once so it isn't silently mysterious. Native fields (Notes, TextEdit…) work.
            if !watching, !UserDefaults.standard.bool(forKey: "warnedNoWatch") {
                UserDefaults.standard.set(true, forKey: "warnedNoWatch")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    LearnPill.shared.showNote("warble can’t watch this app to learn edits")
                }
            }
        }
    }
}
