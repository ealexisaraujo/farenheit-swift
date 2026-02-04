import SwiftUI
import MapKit
import UIKit
import Foundation

/// Main content view for the Temperature Converter app.
/// Features multi-city support with time zone slider and premium card design.
/// Automatically refreshes weather when app returns to foreground.
struct ContentView: View {
    @StateObject private var viewModel = HomeViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingLogViewer = false
    @State private var showingCitySearch = false
    @AppStorage("hasDismissedForceQuitWidgetHint") private var hasDismissedForceQuitWidgetHint = false

    var body: some View {
        ZStack {
            // Background gradient
            backgroundGradient

            ScrollView {
                VStack(spacing: 24) {
                    // Header with settings
                    header

                    // iOS limitation hint (important for widget travel refresh debugging):
                    // Force-quitting the app disables background execution, so Significant Location Changes / BGTasks won't run.
                    forceQuitWidgetHint

                    // Time Zone Slider
                    TimeZoneSliderView(
                        timeService: viewModel.timeService,
                        referenceCity: viewModel.primaryCity
                    )

                    // City Cards Section
                    cityCardsSection

                    // Temperature Converter (existing feature)
                    ConversionSliderView(fahrenheit: $viewModel.manualFahrenheit)

                    // Error message
                    if let error = viewModel.errorMessage {
                        errorBanner(error)
                    }

                    // Action buttons
                    actionButtons

                    // Last update time
                    lastUpdateSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
        }
        .preferredColorScheme(.dark)
        .task { viewModel.onAppear() }
        // Auto-refresh when app comes back to foreground
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                viewModel.onBecameActive()
            }
        }
        .sheet(isPresented: $showingLogViewer) {
            LogViewerView()
        }
        .sheet(isPresented: $showingCitySearch) {
            AddCitySearchSheet(
                canAddCity: viewModel.canAddCity,
                remainingSlots: viewModel.remainingCitySlots
            ) { completion in
                viewModel.addCity(from: completion)
                showingCitySearch = false
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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

            // Log viewer button (debug)
            Button {
                showingLogViewer = true
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

    // MARK: - City Cards Section

    private var cityCardsSection: some View {
        VStack(spacing: 0) {
            if viewModel.cities.isEmpty {
                // Empty state - waiting for location
                emptyLocationState
            } else {
                // City card list
                CityCardListView(
                    cities: $viewModel.cities,
                    timeService: viewModel.timeService,
                    onDeleteCity: { city in
                        viewModel.removeCity(city)
                    },
                    onReorder: { source, destination in
                        viewModel.moveCities(from: source, to: destination)
                    },
                    onAddCity: {
                        showingCitySearch = true
                    }
                )
            }
        }
    }

    private var emptyLocationState: some View {
        VStack(spacing: 16) {
            if viewModel.authorizationStatus == .notDetermined {
                // Waiting for permission
                ProgressView()
                    .scaleEffect(1.2)
                Text("Requesting location permission...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                showingCitySearch = true
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

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Refresh all button
            Button {
                viewModel.forceRefresh()
            } label: {
                Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(viewModel.isLoadingWeather)

            // Settings button (if location denied)
            if viewModel.authorizationStatus == .denied || viewModel.authorizationStatus == .restricted {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Image(systemName: "gear")
                        .font(.title3)
                        .padding(12)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .accessibilityLabel("Open Settings")
            }
        }
    }

    // MARK: - Last Update

    private var lastUpdateSection: some View {
        Group {
            if let lastUpdate = viewModel.lastUpdateTime {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text("Updated:")
                    Text(lastUpdate, style: .relative)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
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
                            showingLogViewer = true
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
