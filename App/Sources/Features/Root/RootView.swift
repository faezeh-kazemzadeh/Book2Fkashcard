import SwiftUI
import B2FCore

enum AppTab: String, CaseIterable, Identifiable {
    case dashboard, library, study, search, settings
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .dashboard: return "Dashboard"
        case .library: return "Library"
        case .study: return "Study"
        case .search: return "Search"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "chart.bar.xaxis"
        case .library: return "books.vertical"
        case .study: return "rectangle.on.rectangle.angled"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape"
        }
    }
}

/// Tab bar on iPhone, sidebar split view on iPad. Keyboard navigation (⌘1–⌘5)
/// is provided as menu commands by `Book2FlashcardsApp` (`NavigationCommands`).
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        @Bindable var model = model
        let selection = model.selectedTab
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    List(AppTab.allCases, selection: Binding<AppTab?>($model.selectedTab)) { tab in
                        Label(tab.title, systemImage: tab.systemImage).tag(tab)
                    }
                    .navigationTitle("Book2Flashcards")
                } detail: {
                    content(for: selection)
                }
            } else {
                TabView(selection: $model.selectedTab) {
                    ForEach(AppTab.allCases) { tab in
                        content(for: tab)
                            .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                            .tag(tab)
                    }
                }
            }
        }
        .sheet(item: $model.presentedPaywall) { feature in
            PaywallView(highlightedFeature: feature)
        }
        .sheet(isPresented: Binding(get: { showsOnboarding }, set: { _ in })) {
            OnboardingView()
                .interactiveDismissDisabled()
        }
        .overlay(alignment: .bottom) { ToastView(message: $model.toast) }
        .onChange(of: model.pendingOpenURL) { _, url in
            if url != nil { model.selectedTab = .library }
        }
    }

    /// RTL (Persian/Arabic UI) comes from the app's localisation automatically;
    /// card content sets its own direction per text (see `AdaptiveText`).
    private var showsOnboarding: Bool {
        !settings.onboardingComplete && !ProcessInfo.processInfo.arguments.contains("-SkipOnboarding")
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .dashboard: NavigationStack { DashboardView() }
        case .library: NavigationStack { LibraryView() }
        case .study: NavigationStack { StudyHomeView() }
        case .search: NavigationStack { SearchView() }
        case .settings: NavigationStack { SettingsView() }
        }
    }
}

/// iPad hardware-keyboard navigation, listed in the ⌘-hold shortcut overlay.
struct NavigationCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Go") {
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) { model.selectedTab = tab }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
    }
}
