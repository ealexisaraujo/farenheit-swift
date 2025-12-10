import SwiftUI
import UIKit

/// List of city cards with reorder and delete capabilities
/// Premium design with smooth animations and haptic feedback
/// Uses Apple-style drag-and-drop with real-time card movement
struct CityCardListView: View {
    @Binding var cities: [CityModel]
    @ObservedObject var timeService: TimeZoneService

    /// Callback when a city should be deleted
    var onDeleteCity: ((CityModel) -> Void)?

    /// Callback when cities are reordered
    var onReorder: ((IndexSet, Int) -> Void)?

    /// Callback when add city is tapped
    var onAddCity: (() -> Void)?

    /// Whether we're in edit/reorder mode
    @State private var isReorderMode = false

    /// City being deleted (for animation)
    @State private var deletingCity: UUID?

    /// Drag state tracking
    @State private var draggingItem: CityModel?
    @State private var dragOffset: CGFloat = 0
    @State private var currentDragIndex: Int?

    // Card dimensions for offset calculations
    private let cardHeight: CGFloat = 72
    private let cardSpacing: CGFloat = 12

    // Maximum cities allowed
    private let maxCities = CityModel.maxCities

    /// Check if there are editable cities (non-primary)
    private var hasEditableCities: Bool {
        cities.filter { !$0.isCurrentLocation && $0.sortOrder != 0 }.count > 0
    }

    /// Number of editable cities
    private var editableCitiesCount: Int {
        cities.filter { !$0.isCurrentLocation && $0.sortOrder != 0 }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with reorder button
            listHeader

            // City cards
            if isReorderMode {
                reorderableList
            } else {
                normalList
            }
        }
        // Auto-exit edit mode when no editable cities remain
        .onChange(of: editableCitiesCount) { _, newCount in
            if newCount == 0 && isReorderMode {
                withAnimation(.spring(response: 0.3)) {
                    isReorderMode = false
                }
            }
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

            // Reorder button - only show if there are editable cities
            if hasEditableCities {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        isReorderMode.toggle()
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isReorderMode ? "checkmark" : "arrow.up.arrow.down")
                            .font(.system(size: 12, weight: .semibold))
                        Text(isReorderMode ? "Listo" : "Ordenar")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(isReorderMode ? .green : .blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(isReorderMode ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
                    )
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 16)
    }

    // MARK: - Normal List

    private var normalList: some View {
        LazyVStack(spacing: 12) {
            ForEach(cities) { city in
                cityCard(for: city)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .scale(scale: 0.8).combined(with: .opacity)
                    ))
            }

            // Add city button
            if cities.count < maxCities {
                addCityButton
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: cities.count)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: deletingCity)
    }

    // MARK: - Reorderable List with Drag & Drop (Apple Style)

    private var reorderableList: some View {
        VStack(spacing: cardSpacing) {
            ForEach(Array(cities.enumerated()), id: \.element.id) { index, city in
                let isPrimary = city.isCurrentLocation || index == 0
                let isDragging = draggingItem?.id == city.id
                let neighborOffset = calculateNeighborOffset(for: city, at: index)

                reorderableCard(for: city, at: index, isPrimary: isPrimary)
                    .zIndex(isDragging ? 100 : Double(cities.count - index))
                    .offset(y: isDragging ? dragOffset : neighborOffset)
                    .scaleEffect(isDragging ? 1.05 : 1.0)
                    .opacity(isDragging ? 0.9 : 1.0)
                    .shadow(
                        color: isDragging ? .black.opacity(0.3) : .clear,
                        radius: isDragging ? 12 : 0,
                        y: isDragging ? 8 : 0
                    )
                    .animation(
                        isDragging ? nil : .spring(response: 0.3, dampingFraction: 0.7),
                        value: neighborOffset
                    )
                    .gesture(
                        isPrimary ? nil : makeDragGesture(for: city, at: index)
                    )
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: cities.map(\.id))
    }

    /// Calculate offset for neighboring cards during drag (not the dragged item)
    private func calculateNeighborOffset(for city: CityModel, at index: Int) -> CGFloat {
        // Don't offset the dragged item - it uses dragOffset directly
        guard draggingItem?.id != city.id else { return 0 }

        // If nothing is being dragged, no offset
        guard let draggingCity = draggingItem,
              let originalDragIndex = cities.firstIndex(where: { $0.id == draggingCity.id }) else {
            return 0
        }

        // Calculate the total distance per card slot
        let slotHeight = cardHeight + cardSpacing

        // Calculate how many slots the dragged item has moved based on dragOffset
        let slotsMoved = Int((dragOffset / slotHeight).rounded())

        // Calculate target index (where dragged item would go)
        let targetIndex = max(1, min(cities.count - 1, originalDragIndex + slotsMoved))

        // Determine if this card needs to move
        if originalDragIndex < targetIndex {
            // Dragging down: cards between original position and target move UP
            if index > originalDragIndex && index <= targetIndex {
                return -slotHeight
            }
        } else if originalDragIndex > targetIndex {
            // Dragging up: cards between target and original position move DOWN
            if index >= targetIndex && index < originalDragIndex {
                return slotHeight
            }
        }

        return 0
    }

    /// Create drag gesture for reordering
    private func makeDragGesture(for city: CityModel, at index: Int) -> some Gesture {
        LongPressGesture(minimumDuration: 0.15)
            .onEnded { _ in
                // Start drag
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    draggingItem = city
                    currentDragIndex = index
                }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
            .sequenced(before: DragGesture())
            .onChanged { value in
                switch value {
                case .second(true, let drag):
                    if let drag = drag {
                        dragOffset = drag.translation.height

                        // Haptic feedback when crossing slot boundaries
                        let slotHeight = cardHeight + cardSpacing
                        let slotsMoved = Int((dragOffset / slotHeight).rounded())
                        let potentialIndex = max(1, min(cities.count - 1, index + slotsMoved))

                        if potentialIndex != currentDragIndex {
                            UISelectionFeedbackGenerator().selectionChanged()
                            currentDragIndex = potentialIndex
                        }
                    }
                default:
                    break
                }
            }
            .onEnded { value in
                guard case .second(true, _) = value else {
                    resetDragState()
                    return
                }

                // Calculate final position
                let slotHeight = cardHeight + cardSpacing
                let slotsMoved = Int((dragOffset / slotHeight).rounded())
                let targetIndex = max(1, min(cities.count - 1, index + slotsMoved))

                // Perform the move if position changed
                if targetIndex != index {
                    let source = IndexSet(integer: index)
                    let destination = targetIndex > index ? targetIndex + 1 : targetIndex
                    onReorder?(source, destination)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }

                resetDragState()
            }
    }

    /// Reset all drag state
    private func resetDragState() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            draggingItem = nil
            dragOffset = 0
            currentDragIndex = nil
        }
    }

    private func reorderableCard(for city: CityModel, at index: Int, isPrimary: Bool) -> some View {
        HStack(spacing: 12) {
            // Drag handle (disabled for primary)
            if !isPrimary {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 44)
                    .contentShape(Rectangle())
            } else {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
            }

            // Position indicator
            ZStack {
                Circle()
                    .fill(isPrimary ? Color.blue : Color.secondary.opacity(0.3))
                    .frame(width: 28, height: 28)

                Text("\(index + 1)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isPrimary ? .white : .primary)
            }

            // City info
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
                        Text("\(Int(temp))°F")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                    Text(timeService.formattedTimeWithPeriod(city))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Move buttons (for non-primary cities)
            if !isPrimary {
                VStack(spacing: 4) {
                    // Move up
                    Button {
                        moveCity(at: index, direction: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(canMoveUp(at: index) ? .blue : .secondary.opacity(0.3))
                            .frame(width: 32, height: 24)
                    }
                    .disabled(!canMoveUp(at: index))

                    // Move down
                    Button {
                        moveCity(at: index, direction: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(canMoveDown(at: index) ? .blue : .secondary.opacity(0.3))
                            .frame(width: 32, height: 24)
                    }
                    .disabled(!canMoveDown(at: index))
                }
            }

            // Delete button (for non-primary cities)
            if !isPrimary {
                Button {
                    deleteCity(city)
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                        .frame(width: 32, height: 32)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(draggingItem?.id == city.id ? .regularMaterial : .ultraThinMaterial)
                .shadow(
                    color: draggingItem?.id == city.id ? .black.opacity(0.2) : .clear,
                    radius: 8,
                    y: 4
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isPrimary ? Color.blue.opacity(0.3) : Color.clear,
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - City Card

    @ViewBuilder
    private func cityCard(for city: CityModel) -> some View {
        let isPrimary = city.isCurrentLocation || city.sortOrder == 0

        CityCardView(
            city: city,
            timeService: timeService,
            isPrimary: isPrimary,
            onDelete: isPrimary ? nil : { deleteCity(city) }
        )
        .opacity(deletingCity == city.id ? 0.5 : 1)
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

    private func canMoveUp(at index: Int) -> Bool {
        // Can't move if at position 1 (position 0 is always current location)
        let minPosition = cities.first?.isCurrentLocation == true ? 1 : 0
        return index > minPosition
    }

    private func canMoveDown(at index: Int) -> Bool {
        return index < cities.count - 1
    }

    private func moveCity(at index: Int, direction: Int) {
        let newIndex = index + direction

        // Validate move
        let minIndex = cities.first?.isCurrentLocation == true ? 1 : 0
        guard newIndex >= minIndex && newIndex < cities.count else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            let source = IndexSet(integer: index)
            let destination = direction > 0 ? newIndex + 1 : newIndex
            onReorder?(source, destination)
        }

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
