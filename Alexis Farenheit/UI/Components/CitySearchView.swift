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
    }

    /// Update search query
    func update(query: String) {
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
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // MKErrorDomain error 5 = "loading throttled" - normal during fast typing
        isSearching = false
    }

    /// Clear all suggestions
    func clear() {
        suggestions = []
        isSearching = false
        completer.queryFragment = ""
    }
}

/// Button that opens the city search sheet
struct CitySearchButton: View {
    let currentCity: String
    let onCitySelected: (MKLocalSearchCompletion) -> Void

    @State private var isShowingSearch = false

    var body: some View {
        Button {
            isShowingSearch = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                Text("Buscar otra ciudad...")
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
            CitySearchSheet(onCitySelected: { completion in
                onCitySelected(completion)
                isShowingSearch = false
            })
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

/// Full-screen search sheet with proper keyboard handling
struct CitySearchSheet: View {
    let onCitySelected: (MKLocalSearchCompletion) -> Void

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
            .navigationTitle("Buscar Ciudad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Ciudad, estado o país"
            )
            .onChange(of: searchText) { _, newValue in
                completer.update(query: newValue)
            }
            .onAppear {
                // Auto-focus search field
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isSearchFocused = true
                }
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
                Text("Buscando...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if searchText.isEmpty {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text("Escribe para buscar")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Busca por nombre de ciudad, estado o país")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "mappin.slash")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text("Sin resultados")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Intenta con otro nombre")
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

    private func selectCity(_ suggestion: MKLocalSearchCompletion) {
        print("[CitySearch] Selected: \(suggestion.title)")
        onCitySelected(suggestion)
    }
}

// MARK: - Legacy View (kept for backwards compatibility)

/// Inline city search view - use CitySearchButton for better UX
struct CitySearchView: View {
    @Binding var searchText: String
    let onCitySelected: (MKLocalSearchCompletion) -> Void

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
                    Text("Buscando...")
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
        .accessibilityLabel("Búsqueda de ciudad")
    }

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

    private func selectCity(_ suggestion: MKLocalSearchCompletion) {
        print("[CitySearch] Selected: \(suggestion.title)")
        onCitySelected(suggestion)
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
        CitySearchButton(currentCity: "Chandler") { completion in
            print("Selected: \(completion.title)")
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Search Sheet") {
    CitySearchSheet { completion in
        print("Selected: \(completion.title)")
    }
    .preferredColorScheme(.dark)
}
