import SwiftUI
import MapKit
import UIKit
import Foundation
import os

/// Main content view for the Temperature Converter app.
/// Features multi-city support with time zone slider and premium card design.
/// Automatically refreshes weather when app returns to foreground.
struct ContentView: View {
    private static let walkthroughLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "AlexisFarenheit",
        category: "Walkthrough"
    )

    private enum ActiveSheet: String, Identifiable {
        case logs
        case addCity

        var id: String { rawValue }
    }

    @StateObject private var viewModel = HomeViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var activeSheet: ActiveSheet?
    @State private var areToolsExpanded = false
    @State private var showingOnboarding = false
    @State private var walkthroughFrames: [HomeWalkthroughTarget: CGRect] = [:]
    @State private var hasCheckedOnboarding = false
    @State private var walkthroughCoordinator = WalkthroughCoordinator()
    @AppStorage("hasDismissedForceQuitWidgetHint") private var hasDismissedForceQuitWidgetHint = false
    @AppStorage("homeOnboardingCompletedV2") private var homeOnboardingCompleted = false

    var body: some View {
        ZStack {
            // Background gradient
            backgroundGradient

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {
                        // Header with settings
                        header

                        // Today Snapshot (primary value area)
                        todaySnapshotSection

                        // Error message
                        if let error = viewModel.errorMessage {
                            errorBanner(error)
                        }

                        // My Cities
                        cityCardsSection

                        // Tools (collapsible to keep city info above the fold)
                        toolsSection

                        // iOS limitation hint (important for widget travel refresh debugging):
                        // Force-quitting the app disables background execution, so Significant Location Changes / BGTasks won't run.
                        forceQuitWidgetHint

                        // Extra tail space lets walkthrough step 4 (tools) scroll to a stable position.
                        if walkthroughCoordinator.isActive, walkthroughCoordinator.currentTarget == .tools {
                            Color.clear
                                .frame(height: 320)
                                .allowsHitTesting(false)
                        }

                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 24)
                }
                .onChange(of: walkthroughCoordinator.isActive) { _, isActive in
                    guard isActive else { return }
                    logWalkthrough("presented step=\(walkthroughCoordinator.currentStepIndex) target=\(targetName(walkthroughCoordinator.currentTarget))")
                    scheduleWalkthroughScroll(using: proxy, reason: "presented")
                }
                .onChange(of: walkthroughCoordinator.currentStep) { _, newStep in
                    guard walkthroughCoordinator.isActive else { return }
                    logWalkthrough(
                        "stepChanged step=\(walkthroughCoordinator.currentStepIndex) target=\(targetName(walkthroughCoordinator.currentTarget)) " +
                        "frame=\(frameSummary(for: walkthroughCoordinator.currentTarget)) toolsExpanded=\(areToolsExpanded)"
                    )
                    if walkthroughCoordinator.currentTarget == .tools && !areToolsExpanded {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            areToolsExpanded = true
                        }
                    }
                    scheduleWalkthroughScroll(using: proxy, reason: "stepChanged")
                }
                .onChange(of: areToolsExpanded) { _, isExpanded in
                    guard walkthroughCoordinator.isActive, walkthroughCoordinator.currentTarget == .tools else { return }
                    logWalkthrough("toolsExpandedChanged expanded=\(isExpanded)")
                    scheduleWalkthroughScroll(using: proxy, reason: "toolsExpandedChanged")
                }
            }
        }
        .overlay {
            if walkthroughCoordinator.isActive {
                WalkthroughTooltipView(
                    coordinator: walkthroughCoordinator,
                    onExpandTools: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            areToolsExpanded = true
                        }
                    }
                )
            }
        }
        .coordinateSpace(name: HomeWalkthroughCoordinateSpace.name)
        .preferredColorScheme(.dark)
        .task { viewModel.onAppear() }
        .onAppear {
            guard !hasCheckedOnboarding else { return }
            hasCheckedOnboarding = true

            // Setup walkthrough coordinator callbacks
            walkthroughCoordinator.onFinished = {
                homeOnboardingCompleted = true
            }

            if !homeOnboardingCompleted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showingOnboarding = true
                }
            }
        }
        // Auto-refresh when app comes back to foreground
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                viewModel.onBecameActive()
            }
        }
        .onPreferenceChange(HomeWalkthroughFramePreferenceKey.self) { frames in
            walkthroughFrames = frames
            walkthroughCoordinator.updateFrames(frames)
            guard walkthroughCoordinator.isActive else { return }
            logWalkthrough(
                "framesUpdated currentTarget=\(targetName(walkthroughCoordinator.currentTarget)) " +
                "frame=\(frameSummary(for: walkthroughCoordinator.currentTarget)) all=\(allFrameSummary(frames))"
            )
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .logs:
                LogViewerView()
            case .addCity:
                AddCitySearchSheet(
                    canAddCity: viewModel.canAddCity,
                    remainingSlots: viewModel.remainingCitySlots
                ) { completion in
                    viewModel.addCity(from: completion)
                    activeSheet = nil
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView(
                locationService: viewModel.locationService,
                onComplete: {
                    homeOnboardingCompleted = true
                    showingOnboarding = false
                },
                onStartWalkthrough: {
                    showingOnboarding = false
                    startWalkthrough()
                }
            )
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color.black, Color(hex: "1C1C1E")],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Weather")
                    .font(.largeTitle.bold())
                Text("World Time")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                startWalkthrough()
            } label: {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.trailing, 8)
            .accessibilityLabel(NSLocalizedString("Replay walkthrough", comment: "Accessibility label for replay walkthrough button"))

            // Log viewer button (debug)
            Button {
                activeSheet = .logs
            } label: {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.trailing, 8)

            // Loading indicator or thermometer icon
            if viewModel.isLoadingWeather {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Image(systemName: "thermometer.medium")
                    .font(.title2)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Today Snapshot

    private var todaySnapshotSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Today Snapshot")
                    .font(.title3.bold())
                Spacer()
                confidenceBadge
            }

            if let primaryCity = viewModel.primaryCity {
                CityCardView(
                    city: primaryCity,
                    timeService: viewModel.timeService,
                    isPrimary: true,
                    freshness: viewModel.primaryCityFreshness
                )

                quickActionsRow

                HStack(spacing: 6) {
                    if let lastUpdate = viewModel.lastUpdateTime {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text("Updated")
                        Text(lastUpdate, style: .relative)
                    } else {
                        Image(systemName: "clock.badge.questionmark")
                            .font(.caption2)
                        Text("Waiting for first weather update")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            } else {
                emptyLocationState
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .id(HomeWalkthroughTarget.todaySnapshot)
        .homeWalkthroughTarget(.todaySnapshot)
    }

    private var confidenceBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(freshnessColor(viewModel.primaryCityFreshness))
                .frame(width: 8, height: 8)
            Text(viewModel.widgetSyncStatusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
        )
    }

    private var quickActionsRow: some View {
        HStack(spacing: 10) {
            quickActionButton(
                title: "Refresh",
                systemImage: "arrow.triangle.2.circlepath",
                tint: .blue,
                isDisabled: viewModel.isLoadingWeather
            ) {
                viewModel.forceRefresh()
            }

            quickActionButton(
                title: "Add City",
                systemImage: "plus",
                tint: .indigo,
                isDisabled: !viewModel.canAddCity
            ) {
                activeSheet = .addCity
            }

            quickActionButton(
                title: "Now",
                systemImage: "clock.arrow.circlepath",
                tint: .teal
            ) {
                withAnimation(.spring(response: 0.3)) {
                    viewModel.timeService.resetToCurrentTime()
                }
            }

            if viewModel.authorizationStatus == .denied || viewModel.authorizationStatus == .restricted {
                quickActionButton(
                    title: "Settings",
                    systemImage: "gearshape.fill",
                    tint: .orange
                ) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
        .id(HomeWalkthroughTarget.quickActions)
        .homeWalkthroughTarget(.quickActions)
    }

    private func quickActionButton(
        title: String,
        systemImage: String,
        tint: Color,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .disabled(isDisabled)
    }

    private func freshnessColor(_ freshness: CityWeatherFreshness) -> Color {
        switch freshness {
        case .fresh:
            return .green
        case .loading:
            return .cyan
        case .stale:
            return .orange
        case .unavailable:
            return .gray
        }
    }

    // MARK: - City Cards Section

    private var cityCardsSection: some View {
        VStack(spacing: 0) {
            if viewModel.cities.isEmpty {
                EmptyView()
            } else {
                // City card list
                CityCardListView(
                    cities: $viewModel.cities,
                    timeService: viewModel.timeService,
                    hidesPrimaryCity: true,
                    onDeleteCity: { city in
                        viewModel.removeCity(city)
                    },
                    onReorder: { source, destination in
                        viewModel.moveCities(from: source, to: destination)
                    },
                    onAddCity: {
                        activeSheet = .addCity
                    },
                    freshnessForCity: { city in
                        viewModel.freshness(for: city)
                    }
                )
            }
        }
        .id(HomeWalkthroughTarget.myCities)
        .homeWalkthroughTarget(.myCities)
    }

    private var emptyLocationState: some View {
        VStack(spacing: 16) {
            if viewModel.authorizationStatus == .notDetermined {
                // Request permission from an explicit user action.
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.cyan)
                Text("Location access needed")
                    .font(.headline)
                Text("Enable location to get weather for your current city and background updates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    viewModel.requestLocationPermission(preferAlways: true)
                } label: {
                    Label("Enable Location", systemImage: "location.fill")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            } else if viewModel.authorizationStatus == .denied || viewModel.authorizationStatus == .restricted {
                // Permission denied
                Image(systemName: "location.slash.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text("Location unavailable")
                    .font(.headline)
                Text("Enable location access in Settings to see weather for your current location")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Open Settings", systemImage: "gearshape.fill")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            } else {
                // Loading location
                ProgressView()
                    .scaleEffect(1.2)
                Text("Getting location...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Manual city search option
            Button {
                activeSheet = .addCity
            } label: {
                Label("Add city manually", systemImage: "magnifyingglass")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
            .tint(.blue)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Tools Section

    private var toolsSection: some View {
        VStack(spacing: 14) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    areToolsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.cyan)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tools")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("World Time + Temperature Converter")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(TimeZoneService.formatMinutes12Hour(viewModel.timeService.selectedMinutes))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Image(systemName: areToolsExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
            }
            .buttonStyle(.plain)

            if areToolsExpanded {
                VStack(spacing: 16) {
                    TimeZoneSliderView(
                        timeService: viewModel.timeService,
                        referenceCity: viewModel.primaryCity
                    )
                    ConversionSliderView(fahrenheit: $viewModel.manualFahrenheit)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .id(HomeWalkthroughTarget.tools)
        .homeWalkthroughTarget(.tools)
    }

    private func scrollWalkthroughTarget(using proxy: ScrollViewProxy, animated: Bool = true) {
        guard walkthroughCoordinator.isActive else { return }

        let target = walkthroughCoordinator.currentTarget
        let anchor = walkthroughCoordinator.currentScrollAnchor

        let action = {
            proxy.scrollTo(target, anchor: anchor)
        }

        logWalkthrough(
            "scroll target=\(targetName(target)) " +
            "anchor=\(anchorName(anchor)) frame=\(frameSummary(for: target)) animated=\(animated)"
        )

        if animated {
            withAnimation(.easeInOut(duration: 0.35)) {
                action()
            }
        } else {
            action()
        }
    }

    private func anchorName(_ anchor: UnitPoint) -> String {
        if anchor == .top { return "top" }
        if anchor == .center { return "center" }
        if anchor == .bottom { return "bottom" }
        return "(\(String(format: "%.2f", anchor.x)),\(String(format: "%.2f", anchor.y)))"
    }

    private func startWalkthrough() {
        activeSheet = nil
        showingOnboarding = false
        logWalkthrough("startWalkthrough cities=\(viewModel.cities.count) toolsExpanded=\(areToolsExpanded)")
        walkthroughCoordinator.start()
    }

    private func scheduleWalkthroughScroll(using proxy: ScrollViewProxy, reason: String) {
        let delays: [Double] = [0.0, 0.12, 0.26, 0.48]
        for (attempt, delay) in delays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard walkthroughCoordinator.isActive else { return }
                logWalkthrough("scrollAttempt reason=\(reason) attempt=\(attempt)")
                scrollWalkthroughTarget(using: proxy, animated: attempt == 0)
            }
        }
    }

    private func logWalkthrough(_ message: String) {
#if DEBUG
        Self.walkthroughLogger.debug("\(message, privacy: .public)")
#endif
    }

    private func targetName(_ target: HomeWalkthroughTarget) -> String {
        switch target {
        case .todaySnapshot:
            return "todaySnapshot"
        case .quickActions:
            return "quickActions"
        case .myCities:
            return "myCities"
        case .tools:
            return "tools"
        }
    }

    private func frameSummary(for target: HomeWalkthroughTarget) -> String {
        return rectSummary(walkthroughFrames[target])
    }

    private func allFrameSummary(_ frames: [HomeWalkthroughTarget: CGRect]) -> String {
        let ordered: [HomeWalkthroughTarget] = [.todaySnapshot, .quickActions, .myCities, .tools]
        return ordered
            .map { "\(targetName($0))=\(rectSummary(frames[$0]))" }
            .joined(separator: " | ")
    }

    private func rectSummary(_ rect: CGRect?) -> String {
        guard let rect else { return "nil" }
        let x = Int(rect.minX.rounded())
        let y = Int(rect.minY.rounded())
        let width = Int(rect.width.rounded())
        let height = Int(rect.height.rounded())
        return "x:\(x),y:\(y),w:\(width),h:\(height)"
    }

    // MARK: - iOS Force-Quit Hint (Widget Background Updates)

    private var forceQuitWidgetHint: some View {
        Group {
            if !hasDismissedForceQuitWidgetHint {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Widgets While Traveling")
                            .font(.subheadline.weight(.semibold))

                        Text("To keep the widget updated when you switch cities, do not force close the app (swipe up). iOS disables background updates when you force quit.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button {
                            // Quick path to inspect timeline/logs when debugging widget refresh.
                            activeSheet = .logs
                        } label: {
                            Label("View logs", systemImage: "doc.text.magnifyingglass")
                                .font(.footnote.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                    }

                    Spacer(minLength: 8)

                    Button {
                        hasDismissedForceQuitWidgetHint = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss notice")
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Color.blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}

// MARK: - Add City Search Sheet

/// Search sheet specifically for adding new cities to the list
struct AddCitySearchSheet: View {
    let canAddCity: Bool
    let remainingSlots: Int
    let onCitySelected: (CitySearchResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var completer = CitySearchCompleter()
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Capacity indicator
                if !canAddCity {
                    limitReachedBanner
                }

                // Search results list
                if completer.suggestions.isEmpty {
                    emptyState
                } else {
                    resultsList
                }
            }
            .navigationTitle("Add City")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "City, state, or country"
            )
            .onChange(of: searchText) { _, newValue in
                completer.update(query: newValue)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isSearchFocused = true
                }
            }
        }
    }

    private var limitReachedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            Text(
                String(
                    format: NSLocalizedString(
                        "You have reached the limit of %d cities",
                        comment: "City limit reached message"
                    ),
                    CityModel.maxCities
                )
            )
                .font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.15))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            if completer.isSearching {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Searching...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if searchText.isEmpty {
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text("Find a city")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Add cities to see time and temperature in different places")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)

                if remainingSlots > 0 {
                    Text(
                        String(
                            format: NSLocalizedString(
                                "%d slots available",
                                comment: "Remaining city slots"
                            ),
                            remainingSlots
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .padding(.top, 8)
                }
            } else {
                Image(systemName: "mappin.slash")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text("No results")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Try another name")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding()
    }

    private var resultsList: some View {
        List(completer.suggestions) { result in
            Button {
                if canAddCity {
                    selectCity(result)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title)
                            .font(.body)
                            .foregroundStyle(.primary)

                        if !result.subtitle.isEmpty {
                            Text(result.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if canAddCity {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.title3)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .disabled(!canAddCity)
            .opacity(canAddCity ? 1 : 0.5)
        }
        .listStyle(.plain)
    }

    private func selectCity(_ result: CitySearchResult) {
        onCitySelected(result)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
