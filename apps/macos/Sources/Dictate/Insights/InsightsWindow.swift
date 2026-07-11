import AppKit
import SwiftUI
import Combine
import Shared

/// Hosts the SwiftUI dashboard in a single dark NSWindow — the one SwiftUI surface in an
/// otherwise-AppKit app. Owns the window chrome too: an AppKit NSToolbar with a centered section
/// title and contextual items (History search + filter, Data export). Deliberately NOT SwiftUI
/// `.toolbar` — that only reaches a real NSToolbar through the hosting-controller/scene bridge this
/// hand-built window doesn't have, and its auto item injection is the same machinery that put the
/// jumping sidebar-toggle in the old titlebar. AppKit items are explicit: nothing appears we didn't add.
public final class InsightsWindow: NSObject {
    public static let shared = InsightsWindow()
    private var window: NSWindow?
    private let nav = InsightsNav()
    private var bag = Set<AnyCancellable>()

    // Toolbar pieces we retitle/reseed as the section or the History filters change. Weak — the
    // toolbar owns them; they nil out when a section swap removes them.
    private weak var titleLabel: NSTextField?
    private weak var searchItem: NSSearchToolbarItem?
    private weak var filterItem: NSMenuToolbarItem?

    private override init() { super.init() } // keep the singleton discipline

    /// Deep-link from the menu (internal). The app coordinator uses openHome()/openTutorial().
    func open(section: InsightsSection = .home) { openImpl(section: section, tutorial: false) }
    /// Public entry points (callable from the app target, which can't see InsightsSection).
    /// QA sibling of WARBLE_FORCE_INSIGHTS: WARBLE_SECTION=history (etc.) lands the forced open on
    /// any section, so headless screenshots can cover every pane.
    public func openHome() {
        if let raw = ProcessInfo.processInfo.environment["WARBLE_SECTION"],
           let s = InsightsSection.allCases.first(where: { $0.rawValue.lowercased().hasPrefix(raw.lowercased()) }) {
            openImpl(section: s, tutorial: false); return
        }
        openImpl(section: .home, tutorial: false)
    }
    /// Open Home and run the first-time, skippable tutorial — e.g. right after engine setup is done.
    public func openTutorial() { openImpl(section: .home, tutorial: true) }
    /// Open straight to Data & Privacy — the dashboard's settings surface. The main menu's
    /// "Settings…" (⌘,) lands here.
    public func openData() { openImpl(section: .data, tutorial: false) }

    private func openImpl(section: InsightsSection, tutorial: Bool) {
        if window == nil {
            makeWindow()
            applySection(section) // chrome is right on the very first frame, before the sink fires
        }
        nav.section = section
        if tutorial, !UserDefaults.standard.bool(forKey: "didShowTutorial") { nav.showTutorial = true }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: window + toolbar construction

    private func makeWindow() {
        let host = NSHostingView(rootView: InsightsRootView(store: InsightStore.shared, nav: nav))
        host.sizingOptions = [] // don't let the hosting view resize the window to its content
        // .fullSizeContentView lets the sidebar's ink and the detail's black bleed up behind the
        // toolbar — the SwiftUI content gets the toolbar height as a top safe-area inset instead.
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 660),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titleVisibility = .hidden // the toolbar's centered item carries the section name instead
        w.titlebarAppearsTransparent = true
        w.titlebarSeparatorStyle = .none // no system hairline cutting across our two panes
        w.toolbarStyle = .unified
        w.appearance = NSAppearance(named: .darkAqua)
        w.isReleasedWhenClosed = false
        w.contentView = host
        w.contentMinSize = NSSize(width: 860, height: 560)
        w.backgroundColor = Theme.black.ns // warble black behind live-resize, no flash
        // isMovableByWindowBackground stays false: the toolbar strip is already a generous drag
        // region, and background-drag through NSHostingView hit-testing fights the rows' gestures.

        let tb = NSToolbar(identifier: "warble.dashboard")
        tb.delegate = self
        tb.displayMode = .iconOnly
        tb.allowsUserCustomization = false
        tb.centeredItemIdentifiers = [.sectionTitle] // never .toggleSidebar — the fixed sidebar has no toggle
        w.toolbar = tb

        // Restore the saved frame if there is one; center only the very first time. (Autosave-then-
        // center re-centered the restored position on every fresh launch.)
        if !w.setFrameUsingName("warble.insights") { w.center() }
        w.setFrameAutosaveName("warble.insights")
        window = w

        // One path for every way the section changes — sidebar click, menu deep-link, ⌘, and the
        // tutorial walking the rows: retitle + swap the contextual toolbar items.
        nav.$section.receive(on: RunLoop.main)
            .sink { [weak self] in self?.applySection($0) }
            .store(in: &bag)
        // "Clear all history" wipes the events; a stale filter would show an inexplicably empty list.
        NotificationCenter.default.publisher(for: .warbleInsightsCleared)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resetHistoryFilters() }
            .store(in: &bag)
    }

    /// Retitle the chrome and swap the contextual items: search + filter on History, export on Data.
    private func applySection(_ s: InsightsSection) {
        guard let w = window, let tb = w.toolbar else { return }
        w.title = "warble — \(s.rawValue)" // hidden, but feeds the Window menu / Mission Control / VoiceOver
        titleLabel?.stringValue = s.rawValue
        // Base is [.sectionTitle, .flexibleSpace]; everything past index 1 is contextual.
        while tb.items.count > 2 { tb.removeItem(at: 2) }
        switch s {
        case .history:
            tb.insertItem(withItemIdentifier: .historyFilter, at: 2)
            tb.insertItem(withItemIdentifier: .historySearch, at: 3)
        case .data:
            tb.insertItem(withItemIdentifier: .exportData, at: 2)
        default: break
        }
        tb.validateVisibleItems()
    }

    /// After a full wipe, History's filters reset too — the next visit starts clean.
    private func resetHistoryFilters() {
        nav.historySearch = ""
        nav.historyAppFilter = nil
        searchItem?.searchField.stringValue = ""
        filterItem?.title = "All apps"
    }

    /// The filter button's face: the picked app's name, or "All apps".
    private var filterTitle: String {
        nav.historyAppFilter.flatMap { k in InsightStore.shared.appFilters.first { $0.key == k }?.name } ?? "All apps"
    }

    // MARK: toolbar actions

    @objc private func searchChanged(_ sender: NSSearchField) {
        nav.historySearch = sender.stringValue
    }

    @objc private func pickFilter(_ sender: NSMenuItem) {
        nav.historyAppFilter = sender.representedObject as? String
        filterItem?.title = filterTitle
    }

    @objc private func exportHistory(_ sender: Any?) {
        HistoryExport.run(InsightStore.shared)
    }
}

// MARK: - NSToolbarDelegate

private extension NSToolbarItem.Identifier {
    static let sectionTitle = NSToolbarItem.Identifier("warble.sectionTitle")
    static let historySearch = NSToolbarItem.Identifier("warble.historySearch")
    static let historyFilter = NSToolbarItem.Identifier("warble.historyFilter")
    static let exportData = NSToolbarItem.Identifier("warble.exportData")
}

extension InsightsWindow: NSToolbarDelegate {
    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sectionTitle, .flexibleSpace, .historyFilter, .historySearch, .exportData]
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sectionTitle, .flexibleSpace]
    }

    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                        willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case .sectionTitle:
            let item = NSToolbarItem(itemIdentifier: id)
            let label = NSTextField(labelWithString: nav.section.rawValue)
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            label.textColor = Theme.textHi.ns
            item.view = label
            titleLabel = label
            return item
        case .historySearch:
            let item = NSSearchToolbarItem(itemIdentifier: id)
            item.label = "Search"
            item.preferredWidthForSearchField = 220
            item.searchField.placeholderString = "Search dictations"
            item.searchField.sendsSearchStringImmediately = true
            item.searchField.stringValue = nav.historySearch // the query survives section round-trips
            item.searchField.target = self
            item.searchField.action = #selector(searchChanged(_:))
            searchItem = item
            return item
        case .historyFilter:
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = "Filter"
            item.showsIndicator = true
            item.title = filterTitle
            let menu = NSMenu()
            menu.delegate = self // rebuilt on every open, so it always matches the live event set
            item.menu = menu
            filterItem = item
            return item
        case .exportData:
            let item = NSToolbarItem(itemIdentifier: id)
            item.label = "Export"
            item.toolTip = "Export history as JSON"
            item.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Export")
            item.isBordered = true
            item.target = self
            item.action = #selector(exportHistory(_:))
            return item
        default:
            return nil
        }
    }
}

// MARK: - NSMenuDelegate (the per-app History filter)

extension InsightsWindow: NSMenuDelegate {
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let all = NSMenuItem(title: "All apps", action: #selector(pickFilter(_:)), keyEquivalent: "")
        all.target = self
        all.state = nav.historyAppFilter == nil ? .on : .off
        menu.addItem(all)
        let filters = InsightStore.shared.appFilters
        if !filters.isEmpty { menu.addItem(.separator()) }
        for f in filters {
            let item = NSMenuItem(title: f.name, action: #selector(pickFilter(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = f.key
            item.state = nav.historyAppFilter == f.key ? .on : .off
            menu.addItem(item)
        }
    }
}
