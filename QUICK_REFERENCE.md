# Alexis Farenheit - Quick Reference

## IDs y Configuración

| Item | Value |
|------|-------|
| **App Group ID** | `group.alexisaraujo.alexisfarenheit` |
| **Background Task ID** | `alexisaraujo.AlexisFarenheit.refresh` |
| **Widget Kind** | `AlexisExtensionFarenheit` |
| **Bundle ID (App)** | `alexisaraujo.Alexis-Farenheit` |

---

## Key Files

### Services

```
Core/Services/
├── LocationService.swift       # GPS + Geocoding + Significant Location Changes
├── WeatherService.swift        # WeatherKit
├── WidgetDataService.swift     # App Group sharing
├── BackgroundTaskService.swift # Background refresh + Significant Location
├── CityStorageService.swift    # Multi-city persistence
├── TimeZoneService.swift       # Time slider logic
├── SharedLogger.swift          # File-based logging (JSON)
└── PerformanceMonitor.swift    # Performance tracking
```

### Widget

```
AlexisExtensionFarenheit/
├── AlexisExtensionFarenheit.swift  # Provider + Views (Home + Lock Screen)
└── WidgetLogger.swift              # Widget logging
```

### Widget Families Soportadas
| Tipo | Familia | Descripción |
|------|---------|-------------|
| Home Screen | `systemSmall` | Temperatura compacta |
| Home Screen | `systemMedium` | Temp + conversiones |
| Home Screen | `systemLarge` | Tabla completa |
| Lock Screen | `accessoryCircular` | Gauge con °F/°C |
| Lock Screen | `accessoryRectangular` | Layout horizontal |
| Lock Screen | `accessoryInline` | Texto en línea |

---

## Common Code Patterns

### Save to Widget
```swift
WidgetDataService.shared.saveTemperature(
    city: "Chandler",
    country: "US",
    fahrenheit: 72.0
)
```

### Logging (App)
```swift
SharedLogger.shared.info("Message", category: "Category")
SharedLogger.shared.debug("Debug info", category: "Debug")
SharedLogger.shared.error("Error!", category: "Error")
```

### Logging (Widget)
```swift
WidgetLogger.widget("Timeline requested", category: "Timeline")
WidgetLogger.info("Data loaded", category: "Data")
```

---

## Xcode Capabilities Required

### Main App Target ✓

- App Groups: `group.alexisaraujo.alexisfarenheit`
- WeatherKit
- Background Modes: fetch, processing

### Widget Extension Target ✓

- App Groups: `group.alexisaraujo.alexisfarenheit`

### Info Tab (Main App)

- `BGTaskSchedulerPermittedIdentifiers`: Array con `alexisaraujo.AlexisFarenheit.refresh`
- `NSLocationWhenInUseUsageDescription`
- `NSLocationAlwaysAndWhenInUseUsageDescription`

---

## Debug Commands

### Simulate Background Fetch
```
Xcode → Debug → Simulate Background Fetch
```

### Clean Build
```
Cmd + Shift + K
```

### Check App Group Working
```swift
print(WidgetDataService.shared.isAppGroupAvailable())
```

---

## Known Warnings (Safe to Ignore)

1. `CFPrefsPlistSource` error → No afecta funcionalidad
2. `CLGeocoder` deprecated → Funciona hasta iOS 25
3. Widget timing → iOS controla cuándo actualiza

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Widget no aparece | Verificar Widget Extension target |
| WeatherKit error | Habilitar en Developer Portal |
| Location denied | Revisar permisos en Settings |
| Widget datos viejos | Force save desde la app |
| Lock Screen widget no aparece | Settings → Wallpaper → Customize Lock Screen |
| Widget no actualiza en background | Verificar permiso "Always Allow" location |
| Significant location no funciona | Requiere dispositivo real (~500m+ movimiento) |

---

## Background Location (Significant Changes)

### Cómo funciona

- Usa torres celulares (no GPS) → eficiente en batería
- Detecta movimiento ~500m+ → iOS despierta app
- App fetch weather → actualiza widget
- No requiere Background Mode "Location updates"

### Métodos clave

```swift
// LocationService
locationService.startMonitoringSignificantLocationChanges()
locationService.stopMonitoringSignificantLocationChanges()
locationService.onSignificantLocationChange = { location in ... }

// BackgroundTaskService
BackgroundTaskService.shared.setupBackgroundLocationMonitoring()
BackgroundTaskService.shared.startSignificantLocationMonitoring()
BackgroundTaskService.shared.stopSignificantLocationMonitoring()
```

### App lifecycle

```swift
// Alexis_FarenheitApp.swift
.onChange(of: scenePhase) {
    case .background:
        BackgroundTaskService.shared.startSignificantLocationMonitoring()
    case .active:
        BackgroundTaskService.shared.stopSignificantLocationMonitoring()
}
```

---

Ver `PROJECT_CONTEXT.md` para documentación completa.

