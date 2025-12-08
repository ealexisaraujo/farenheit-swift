import SwiftUI
import Combine
import MapKit

/// City search autocomplete using MapKit
/// Provides suggestions as user types and clears when a city is selected
@MainActor
final class CitySearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var suggestions: [MKLocalSearchCompletion] = []
    @Published var isSearching: Bool = false

    private let completer: MKLocalSearchCompleter = {
        let c = MKLocalSearchCompleter()
        c.resultTypes = .address
        return c
    }()

    override init() {
        super.init()
        completer.delegate = self
        print("[CitySearch] Completer initialized")
    }

    /// Update search query
    func update(query: String) {
        print("[CitySearch] Query: '\(query)'")

        if query.isEmpty {
            clear()
            return
        }

        completer.queryFragment = query
        isSearching = true
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results
        isSearching = false
        print("[CitySearch] Results: \(suggestions.count)")
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("[CitySearch] Error: \(error.localizedDescription)")
        isSearching = false
    }

    /// Clear all suggestions
    func clear() {
        print("[CitySearch] Clearing suggestions")
        suggestions = []
        isSearching = false
        completer.queryFragment = ""
    }
}

/// City search view with autocomplete dropdown
struct CitySearchView: View {
    @Binding var searchText: String
    let onCitySelected: (MKLocalSearchCompletion) -> Void

    @StateObject private var completer = CitySearchCompleter()
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Search field
            searchField

            // Loading indicator
            if completer.isSearching {
                HStack {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                    Text("Buscando...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }

            // Results list - only show when we have suggestions
            if !completer.suggestions.isEmpty {
                suggestionsList
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Búsqueda de ciudad")
    }

    // MARK: - Subviews

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Buscar ciudad...", text: $searchText)
                .textInputAutocapitalization(.words)
                .focused($isTextFieldFocused)
                .onChange(of: searchText) { _, newValue in
                    completer.update(query: newValue)
                }

            // Clear button - only show when there's text
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
            ForEach(completer.suggestions, id: \.self) { suggestion in
                suggestionRow(suggestion)

                // Divider between items (except last)
                if suggestion != completer.suggestions.last {
                    Divider()
                        .padding(.leading, 12)
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func suggestionRow(_ suggestion: MKLocalSearchCompletion) -> some View {
        Button {
            selectCity(suggestion)
        } label: {
            HStack {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)

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

    // MARK: - Actions

    private func selectCity(_ suggestion: MKLocalSearchCompletion) {
        print("[CitySearch] Selected: \(suggestion.title)")

        // 1. Call the selection handler
        onCitySelected(suggestion)

        // 2. Clear everything
        clearSearch()

        // 3. Dismiss keyboard
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

#Preview {
    StatefulPreviewWrapper("") { text in
        CitySearchView(searchText: text) { completion in
            print("Selected: \(completion.title)")
        }
        .padding()
    }
}
