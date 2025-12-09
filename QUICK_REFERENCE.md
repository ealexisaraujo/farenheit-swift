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
├── LocationService.swift       # GPS + Geocoding
├── WeatherService.swift        # WeatherKit
├── WidgetDataService.swift     # App Group sharing
├── BackgroundTaskService.swift # Background refresh
└── SharedLogger.swift          # Logging system
```

### Widget
```
AlexisExtensionFarenheit/
├── AlexisExtensionFarenheit.swift  # Provider + Views
└── WidgetLogger.swift              # Widget logging
```

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

---

Ver `PROJECT_CONTEXT.md` para documentación completa.

