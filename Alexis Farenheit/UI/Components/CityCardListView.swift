import SwiftUI
import UniformTypeIdentifiers

/// List of city cards with reorder and delete capabilities
/// Uses LazyVStack for ScrollView compatibility with custom drag-and-drop
struct CityCardListView: View {
    @Binding var cities: [CityModel]
    @ObservedObject var timeService: TimeZoneService

    var onDeleteCity: ((CityModel) -> Void)?
    var onReorder: ((IndexSet, Int) -> Void)?
    var onAddCity: (() -> Void)?
    var onTapCity: ((CityModel) -> Void)?

    @State private var isEditMode = false
    @State private var deletingCity: UUID?
    @State private var draggingCityID: UUID?

    @State private var sensoryFeedbackTrigger = 0
    @State private var pendingSensoryFeedback: SensoryFeedback = .impact(weight: .light)

    private let cardSpacing: CGFloat = 12
    private let maxCities = CityModel.maxCities

    var body: some View {
        VStack(spacing: 0) {
            listHeader
            cityList
        }
        .sensoryFeedback(pendingSensoryFeedback, trigger: sensoryFeedbackTrigger)
    }

    private func emitFeedback(_ feedback: SensoryFeedback) {
        pendingSensoryFeedback = feedback
        sensoryFeedbackTrigger += 1
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

            if cities.count > 1 {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        isEditMode.toggle()
                    }
                    emitFeedback(.impact(weight: .light))
                } label: {
                    Text(isEditMode ? "Listo" : "Editar")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isEditMode ? .green : .blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isEditMode ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
                        )
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 16)
    }

    // MARK: - City List

    private var cityList: some View {
        LazyVStack(spacing: cardSpacing) {
            ForEach(Array(cities.enumerated()), id: \.element.id) { index, city in
                let isPrimary = city.isCurrentLocation || index == 0

                cityRow(for: city, at: index, isPrimary: isPrimary)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
            }

            if cities.count < maxCities {
                addCityButton
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: cities.map(\.id))
    }

    // MARK: - City Row

    @ViewBuilder
    private func cityRow(for city: CityModel, at index: Int, isPrimary: Bool) -> some View {
        if isEditMode {
            // Edit mode: show drag handles
            editModeRow(for: city, at: index, isPrimary: isPrimary)
        } else {
            // Normal mode: swipe to delete, tap to edit
            normalModeRow(for: city, isPrimary: isPrimary)
        }
    }

    // MARK: - Normal Mode Row

    @ViewBuilder
    private func normalModeRow(for city: CityModel, isPrimary: Bool) -> some View {
        CityCardView(city: city, timeService: timeService, isPrimary: isPrimary, onDelete: nil)
            .onTapGesture { onTapCity?(city) }
            .opacity(deletingCity == city.id ? 0.5 : 1.0)
    }

    // MARK: - Edit Mode Row (Drag & Drop)

    @ViewBuilder
    private func editModeRow(for city: CityModel, at index: Int, isPrimary: Bool) -> some View {
        HStack(spacing: 12) {
            // Drag handle or lock icon
            if isPrimary {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
            } else {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 44)
                    .contentShape(Rectangle())
                    .onDrag {
                        draggingCityID = city.id
                        emitFeedback(.impact(weight: .medium))
                        return NSItemProvider(object: city.id.uuidString as NSString)
                    }
            }

            // City info compact
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if isPrimary {
                        Image(systemName: "location.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    Text(city.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                HStack(spacing: 8) {
                    if let temp = city.fahrenheit {
                        Text("\(temp.roundedInt)°F")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                    Text(timeService.formattedTimeWithPeriod(city))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Delete button (not for primary)
            if !isPrimary {
                Button {
                    deleteCity(city)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            if isPrimary {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.blue.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
        .onDrop(of: [UTType.text], delegate: ReorderDropDelegate(
            targetCity: city,
            cities: $cities,
            draggingCityID: $draggingCityID,
            onReorder: onReorder,
            emitFeedback: emitFeedback
        ))
    }

    // MARK: - Add Button

    private var addCityButton: some View {
        Button {
            onAddCity?()
            emitFeedback(.impact(weight: .medium))
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
        emitFeedback(.warning)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                onDeleteCity?(city)
                deletingCity = nil
            }
        }
    }
}

// MARK: - Reorder Drop Delegate

struct ReorderDropDelegate: DropDelegate {
    let targetCity: CityModel
    @Binding var cities: [CityModel]
    @Binding var draggingCityID: UUID?
    let onReorder: ((IndexSet, Int) -> Void)?
    let emitFeedback: (SensoryFeedback) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func dropEntered(info: DropInfo) {
        guard let draggingID = draggingCityID, draggingID != targetCity.id else { return }

        guard let fromIndex = cities.firstIndex(where: { $0.id == draggingID }),
              let toIndex = cities.firstIndex(where: { $0.id == targetCity.id }) else { return }

        let minIndex = cities.first?.isCurrentLocation == true ? 1 : 0
        guard fromIndex >= minIndex, toIndex >= minIndex, fromIndex != toIndex else { return }

        let source = IndexSet(integer: fromIndex)
        let destination = toIndex > fromIndex ? toIndex + 1 : toIndex

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            onReorder?(source, destination)
        }
        emitFeedback(.selection)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingCityID = nil
        emitFeedback(.impact(weight: .light))
        return true
    }
}

// MARK: - Button Styles

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
                onAddCity: { },
                onTapCity: { _ in }
            )
            .padding()
        }
    }
    .preferredColorScheme(.dark)
}
