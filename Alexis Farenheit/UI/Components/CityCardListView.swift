import SwiftUI
import UIKit

/// List of city cards with reorder and delete capabilities
/// Premium design with smooth animations and haptic feedback
struct CityCardListView: View {
    @Binding var cities: [CityModel]
    @ObservedObject var timeService: TimeZoneService

    /// Callback when a city should be deleted
    var onDeleteCity: ((CityModel) -> Void)?

    /// Callback when cities are reordered
    var onReorder: ((IndexSet, Int) -> Void)?

    /// Callback when add city is tapped
    var onAddCity: (() -> Void)?

    /// Whether we're in edit mode
    @State private var editMode: EditMode = .inactive

    /// City being deleted (for animation)
    @State private var deletingCity: UUID?

    // Maximum cities allowed
    private let maxCities = CityModel.maxCities

    var body: some View {
        VStack(spacing: 0) {
            // Header
            listHeader

            // City cards
            LazyVStack(spacing: 12) {
                ForEach(cities) { city in
                    cityCard(for: city)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                            removal: .scale(scale: 0.8).combined(with: .opacity)
                        ))
                }
                .onMove(perform: handleMove)

                // Add city button
                if cities.count < maxCities {
                    addCityButton
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: cities.count)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: deletingCity)
        }
    }

    // MARK: - Header

    private var listHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ciudades")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)

                Text("\(cities.count) de \(maxCities)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Edit button
            if cities.count > 1 {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        editMode = editMode == .active ? .inactive : .active
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(editMode == .active ? "Listo" : "Editar")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 16)
    }

    // MARK: - City Card

    @ViewBuilder
    private func cityCard(for city: CityModel) -> some View {
        let isPrimary = city.isCurrentLocation || city.sortOrder == 0

        ZStack {
            CityCardView(
                city: city,
                timeService: timeService,
                isPrimary: isPrimary,
                onDelete: isPrimary ? nil : { deleteCity(city) }
            )
            .opacity(deletingCity == city.id ? 0.5 : 1)

            // Delete overlay in edit mode
            if editMode == .active && !isPrimary {
                deleteOverlay(for: city)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: !isPrimary) {
            if !isPrimary {
                Button(role: .destructive) {
                    deleteCity(city)
                } label: {
                    Label("Eliminar", systemImage: "trash")
                }
            }
        }
    }

    private func deleteOverlay(for city: CityModel) -> some View {
        HStack {
            Spacer()

            Button {
                deleteCity(city)
            } label: {
                ZStack {
                    Circle()
                        .fill(.red)
                        .frame(width: 28, height: 28)

                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .offset(x: 10, y: 0)
        }
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Add Button

    private var addCityButton: some View {
        Button {
            onAddCity?()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.blue.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Agregar ciudad")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)

                    Text("\(maxCities - cities.count) lugares disponibles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.blue.opacity(0.3), .cyan.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 1, dash: [8, 4])
                            )
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Actions

    private func deleteCity(_ city: CityModel) {
        guard !city.isCurrentLocation && city.sortOrder != 0 else { return }

        withAnimation(.spring(response: 0.3)) {
            deletingCity = city.id
        }

        UINotificationFeedbackGenerator().notificationOccurred(.warning)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                onDeleteCity?(city)
                deletingCity = nil
            }
        }
    }

    private func handleMove(from source: IndexSet, to destination: Int) {
        // Prevent moving current location
        if source.contains(0) && cities.first?.isCurrentLocation == true {
            return
        }

        // Prevent moving to position 0 if current location is there
        if destination == 0 && cities.first?.isCurrentLocation == true {
            return
        }

        onReorder?(source, destination)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

// MARK: - Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Empty State

struct CityListEmptyView: View {
    var onAddCity: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Sin ciudades guardadas")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)

                Text("Agrega ciudades para ver la hora y temperatura en diferentes lugares del mundo")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                onAddCity()
            } label: {
                Label("Agregar ciudad", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Preview

#Preview("City List") {
    ZStack {
        Color.black.ignoresSafeArea()

        ScrollView {
            CityCardListView(
                cities: .constant(CityModel.samples),
                timeService: TimeZoneService.shared,
                onDeleteCity: { _ in },
                onReorder: { _, _ in },
                onAddCity: { }
            )
            .padding()
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Empty State") {
    ZStack {
        Color.black.ignoresSafeArea()

        CityListEmptyView(onAddCity: { })
            .padding()
    }
    .preferredColorScheme(.dark)
}
