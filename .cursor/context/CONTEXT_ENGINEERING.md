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

## Optimizaciones de Performance (Sesión 3 - Diciembre 2024)

### Problema: FileIO Blocking y Widget Sync

**Síntomas en logs:**
- `LogFileWrite: 4.37s` - Escrituras bloqueantes
- `LogFileRead: 2.35s` - Lecturas lentas al inicio
- `END without START` - Race conditions en performance tracking
- `"app_logs.json.tmp" couldn't be moved` - Error de archivo temporal
- Widget mostraba ciudad diferente a la app

**Soluciones Implementadas:**

#### 1. Simplificación de SharedLogger
```swift
// Antes: Temp file + move (causaba errores)
// Después: Data.write directo con .atomic
try data.write(to: fileURL, options: [.atomic])

// Cache persistente (no expira por tiempo)
private var cachedEntries: [LogEntry]?
private var cacheIsValid: Bool = false
```

#### 2. Eliminación de Performance Tracking en FileIO
```swift
// Removido startOperation/endOperation en SharedLogger
// Solo NSLog y OSLog - sin file I/O durante operaciones
```

#### 3. Widget Location Sync
```swift
// En fetchWeather(for city:) - sincroniza widget cuando es current location
if cities[index].isCurrentLocation {
    WidgetDataService.shared.saveTemperature(...)
    defaults.set(updatedCity.latitude, forKey: "last_latitude")
    defaults.set(updatedCity.longitude, forKey: "last_longitude")
}

// En updateCurrentLocationCity() - guarda coordenadas inmediatamente
if let defaults = UserDefaults(suiteName: appGroupID) {
    defaults.set(location.coordinate.latitude, forKey: "last_latitude")
    defaults.set(location.coordinate.longitude, forKey: "last_longitude")
}
```

#### 4. CityStorageService - Widget Reload Activo
```swift
// Antes: saveCitiesQuietly() no recargaba widgets
// Después: Siempre usa saveCities() con throttling interno
func updateCity(_ city: CityModel) {
    cities[index] = city
    saveCities() // Reload widgets (throttled internally)
}
```

---

## Significant Location Changes (Sesión 3 - Diciembre 2024)

### Arquitectura de Background Location

```
┌─────────────────────────────────────────────────────────────────┐
│                         MAIN APP                                 │
│                                                                  │
│  ┌──────────────────┐      ┌─────────────────────────────────┐  │
│  │  HomeViewModel   │      │    BackgroundTaskService        │  │
│  │  LocationService │      │    (dedicated LocationService)  │  │
│  │  (foreground)    │      │    - Significant Location Changes│  │
│  └────────┬─────────┘      │    - BGAppRefreshTask           │  │
│           │                └──────────────┬──────────────────┘  │
│           │                               │                      │
│           ▼                               ▼                      │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              App Group (UserDefaults)                        ││
│  │  - last_latitude, last_longitude (coordenadas actuales)     ││
│  │  - widget_city, widget_country, widget_fahrenheit           ││
│  │  - saved_cities (lista de ciudades)                         ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

### Flujo cuando usuario se mueve de ciudad (app cerrada)

1. **Sistema detecta** movimiento significativo (~500m+, torres celulares)
2. **iOS despierta** la app en background
3. **LocationService** recibe `didUpdateLocations`
4. **Callback** `onSignificantLocationChange` se dispara
5. **BackgroundTaskService**:
   - Guarda nuevas coordenadas en App Group
   - Hace reverse geocode para nombre de ciudad
   - Fetcha weather de WeatherKit
   - Actualiza widget via `WidgetDataService.saveTemperature()`
6. **Widget se recarga** con la nueva ciudad y temperatura

### Archivos Modificados

| Archivo | Cambios |
|---------|---------|
| `LocationService.swift` | + `onSignificantLocationChange` callback, + `startMonitoringSignificantLocationChanges()`, + `stopMonitoringSignificantLocationChanges()` |
| `BackgroundTaskService.swift` | + `setupBackgroundLocationMonitoring()`, + `handleSignificantLocationChange()`, + `fetchWeatherAndUpdateWidget()` |
| `Alexis_FarenheitApp.swift` | + Setup y lifecycle de significant location monitoring |

### Código Clave - LocationService

```swift
/// Callback when location changes significantly (for background updates)
var onSignificantLocationChange: ((CLLocation) -> Void)?

func startMonitoringSignificantLocationChanges() {
    guard CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
    locationManager.startMonitoringSignificantLocationChanges()
    isMonitoringSignificantChanges = true
}

func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    // Check if this is a significant location change (background update)
    let isSignificantChange = isMonitoringSignificantChanges && !isRequesting

    if isSignificantChange {
        onSignificantLocationChange?(location)
    }
}
```

### Código Clave - BackgroundTaskService

```swift
func setupBackgroundLocationMonitoring() {
    let bgLocationService = LocationService()
    self.locationService = bgLocationService

    bgLocationService.onSignificantLocationChange = { [weak self] location in
        self?.handleSignificantLocationChange(location)
    }
}

private func handleSignificantLocationChange(_ location: CLLocation) {
    saveLocationToAppGroup(location)
    Task {
        await fetchWeatherAndUpdateWidget(for: location)
    }
}
```

### Requisitos para Funcionamiento

1. ✅ **Permiso "Always"** - Usuario debe dar permiso "Siempre"
2. ✅ **`NSLocationAlwaysAndWhenInUseUsageDescription`** - Ya configurado
3. ✅ **No requiere Background Mode "Location updates"** - Significant Location Changes es especial

### Limitaciones

- **~500m mínimo** - iOS solo notifica cambios "significativos"
- **iOS decide cuándo** - No hay garantía de tiempo exacto
- **Requiere permiso "Always"** - Con "When In Use" solo funciona en foreground
- **Batería optimizada** - Usa torres celulares, no GPS continuo

---

## Commits Relacionados

- feat: add multi-city support with timezone slider
- fix: slider hard stops at 12AM/11:59PM
- feat: add reorder button and large widget multi-city
- fix: edit mode auto-exit, drag-and-drop, medium widget
- fix: widget updates on city changes, Apple-style drag
- perf: fix duplicate weather fetches, add throttling
- fix: neighboring cards animate during drag-and-drop
- perf: simplify SharedLogger, fix cache, remove FileIO tracking
- fix: widget location sync with current location city
- feat: add significant location changes for background updates
- refactor: use saved_cities as single source of truth for widget data
- fix: use lastUpdated timestamp to determine cache freshness
- fix: consistent temperature rounding across app and widgets

---

## Widget Data Unification (Sesión 4 - Diciembre 2024)

### Problema: Race Condition entre App y Widget

**Síntomas en logs:**
- Widget mostraba "Tempe, 74°F" mientras la app ya tenía "Chandler, 74°F"
- `reloadAllTimelines()` se llamaba pero widgets usaban datos viejos
- Dos fuentes de datos separadas: `widget_city` y `saved_cities`

**Causa Raíz:**
El widget leía de dos lugares diferentes:
1. `loadCachedData()` → `widget_city` (legacy, via WidgetDataService)
2. `loadSavedCities()` → `saved_cities` (via CityStorageService)

Cuando cambiabas de ciudad, había una race condition donde el widget podía leer `widget_city` antes de que se actualizara.

### Solución: Single Source of Truth

**Decisión:** El widget ahora usa **solo `saved_cities`** como fuente de verdad.

#### Cambios en AlexisExtensionFarenheit.swift

```swift
// ANTES: Usaba loadCachedData() que leía widget_city
let cachedData = loadCachedData()
if let data = cachedData {
    cacheAgeMinutes = Date().timeIntervalSince(data.lastUpdate) / 60
}

// DESPUÉS: Usa loadSavedCities() que lee saved_cities
let cities = loadSavedCities()
let primaryCity = cities.first  // Primera ciudad = current location

if let primary = primaryCity, let temp = primary.fahrenheit {
    if let lastUpdate = primary.lastUpdated {
        cacheAgeMinutes = Date().timeIntervalSince(lastUpdate) / 60
    }
}
```

#### Cambios en CityStorageService.swift

```swift
// Nuevo parámetro forceReload para bypasear throttling
private func saveCities(reloadWidgets: Bool = true, forceReload: Bool = false)

// updateCurrentLocation ahora fuerza reload
func updateCurrentLocation(_ city: CityModel) {
    // ... update logic ...
    saveCities(forceReload: true)  // Crítico: ciudad cambió
}
```

#### Cambios en HomeViewModel.swift

```swift
// Detecta cuando el nombre de ciudad cambia
if let existingIndex = self.cities.firstIndex(where: { $0.isCurrentLocation }) {
    let oldCityName = self.cities[existingIndex].name
    let cityNameChanged = oldCityName != cityName

    if cityNameChanged {
        self.cityStorage.updateCurrentLocation(updatedCity)  // Force reload
    } else {
        self.cityStorage.updateCity(updatedCity)  // Throttled
    }
}
```

#### Cambios en BackgroundTaskService.swift

```swift
// Cambiado de WidgetDataService a CityStorageService
private let cityStorage = CityStorageService.shared

// fetchWeatherAndUpdateWidget ahora actualiza saved_cities
let currentLocationCity = CityModel(
    name: cityName,
    fahrenheit: temp,
    lastUpdated: Date(),
    isCurrentLocation: true,
    // ...
)
cityStorage.updateCurrentLocation(currentLocationCity)
```

### Beneficios

1. **Eliminada race condition** - Una sola fuente de verdad
2. **Actualizaciones más confiables** - Widget siempre lee datos correctos
3. **Reload forzado cuando importa** - Sin throttling cuando cambia la ciudad
4. **Código más simple** - Menos duplicación de lógica

---

## Widget Cache Freshness (Sesión 4 - Diciembre 2024)

### Problema: Widget no actualizaba temperatura por horas

**Síntomas en logs:**
- Widget mostraba 61°F por ~2 horas (19:25 - 20:26)
- Cambió a 59°F solo cuando se abrió la app
- No había logs de `[App/Background]` - Background Task nunca se ejecutó

**Causa Raíz:**
- iOS decide cuándo ejecutar background tasks basado en batería, uso, etc.
- El widget siempre asumía `cacheAgeMinutes = 0` cuando había datos
- Nunca verificaba qué tan viejos eran realmente

### Solución: Verificar edad real de los datos

#### Agregado lastUpdated a CityWidgetData

```swift
struct CityWidgetData: Identifiable, Codable {
    let id: UUID
    var name: String
    var fahrenheit: Double?
    var lastUpdated: Date?  // NUEVO
    // ...
}
```

#### Cálculo de edad real en getTimeline()

```swift
// ANTES: Siempre asumía datos frescos
if let primary = primaryCity, let temp = primary.fahrenheit {
    cacheAgeMinutes = 0  // ❌ Siempre 0
}

// DESPUÉS: Calcula edad real
if let primary = primaryCity, let temp = primary.fahrenheit {
    if let lastUpdate = primary.lastUpdated {
        cacheAgeMinutes = Date().timeIntervalSince(lastUpdate) / 60
    } else {
        cacheAgeMinutes = Double.infinity  // Sin fecha = stale
    }
}
```

#### Propagación de lastUpdated

```swift
// loadSavedCities() ahora incluye lastUpdated
let widgetCities = cityModels.prefix(3).map { model in
    CityWidgetData(
        // ...
        lastUpdated: model.lastUpdated  // NUEVO
    )
}
```

### Comportamiento esperado

Si los datos tienen **más de 30 minutos** (`maxCacheAgeMinutes`):
1. Widget detecta `needsFresh = true`
2. Hace fetch directo de WeatherKit usando coordenadas guardadas
3. Muestra temperatura actualizada

Los logs ahora muestran la edad real:
```
Primary city: Chandler, 59°F, age: 45m  // En lugar de siempre age: 0m
```

---

## Redondeo Consistente de Temperatura (Sesión 4 - Diciembre 2024)

### Problema: App y widget mostraban temperaturas diferentes

**Ejemplo:**
- Temperatura real: `57.851702°F`
- App mostraba: **58°F** (usando `Int(round(fahrenheit))`)
- Widget mostraba: **57°F** (usando `Int(fahrenheit)`) - truncamiento

### Solución: Extensión `roundedInt` reutilizable

#### Definición (en ambos targets)

```swift
// Color+Temperature.swift (App) y AlexisExtensionFarenheit.swift (Widget)
extension Double {
    /// Rounds to nearest integer using standard rounding rules
    /// Example: 57.85 → 58, 57.49 → 57
    var roundedInt: Int {
        Int(self.rounded())
    }
}
```

#### Uso en toda la UI

```swift
// ANTES (inconsistente)
Text("\(Int(round(fahrenheit)))°F")  // App - redondea
Text("\(Int(entry.fahrenheit))")     // Widget - trunca

// DESPUÉS (consistente)
Text("\(fahrenheit.roundedInt)°F")   // App
Text("\(entry.fahrenheit.roundedInt)")  // Widget
```

#### Archivos actualizados

| Archivo | Cambios |
|---------|---------|
| `Color+Temperature.swift` | + extensión `Double.roundedInt` |
| `AlexisExtensionFarenheit.swift` | + extensión + 8 usos de `roundedInt` |
| `TemperatureDisplayView.swift` | Migrado a `roundedInt` |
| `CityCardView.swift` | Migrado a `roundedInt` |
| `CityCardListView.swift` | Migrado a `roundedInt` |

### Resultado

App y widget ahora muestran exactamente la misma temperatura para el mismo valor.

---

## Commits Relacionados (Sesión 4)

- `b87e32c` - refactor: use saved_cities as single source of truth for widget data
- `c58c8b6` - fix: use lastUpdated timestamp to determine cache freshness
- (pendiente) - fix: consistent temperature rounding across app and widgets
