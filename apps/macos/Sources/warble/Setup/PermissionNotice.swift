import AppKit
import AVFoundation
import ApplicationServices
import Shared

/// Post-macOS-update permission re-verify (ROADMAP 0.4). macOS updates can silently revoke
/// Accessibility — a documented support generator for this app class — so on the first launch
/// after the OS build changes, re-check what was granted before and remember anything revoked.
/// The surface is ONE quiet menu row (the "Last error" idiom from 0.3): never a dialog
/// (product.md §4.5), retired the moment it's acknowledged or the grant comes back.
/// The decision itself is pure (PermissionReverify, unit-tested); this file is the plumbing:
/// live TCC reads, the OS build string, and UserDefaults persistence.
enum PermissionNotice {
    static let mic = "mic"
    static let ax = "ax"

    private static let buildKey = "permMacOSBuild"     // last build we verified under
    private static let grantedKey = "permGrantedSet"   // permissions seen granted then, e.g. ["ax","mic"]
    private static let noticeKey = "permRevokedNotice" // pending (unacknowledged) revocations

    /// The OS build string (e.g. "23E224") — kern.osversion bumps on every macOS update,
    /// including the point releases that shuffle TCC.
    static var currentBuild: String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        guard size > 0 else { return "unknown" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("kern.osversion", &buf, &size, nil, 0)
        return String(cString: buf)
    }

    /// The permissions currently granted — status reads only, never a prompt.
    static func nowGranted() -> Set<String> {
        var g = Set<String>()
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized { g.insert(mic) }
        if AXIsProcessTrusted() { g.insert(ax) }
        return g
    }

    /// Launch entry point: silently re-check after an OS update, store any revocation as the
    /// pending notice, and refresh the baseline (build + grants) for the next update.
    static func checkAtLaunch() {
        let d = UserDefaults.standard
        let now = nowGranted()
        let revoked = PermissionReverify.revoked(lastBuild: d.string(forKey: buildKey),
                                                 currentBuild: currentBuild,
                                                 wasGranted: Set(d.stringArray(forKey: grantedKey) ?? []),
                                                 nowGranted: now)
        if !revoked.isEmpty { d.set(revoked, forKey: noticeKey) }
        d.set(currentBuild, forKey: buildKey)
        d.set(now.sorted(), forKey: grantedKey)
    }

    /// The unacknowledged notice, auto-retired per permission the moment its grant is back.
    static func pending() -> [String] {
        let d = UserDefaults.standard
        guard let stored = d.stringArray(forKey: noticeKey), !stored.isEmpty else { return [] }
        let still = stored.filter { !nowGranted().contains($0) }
        if still.count != stored.count {
            still.isEmpty ? d.removeObject(forKey: noticeKey) : d.set(still, forKey: noticeKey)
        }
        return still
    }

    /// Clicking the notice row is the acknowledgment — it never repeats after this.
    static func acknowledge() { UserDefaults.standard.removeObject(forKey: noticeKey) }

    /// Keep the granted baseline fresh when the onboarding poll sees a grant land, so the next
    /// OS-update re-verify compares against what the user actually had.
    static func refreshBaseline() {
        UserDefaults.standard.set(nowGranted().sorted(), forKey: grantedKey)
    }

    static func menuTitle(for revoked: [String]) -> String {
        let names = revoked.map { $0 == mic ? "Microphone" : "Accessibility" }
        return "\(names.joined(separator: " & ")) access was revoked by the macOS update"
    }

    // System Settings deep links — the same panes the onboarding cards use.
    static let micSettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
    static let axSettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    static func settingsURL(for revoked: [String]) -> URL {
        revoked.contains(mic) ? micSettingsURL : axSettingsURL
    }
}
