import SwiftUI
import Combine
import MapKit

/// Search result model that can come from MKLocalSearch
struct CitySearchResult: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
    let mapItem: MKMapItem

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: CitySearchResult, rhs: CitySearchResult) -> Bool {
        lhs.id == rhs.id
    }
}

/// City search using MKLocalSearch for better results with small cities
/// MKLocalSearchCompleter doesn't find cities like "Metepec" in Mexico
@MainActor
final class CitySearchCompleter: ObservableObject {
    @Published var suggestions: [CitySearchResult] = []
    @Published var isSearching: Bool = false

    // Legacy property for backwards compatibility
    var legacySuggestions: [MKLocalSearchCompletion] { [] }

    // Debouncing to prevent searching on every keystroke
    private var searchWorkItem: DispatchWorkItem?
    private var currentSearch: MKLocalSearch?
    private let debounceDelay: TimeInterval = 0.4 // Wait 400ms after typing stops

    /// Update search query (debounced)
    func update(query: String) {
        // Cancel previous search
        searchWorkItem?.cancel()
        currentSearch?.cancel()

        if query.isEmpty {
            clear()
            return
        }

        // Disable file logging during active search to prevent I/O blocking
        SharedLogger.shared.fileLoggingEnabled = false

        // Debounce: wait for user to stop typing
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.performSearch(query: query)
        }

        searchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceDelay, execute: workItem)
    }

    private func performSearch(query: String) {
        isSearching = true

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        // Don't restrict to a specific region to allow worldwide search

        let search = MKLocalSearch(request: request)
        currentSearch = search

        search.start { [weak self] response, error in
            Task { @MainActor in
                guard let self else { return }

                self.isSearching = false

                // Re-enable file logging
                SharedLogger.shared.fileLoggingEnabled = true

                if let error = error {
                    // MKErrorDomain error 4 = cancelled (normal during typing)
                    let nsError = error as NSError
                    if nsError.code != 4 {
                        print("[CitySearch] Search error: \(error.localizedDescription)")
                    }
                    return
                }

                guard let response = response else {
                    self.suggestions = []
                    return
                }

                // Convert MKMapItems to CitySearchResults
                // Filter to only include places that look like cities/localities
                self.suggestions = response.mapItems.compactMap { item -> CitySearchResult? in
                    // Skip items without a name
                    guard let name = item.name, !name.isEmpty else { return nil }

                    // Build subtitle from location info
                    let subtitle = Self.buildSubtitle(for: item, excludingName: name)

                    return CitySearchResult(
                        title: name,
                        subtitle: subtitle,
                        mapItem: item
                    )
                }

                print("[CitySearch] Found \(self.suggestions.count) results for '\(query)'")
            }
        }
    }

    /// Clear all suggestions
    func clear() {
        // Cancel any pending search
        searchWorkItem?.cancel()
        searchWorkItem = nil
        currentSearch?.cancel()
        currentSearch = nil

        // Re-enable file logging when search is cleared
        SharedLogger.shared.fileLoggingEnabled = true

        suggestions = []
        isSearching = false
    }

    /// Build subtitle string from MKMapItem
    /// Uses address for iOS 26+, placemark for older versions
    @MainActor
    private static func buildSubtitle(for item: MKMapItem, excludingName name: String) -> String {
        if #available(iOS 26.0, *) {
            // iOS 26+: Use MKAddress shortAddress or fullAddress
            if let address = item.address {
                // Use shortAddress if available, otherwise clean up fullAddress
                if let shortAddr = address.shortAddress, !shortAddr.isEmpty {
                    // Remove the name if it appears at the start
                    return shortAddr
                        .replacingOccurrences(of: "\(name), ", with: "")
                        .replacingOccurrences(of: "\(name)\n", with: "")
                        .replacingOccurrences(of: "\n", with: ", ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    // Use fullAddress as fallback
                    return address.fullAddress
                        .replacingOccurrences(of: "\(name), ", with: "")
                        .replacingOccurrences(of: "\(name)\n", with: "")
                        .replacingOccurrences(of: "\n", with: ", ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return ""
        } else {
            // Legacy: use placemark properties
            let subtitleParts = [
                item.placemark.locality != name ? item.placemark.locality : nil,
                item.placemark.administrativeArea,
                item.placemark.country
            ].compactMap { $0 }
            return subtitleParts.joined(separator: ", ")
        }
    }
}

/// Button that opens the city search sheet
struct CitySearchButton: View {
    let currentCity: String
    let onCitySelected: (CitySearchResult) -> Void

    @State private var isShowingSearch = false

    var body: some View {
        Button {
            isShowingSearch = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                Text("Search another city...")
                    .foregroundStyle(.secondary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isShowingSearch) {
            CitySearchSheet(onCitySelected: { result in
                onCitySelected(result)
                isShowingSearch = false
            })
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .onAppear {
                // Disable file logging when search opens
                SharedLogger.shared.fileLoggingEnabled = false
            }
            .onDisappear {
                // Re-enable file logging when search closes
                SharedLogger.shared.fileLoggingEnabled = true
            }
        }
    }
}

/// Full-screen search sheet with proper keyboard handling
struct CitySearchSheet: View {
    let onCitySelected: (CitySearchResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var completer = CitySearchCompleter()
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search results list
                if completer.suggestions.isEmpty {
                    emptyState
                } else {
                    resultsList
                }
            }
            .navigationTitle("Search City")
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
                // Disable file logging when search sheet appears to prevent I/O blocking
                SharedLogger.shared.fileLoggingEnabled = false

                // Auto-focus search field
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isSearchFocused = true
                }
            }
            .onDisappear {
                // Re-enable file logging when search sheet closes
                SharedLogger.shared.fileLoggingEnabled = true
            }
        }
    }

    // MARK: - Subviews

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
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text("Type to search")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Search by city, state, or country name")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
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
        List(completer.suggestions, id: \.self) { suggestion in
            Button {
                selectCity(suggestion)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title)
                            .font(.body)
                            .foregroundStyle(.primary)

                        if !suggestion.subtitle.isEmpty {
                            Text(suggestion.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
    }

    // MARK: - Actions

    private func selectCity(_ result: CitySearchResult) {
        print("[CitySearch] Selected: \(result.title)")
        onCitySelected(result)
    }
}

// MARK: - Legacy View (kept for backwards compatibility)

/// Inline city search view - use CitySearchButton for better UX
struct CitySearchView: View {
    @Binding var searchText: String
    let onCitySelected: (CitySearchResult) -> Void

    @StateObject private var completer = CitySearchCompleter()
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField

            if completer.isSearching {
                HStack {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                    Text("Searching...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }

            if !completer.suggestions.isEmpty {
                suggestionsList
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("City search")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search for a city...", text: $searchText)
                .textInputAutocapitalization(.words)
                .focused($isTextFieldFocused)
                .onChange(of: searchText) { _, newValue in
                    completer.update(query: newValue)
                }

            if !searchText.isEmpty {
                Button {
                    clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var suggestionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(completer.suggestions.prefix(5), id: \.self) { suggestion in
                suggestionRow(suggestion)

                if suggestion != completer.suggestions.prefix(5).last {
                    Divider()
                        .padding(.leading, 12)
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func suggestionRow(_ result: CitySearchResult) -> some View {
        Button {
            selectCity(result)
        } label: {
            HStack {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)

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

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func selectCity(_ result: CitySearchResult) {
        print("[CitySearch] Selected: \(result.title)")
        onCitySelected(result)
        clearSearch()
        isTextFieldFocused = false
    }

    private func clearSearch() {
        searchText = ""
        completer.clear()
        isTextFieldFocused = false
    }
}

// MARK: - Preview Helper

struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    let content: (Binding<Value>) -> Content

    init(_ initialValue: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        self._value = State(initialValue: initialValue)
        self.content = content
    }

    var body: some View {
        content($value)
    }
}

#Preview("Search Button") {
    ZStack {
        Color.black.ignoresSafeArea()
        CitySearchButton(currentCity: "Chandler") { result in
            print("Selected: \(result.title)")
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Search Sheet") {
    CitySearchSheet { result in
        print("Selected: \(result.title)")
    }
    .preferredColorScheme(.dark)
}
