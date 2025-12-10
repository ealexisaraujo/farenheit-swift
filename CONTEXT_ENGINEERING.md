# Context Engineering - Alexis Farenheit

## Resumen de Sesión

**Fecha:** Diciembre 2024
**Branch:** `elegant-chandrasekhar` (worktree)
**Estado:** Todas las tareas completadas y compilando exitosamente

---

## Características Implementadas

### 1. Sistema Multi-Ciudad con Zonas Horarias

#### Archivos Creados
- `Alexis Farenheit/Core/Models/CityModel.swift`
- `Alexis Farenheit/Core/Services/CityStorageService.swift`
- `Alexis Farenheit/Core/Services/TimeZoneService.swift`
- `Alexis Farenheit/UI/Components/TimeZoneSliderView.swift`
- `Alexis Farenheit/UI/Components/CityCardView.swift`
- `Alexis Farenheit/UI/Components/CityCardListView.swift`

#### CityModel.swift
```swift
struct CityModel: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var countryCode: String
    var latitude: Double
    var longitude: Double
    var timeZoneIdentifier: String
    var fahrenheit: Double?
    var lastUpdated: Date?
    var isCurrentLocation: Bool
    var sortOrder: Int

    static let maxCities = 5  // Límite freemium
}
```

#### TimeZoneService.swift - Detalles Críticos
- **Rango:** 0-1439 minutos (12:00 AM a 11:59 PM)
- **Sin wrapping:** Hard stops en los límites
- **Slider value:** `Double(selectedMinutes) / 1439.0`
- **Método clave:** `setSliderValue(_ value: Double)` clampea a 0...1

```swift
func setSliderValue(_ value: Double) {
    let clampedValue = max(0, min(1, value))
    selectedMinutes = Int(clampedValue * 1439)
}
```

---

### 2. Drag-and-Drop Estilo Apple

**Archivo:** `CityCardListView.swift`

#### Estados de Drag
```swift
@State private var draggingItem: CityModel?
@State private var dragOffset: CGFloat = 0
@State private var currentDragIndex: Int?

private let cardHeight: CGFloat = 72
private let cardSpacing: CGFloat = 12
```

#### Algoritmo de Offset para Cards Vecinas
```swift
// La card arrastrada usa dragOffset directamente
// Las cards vecinas usan calculateNeighborOffset con animación

private func calculateNeighborOffset(for city: CityModel, at index: Int) -> CGFloat {
    guard draggingItem?.id != city.id else { return 0 }
    guard let draggingCity = draggingItem,
          let originalDragIndex = cities.firstIndex(where: { $0.id == draggingCity.id }) else {
        return 0
    }

    let slotHeight = cardHeight + cardSpacing
    let slotsMoved = Int((dragOffset / slotHeight).rounded())
    let targetIndex = max(1, min(cities.count - 1, originalDragIndex + slotsMoved))

    if originalDragIndex < targetIndex {
        if index > originalDragIndex && index <= targetIndex {
            return -slotHeight  // Mover arriba
        }
    } else if originalDragIndex > targetIndex {
        if index >= targetIndex && index < originalDragIndex {
            return slotHeight   // Mover abajo
        }
    }
    return 0
}
```

#### Aplicación del Offset con Animación
```swift
reorderableCard(...)
    .offset(y: isDragging ? dragOffset : neighborOffset)
    .animation(
        isDragging ? nil : .spring(response: 0.3, dampingFraction: 0.7),
        value: neighborOffset
    )
```

#### Gesto Combinado (LongPress + Drag)
```swift
LongPressGesture(minimumDuration: 0.15)
    .onEnded { _ in
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            draggingItem = city
            currentDragIndex = index
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    .sequenced(before: DragGesture())
    .onChanged { ... }
    .onEnded { ... }
```

#### Auto-Exit Edit Mode
```swift
.onChange(of: editableCitiesCount) { _, newCount in
    if newCount == 0 && isReorderMode {
        withAnimation(.spring(response: 0.3)) {
            isReorderMode = false
        }
    }
}
```

---

### 3. Actualización Automática de Widgets

**Archivo:** `CityStorageService.swift`

```swift
import WidgetKit

private func saveCities() {
    do {
        let data = try JSONEncoder().encode(cities)
        defaults?.set(data, forKey: citiesKey)
        defaults?.synchronize()

        // CRÍTICO: Recargar widgets al cambiar ciudades
        WidgetCenter.shared.reloadAllTimelines()
    } catch {
        // ...
    }
}
```

---

### 4. Widget Medium - Diseño 2025

**Archivo:** `AlexisExtensionFarenheit.swift`

#### Estructura
- **Izquierda:** Ciudad principal con temperatura grande
- **Divisor:** Línea vertical semitransparente
- **Derecha:** Segunda ciudad O tabla de conversión (fallback)

```swift
var body: some View {
    HStack(spacing: 16) {
        primaryCityView

        Rectangle()
            .fill(.white.opacity(0.2))
            .frame(width: 1)
            .padding(.vertical, 8)

        if let secondCity = entry.cities.dropFirst().first {
            secondaryCityView(secondCity)
        } else {
            conversionView
        }
    }
    .padding(16)
}
```

#### Segunda Ciudad View
- Icono día/noche (sun.max.fill / moon.fill)
- Temperatura en °F y °C
- Hora local del timezone

---

### 5. Lazy Loading para Performance

**Archivo:** `HomeViewModel.swift`

#### Carga Inicial Escalonada
```swift
private func lazyLoadInitialWeather() {
    let staleThreshold: TimeInterval = 15 * 60  // 15 minutos

    let citiesToRefresh = cities.dropFirst().filter { city in
        guard let lastUpdated = city.lastUpdated else {
            return city.fahrenheit == nil
        }
        return Date().timeIntervalSince(lastUpdated) > staleThreshold
    }

    // Escalonar requests con 500ms entre cada uno
    for (index, city) in citiesToRefresh.enumerated() {
        let delay = Double(index) * 0.5
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run {
                fetchWeather(for: city)
            }
        }
    }
}
```

#### Refresh All Cities (Escalonado)
```swift
func refreshAllCities() {
    // Ciudad primaria: inmediato
    if let primary = cities.first {
        fetchWeather(for: primary)
    }

    // Resto: escalonado 300ms
    let remainingCities = Array(cities.dropFirst())
    for (index, city) in remainingCities.enumerated() {
        let delay = Double(index + 1) * 0.3
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run {
                fetchWeather(for: city)
            }
        }
    }
}
```

---

## Reglas de Negocio Importantes

### Ciudad Primaria (Current Location)
- **Siempre en posición 0**
- **No se puede eliminar**
- **No se puede reordenar**
- Identificada por `isCurrentLocation == true` O `sortOrder == 0`

### Límite de Ciudades
- **Máximo: 5 ciudades** (preparado para modelo freemium)
- Definido en `CityModel.maxCities`

### Detección de Duplicados
- Por distancia: < 1km = duplicado
- Implementado en `CityStorageService.addCity()`

---

## Flujo de Datos Widget

```
App agrega ciudad
    ↓
CityStorageService.addCity()
    ↓
saveCities() → UserDefaults (App Group)
    ↓
WidgetCenter.shared.reloadAllTimelines()
    ↓
TemperatureProvider.getTimeline()
    ↓
loadSavedCities() → Decode desde App Group
    ↓
Widget muestra nuevas ciudades
```

---

## Dependencias Entre Archivos

```
ContentView
    └── HomeViewModel
        ├── CityStorageService (singleton)
        ├── TimeZoneService (singleton)
        ├── LocationService
        └── WeatherService

CityCardListView
    ├── CityCardView
    └── TimeZoneService

TimeZoneSliderView
    └── TimeZoneService

Widget (AlexisExtensionFarenheit)
    └── Lee de App Group (UserDefaults)
```

---

## Haptic Feedback Implementado

| Acción | Tipo | Ubicación |
|--------|------|-----------|
| Inicio de drag | `.medium` | `makeDragGesture()` |
| Cruzar slot | `selectionChanged()` | `makeDragGesture()` |
| Soltar card | `.medium` | `makeDragGesture()` |
| Eliminar ciudad | `.warning` | `deleteCity()` |
| Toggle edit mode | `.light` | `listHeader` |
| Agregar ciudad | `.medium` | `addCityButton` |
| Límites del slider | `.warning` | `TimeZoneSliderView` |

---

## Problemas Conocidos / Warnings

1. **CLGeocoder deprecated iOS 26+** - Funcional pero genera warnings
2. **CFPrefsPlistSource error** - Ignorar si App Groups configurado correctamente

---

## Configuración Requerida

### App Groups
- ID: `group.alexisaraujo.alexisfarenheit`
- Requerido en: Main App + Widget Extension

### Imports Necesarios por Archivo

| Archivo | Imports Especiales |
|---------|-------------------|
| CityStorageService | `WidgetKit` |
| CityCardListView | `UIKit` (haptics) |
| TimeZoneSliderView | `UIKit` (haptics) |
| HomeViewModel | `SwiftUI` (para `move(fromOffsets:)`) |

---

## Para Continuar Desarrollo

### Si necesitas modificar drag-and-drop:
1. Ajustar `cardHeight` y `cardSpacing` en `CityCardListView`
2. El algoritmo de offset está en `calculateOffset(for:at:)`
3. El gesto está en `makeDragGesture(for:at:)`

### Si necesitas modificar widgets:
1. Cambios en `AlexisExtensionFarenheit.swift`
2. Datos vienen de `loadSavedCities()` en `TemperatureProvider`
3. Modelo de datos: `CityWidgetData` (simplificado de `CityModel`)

### Si necesitas modificar el slider de tiempo:
1. Lógica en `TimeZoneService.swift`
2. UI en `TimeZoneSliderView.swift`
3. Rango: 0-1439 minutos, NO usar offset

---

---

## Optimizaciones de Performance (Sesión 2)

### Problema: Múltiples Fetches Duplicados al Iniciar

**Síntomas en logs:**
- Weather se fetch 8+ veces para la misma ciudad
- Widget reload se dispara en cada update de temperatura
- "Updated city: Chandler" aparece repetidamente

**Soluciones Implementadas:**

#### 1. Throttling de Fetches por Ciudad
```swift
// HomeViewModel.swift
private var lastFetchTime: [UUID: Date] = [:]
private let minimumFetchInterval: TimeInterval = 30

func fetchWeather(for city: CityModel) {
    if let lastFetch = lastFetchTime[city.id],
       Date().timeIntervalSince(lastFetch) < minimumFetchInterval {
        logger.debug("Skipping - fetched recently")
        return
    }
    lastFetchTime[city.id] = Date()
    // ... fetch
}
```

#### 2. Debounce en Location Updates
```swift
locationService.$lastLocation
    .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
    .removeDuplicates { old, new in
        old.distance(from: new) < 100  // 100 metros
    }
```

#### 3. Widget Reload Throttling
```swift
// CityStorageService.swift
private var lastWidgetReload: Date?
private let widgetReloadThrottle: TimeInterval = 10

func saveCities(reloadWidgets: Bool = true) {
    // Solo recargar si pasaron >10 segundos
}

func saveCitiesQuietly() {
    saveCities(reloadWidgets: false)  // Para updates de temperatura
}
```

#### 4. Flag de Carga Inicial
```swift
private var hasCompletedInitialLoad = false

func onAppear() {
    guard !hasCompletedInitialLoad else { return }
    hasCompletedInitialLoad = true
}
```

#### 5. Eliminación de Fetch Duplicado
```swift
func onBecameActive() {
    // Solo llamar refreshAllCities()
    // NO llamar refreshWeatherIfPossible() por separado
    refreshAllCities()
}
```

---

## Commits Relacionados

- feat: add multi-city support with timezone slider
- fix: slider hard stops at 12AM/11:59PM
- feat: add reorder button and large widget multi-city
- fix: edit mode auto-exit, drag-and-drop, medium widget
- fix: widget updates on city changes, Apple-style drag
- perf: fix duplicate weather fetches, add throttling
- fix: neighboring cards animate during drag-and-drop
