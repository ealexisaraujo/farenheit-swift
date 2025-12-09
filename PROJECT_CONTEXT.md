# 🌡️ Alexis Farenheit - Context Engineering Document

> **Última actualización**: Diciembre 2024
> **Plataforma**: iOS 17+
> **Lenguaje**: Swift 5.9+ / SwiftUI

---

## 📋 Resumen del Proyecto

**Alexis Farenheit** es una aplicación iOS de conversión de temperatura con widget para Home Screen. La app muestra el clima actual de la ubicación del usuario y permite convertir entre Fahrenheit y Celsius.

### Características Principales
- ✅ Detección automática de ubicación (CoreLocation)
- ✅ Clima en tiempo real (WeatherKit)
- ✅ Búsqueda de ciudades (MapKit)
- ✅ Widget de Home Screen (WidgetKit) - 3 tamaños
- ✅ Conversión manual F° ↔ C°
- ✅ Background refresh del widget
- ✅ Sistema de logging compartido (App + Widget)

---

## 🏗️ Arquitectura

### Patrón: MVVM + Services

```
┌─────────────────────────────────────────────────────────────┐
│                         Views                                │
│  ContentView, CitySearchView, ConversionSliderView, etc.    │
└─────────────────────┬───────────────────────────────────────┘
                      │ @StateObject / @ObservedObject
┌─────────────────────▼───────────────────────────────────────┐
│                     ViewModels                               │
│                    HomeViewModel                             │
└─────────────────────┬───────────────────────────────────────┘
                      │ Combine bindings
┌─────────────────────▼───────────────────────────────────────┐
│                      Services                                │
│  LocationService, WeatherService, WidgetDataService,        │
│  BackgroundTaskService, SharedLogger                         │
└─────────────────────────────────────────────────────────────┘
```

### Principios Aplicados
- **Value Types First**: Preferencia por `struct` sobre `class`
- **Protocol-Oriented**: Servicios con interfaces claras
- **Combine**: Reactive bindings con `@Published` y `sink`/`assign`
- **Dependency Injection**: Servicios inyectados vía Environment o init
- **Single Responsibility**: Cada servicio tiene una única responsabilidad

---

## 📁 Estructura del Proyecto

```
Alexis Farenheit/
├── Alexis_FarenheitApp.swift          # Entry point, registra background tasks
├── ContentView.swift                   # Vista principal
│
├── Core/
│   ├── Services/
│   │   ├── LocationService.swift       # CoreLocation wrapper
│   │   ├── WeatherService.swift        # WeatherKit wrapper
│   │   ├── WidgetDataService.swift     # App Group data sharing
│   │   ├── BackgroundTaskService.swift # BGTaskScheduler
│   │   └── SharedLogger.swift          # Logging compartido
│   │
│   └── Theme/
│       └── Color+Temperature.swift     # Gradientes por temperatura
│
├── Features/
│   └── Home/
│       └── ViewModels/
│           └── HomeViewModel.swift     # ViewModel principal
│
├── UI/
│   └── Components/
│       ├── CitySearchView.swift        # Búsqueda con MKLocalSearchCompleter
│       ├── ConversionSliderView.swift  # Slider de conversión
│       └── LogViewerView.swift         # Visor de logs exportables
│
└── Assets.xcassets/                    # Assets y colores

AlexisExtensionFarenheit/               # Widget Extension
├── AlexisExtensionFarenheit.swift      # Widget views y provider
├── AlexisExtensionFarenheitBundle.swift
├── WidgetLogger.swift                  # Logger para widget
├── AlexisExtensionFarenheit.entitlements
└── Info.plist
```

---

## 🔧 Servicios Implementados

### 1. LocationService
**Archivo**: `Core/Services/LocationService.swift`

**Responsabilidad**: Manejo de permisos de ubicación, obtención de coordenadas y reverse geocoding.

**Propiedades Published**:
- `lastLocation: CLLocation?`
- `currentCity: String`
- `currentCountry: String`
- `authorizationStatus: CLAuthorizationStatus`
- `errorMessage: String?`

**Decisiones de Diseño**:
- Usa `CLLocationManager` con delegate
- Solicita `requestWhenInUseAuthorization()`
- Reverse geocoding con `CLGeocoder` (warning: deprecated en iOS 26+)

### 2. WeatherService
**Archivo**: `Core/Services/WeatherService.swift`

**Responsabilidad**: Obtener temperatura actual vía WeatherKit.

**Propiedades Published**:
- `currentTemperatureF: Double?`
- `isLoading: Bool`
- `errorMessage: String?`

**Decisiones de Diseño**:
- Marked `@MainActor` para thread safety
- Convierte a Fahrenheit internamente
- Error handling específico para JWT/sandbox errors

**⚠️ Requisitos**:
- WeatherKit capability en Xcode
- WeatherKit service habilitado en Apple Developer Portal
- Entitlement: `com.apple.developer.weatherkit`

### 3. WidgetDataService
**Archivo**: `Core/Services/WidgetDataService.swift`

**Responsabilidad**: Compartir datos entre la app principal y el widget via App Groups.

**Métodos Principales**:
```swift
func saveTemperature(city: String, country: String, fahrenheit: Double)
func loadTemperature() -> (city: String, country: String, fahrenheit: Double, lastUpdate: Date)?
```

**Decisiones de Diseño**:
- Usa `UserDefaults(suiteName: "group.alexisaraujo.alexisfarenheit")`
- Llama `WidgetCenter.shared.reloadTimelines()` después de guardar
- Keys: `widget_city`, `widget_country`, `widget_fahrenheit`, `widget_last_update`

### 4. BackgroundTaskService
**Archivo**: `Core/Services/BackgroundTaskService.swift`

**Responsabilidad**: Actualizar el widget en background sin abrir la app.

**Task Identifier**: `alexisaraujo.AlexisFarenheit.refresh`

**Flujo**:
1. App registra task en `init()`
2. Cuando app va a background → schedula refresh en ~15 min
3. iOS ejecuta task → fetch weather → save to widget

**⚠️ Limitaciones iOS**:
- iOS decide cuándo ejecutar (no garantizado)
- Apps poco usadas reciben menos "presupuesto"
- Modo bajo consumo reduce actualizaciones

### 5. SharedLogger
**Archivo**: `Core/Services/SharedLogger.swift`

**Responsabilidad**: Sistema de logging que funciona tanto en la app como en el widget.

**Características**:
- Escribe a archivo JSON en App Group container
- Soporta niveles: debug, info, warning, error, widget
- Exportable a TXT o JSON
- UI dedicada en `LogViewerView`

---

## 🧩 Widget Implementation

### Timeline Provider
**Archivo**: `AlexisExtensionFarenheit/AlexisExtensionFarenheit.swift`

```swift
struct TemperatureProvider: TimelineProvider {
    func getTimeline(in context: Context, completion: @escaping (Timeline<TemperatureEntry>) -> Void) {
        // 1. Cargar datos del App Group
        let data = WidgetDataService.shared.loadTemperature()

        // 2. Crear 4 entries (1 por hora)
        var entries: [TemperatureEntry] = []
        for hourOffset in 0..<4 {
            let entryDate = Calendar.current.date(byAdding: .hour, value: hourOffset, to: currentDate)!
            entries.append(TemperatureEntry(...))
        }

        // 3. Solicitar nuevo timeline después de la última entry
        let timeline = Timeline(entries: entries, policy: .after(nextRefreshDate))
        completion(timeline)
    }
}
```

### Widget Sizes
- **Small**: Temperatura y ciudad solamente
- **Medium**: Temperatura + tabla de conversiones
- **Large**: Lista de ciudades (placeholder)

### Logging en Widget
Usa `WidgetLogger` que escribe al mismo archivo que `SharedLogger`:
```swift
WidgetLogger.widget("Timeline requested", category: "Timeline")
```

---

## ⚙️ Configuración Requerida en Xcode

### Main App Target

#### Signing & Capabilities:
1. **App Groups**: `group.alexisaraujo.alexisfarenheit`
2. **WeatherKit**: Enabled
3. **Background Modes**:
   - ✅ Background fetch
   - ✅ Background processing

#### Info Tab:
- `BGTaskSchedulerPermittedIdentifiers` (Array):
  - `alexisaraujo.AlexisFarenheit.refresh`
- `NSLocationWhenInUseUsageDescription`: "Necesitamos tu ubicación..."
- `NSLocationAlwaysUsageDescription`: (opcional, para background)

### Widget Extension Target

#### Signing & Capabilities:
1. **App Groups**: `group.alexisaraujo.alexisfarenheit` (mismo que main app)

#### Entitlements:
```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.alexisaraujo.alexisfarenheit</string>
</array>
```

### Apple Developer Portal:
1. **App ID** registrado con WeatherKit capability
2. **App Group** registrado: `group.alexisaraujo.alexisfarenheit`

---

## 🚧 Desafíos y Soluciones

### 1. WeatherKit Sandbox Error
**Error**: `com.apple.weatherkit.authservice was invalidated: Sandbox restriction`

**Causa**: WeatherKit no configurado correctamente.

**Solución**:
1. Habilitar WeatherKit capability en Xcode
2. Habilitar WeatherKit en Apple Developer Portal para el App ID
3. Agregar entitlement `com.apple.developer.weatherkit`

---

### 2. CFPrefsPlistSource Error
**Error**: `Couldn't read values in CFPrefsPlistSource... Using kCFPreferencesAnyUser with a container is only allowed for System Containers`

**Causa**: App Group no configurado correctamente o mismatch entre app y widget.

**Solución**:
1. Verificar mismo App Group ID en ambos targets
2. Verificar entitlements files en ambos targets
3. Clean build folder y reinstalar

**Nota**: Este error puede aparecer en logs pero no afecta funcionalidad si todo está configurado.

---

### 3. Widget No Aparece en Selector
**Causa**: Widget Extension no creado correctamente.

**Solución**:
1. File → New → Target → Widget Extension
2. Agregar archivos al target correcto
3. Verificar que el widget bundle está en "Embed App Extensions"

---

### 4. Location Error kCLErrorDomain 1
**Error**: `kCLErrorDomain error 1` (Permission denied)

**Solución**:
1. Agregar `NSLocationWhenInUseUsageDescription` a Info.plist
2. Verificar que el usuario aceptó permisos
3. Mostrar UI para guiar al usuario a Settings

---

### 5. City Search List No Desaparece
**Causa**: La lista de resultados no se limpiaba después de selección.

**Solución**:
- Mover búsqueda a un `.sheet()` modal
- Llamar `completer.clear()` después de selección
- Usar `@FocusState` para dismiss keyboard

---

### 6. Slider Rate-Limit Messages
**Error**: `Message send exceeds rate-limit threshold`

**Causa**: Haptic feedback llamado demasiado frecuentemente.

**Solución**:
- Solo trigger haptic al INICIO del drag, no continuamente
- Remover logging excesivo en onChange del slider

---

### 7. Widget No Se Auto-Actualiza
**Causa**: iOS tiene presupuesto limitado para widget refreshes.

**Solución Implementada**:
1. Background App Refresh con `BGTaskScheduler`
2. Timeline con múltiples entries (4 horas)
3. Policy `.after()` para solicitar nuevo timeline
4. Guardar coordenadas para background fetch

**Limitación**: iOS decide cuándo ejecutar - no hay garantía de tiempo exacto.

---

### 8. Close Button No Funcionaba en LogViewer
**Causa**: Botón tenía acción vacía.

**Solución**:
```swift
@Environment(\.dismiss) private var dismiss

Button("Cerrar") {
    dismiss()
}
```

---

### 9. Info.plist Duplicado
**Error**: `Multiple commands produce Info.plist`

**Causa**: Xcode genera Info.plist internamente; archivo manual causa conflicto.

**Solución**:
- No crear archivo `Info.plist` manual
- Configurar todo desde Xcode UI (Info tab del target)

---

## 🔄 Flujo de Datos

### App → Widget (Actualización)
```
1. WeatherService fetch completo
   ↓
2. HomeViewModel.saveWeatherToWidget()
   ↓
3. WidgetDataService.saveTemperature()
   - Guarda en UserDefaults(suiteName: App Group)
   - Llama WidgetCenter.shared.reloadTimelines()
   ↓
4. iOS notifica al Widget
   ↓
5. TemperatureProvider.getTimeline() ejecuta
   - Lee de WidgetDataService.loadTemperature()
   - Crea nuevas entries
   ↓
6. Widget UI se actualiza
```

### Background Refresh Flow
```
1. App va a background
   ↓
2. Alexis_FarenheitApp detecta scenePhase == .background
   ↓
3. BackgroundTaskService.scheduleAppRefresh()
   - Programa task para ~15 min
   ↓
4. [iOS decide cuándo ejecutar]
   ↓
5. handleAppRefresh()
   - Lee última ubicación de App Group
   - Fetch weather
   - Save to widget
   ↓
6. Widget se actualiza (si iOS lo permite)
```

---

## 📊 Dependencias

### Frameworks de Apple Usados
| Framework | Uso |
|-----------|-----|
| SwiftUI | UI declarativa |
| Combine | Reactive bindings |
| CoreLocation | GPS y geocoding |
| WeatherKit | Datos del clima |
| MapKit | Búsqueda de ciudades |
| WidgetKit | Home Screen widgets |
| BackgroundTasks | Background refresh |
| os.log | Logging del sistema |

### No se usan dependencias externas (SPM/CocoaPods)

---

## 🧪 Testing Manual

### Checklist de Funcionalidad
- [ ] App detecta ubicación al abrir
- [ ] Temperatura se muestra correctamente
- [ ] Búsqueda de ciudad funciona
- [ ] Slider convierte F° ↔ C°
- [ ] Widget muestra datos actuales
- [ ] Widget se actualiza al cambiar ciudad
- [ ] Logs capturan eventos de app y widget
- [ ] Export de logs funciona (TXT/JSON)
- [ ] Botón cerrar en LogViewer funciona

### Simular Background Fetch (Xcode)
```
Debug → Simulate Background Fetch
```

O via terminal:
```bash
xcrun simctl spawn booted launchctl kickstart -k system/com.apple.backboardd
```

---

## 📝 Notas para Desarrollo Futuro

### Mejoras Potenciales
1. **Push Notifications**: Para updates más confiables del widget
2. **Watch App**: Companion para Apple Watch
3. **Intent Configuration**: Widget configurable por el usuario
4. **Multiple Cities**: Guardar lista de ciudades favoritas
5. **Charts**: Gráfica de temperatura histórica
6. **Localization**: Soporte multi-idioma completo

### Deprecation Warnings
- `CLGeocoder` métodos deprecados en iOS 26.0+
- Migrar a `MKReverseGeocodingRequest` cuando sea necesario

### Known Issues
- El error `CFPrefsPlistSource` aparece en logs pero no afecta funcionalidad
- Widget refresh timing es controlado por iOS, no garantizado

---

## 🔐 Seguridad

- No se almacenan datos sensibles
- Ubicación solo se usa mientras la app está activa
- No hay autenticación de usuario
- Datos compartidos via App Group (sandboxed)

---

## 📚 Referencias

- [Apple WeatherKit Documentation](https://developer.apple.com/documentation/weatherkit)
- [WidgetKit Best Practices](https://developer.apple.com/documentation/widgetkit)
- [Keeping a Widget Up To Date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)
- [Background Tasks](https://developer.apple.com/documentation/backgroundtasks)
- [App Groups](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_application-groups)

---

*Documento generado como parte del desarrollo de Alexis Farenheit iOS App*

