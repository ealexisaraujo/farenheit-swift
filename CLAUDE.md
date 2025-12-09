# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Alexis Farenheit is an iOS temperature conversion app with Home Screen and Lock Screen widgets. It displays current weather for the user's location and converts between Fahrenheit and Celsius.

**Platform**: iOS 17+ | **Language**: Swift 5.9+ / SwiftUI

## Build & Run

```bash
# Open in Xcode
open "Alexis Farenheit.xcodeproj"
```

- WeatherKit requires a **physical device** (not simulator)
- Both Main App and Widget Extension need matching App Groups capability

## Architecture

**Pattern**: MVVM + Services with Combine bindings

```
Views (SwiftUI)
    ↓ @StateObject / @ObservedObject
ViewModels (HomeViewModel)
    ↓ Combine bindings
Services (LocationService, WeatherService, WidgetDataService, BackgroundTaskService, SharedLogger)
```

### Key Files

| File | Purpose |
|------|---------|
| `Alexis_FarenheitApp.swift` | Entry point, registers background tasks |
| `ContentView.swift` | Main view |
| `Core/Services/LocationService.swift` | CoreLocation wrapper, permissions, geocoding |
| `Core/Services/WeatherService.swift` | WeatherKit wrapper (`@MainActor`) |
| `Core/Services/WidgetDataService.swift` | App Group data sharing with widget |
| `Core/Services/BackgroundTaskService.swift` | BGTaskScheduler for widget refresh |
| `Core/Services/SharedLogger.swift` | File-based logging (JSON in App Group) |
| `Features/Home/ViewModels/HomeViewModel.swift` | Main view model |
| `AlexisExtensionFarenheit/AlexisExtensionFarenheit.swift` | Widget provider and views (Home Screen + Lock Screen) |
| `AlexisExtensionFarenheit/WidgetLogger.swift` | Widget-specific logging |

## Configuration IDs

| Item | Value |
|------|-------|
| App Group | `group.alexisaraujo.alexisfarenheit` |
| Background Task ID | `alexisaraujo.AlexisFarenheit.refresh` |
| Widget Kind | `AlexisExtensionFarenheit` |
| Bundle ID | `alexisaraujo.Alexis-Farenheit` |

## Required Xcode Capabilities

### Main App Target
- **App Groups**: `group.alexisaraujo.alexisfarenheit`
- **WeatherKit**: Enabled (requires Apple Developer Portal setup)
- **Background Modes**: Background fetch, Background processing
- **Info Tab**: `BGTaskSchedulerPermittedIdentifiers` array with `alexisaraujo.AlexisFarenheit.refresh`

### Widget Extension Target
- **App Groups**: `group.alexisaraujo.alexisfarenheit`

## Data Flow

### App → Widget Update
1. `WeatherService` fetches temperature
2. `HomeViewModel.saveWeatherToWidget()` calls `WidgetDataService.saveTemperature()`
3. `WidgetDataService` saves to `UserDefaults(suiteName: App Group)` and calls `WidgetCenter.shared.reloadTimelines()`
4. `TemperatureProvider.getTimeline()` reads from App Group and creates timeline entries

### Background Refresh
1. App goes to background → `BackgroundTaskService.scheduleAppRefresh()` schedules task for ~15 min
2. iOS executes task → fetches weather with stored coordinates → saves to widget
3. Timeline policy `.after()` requests new timeline

## Code Patterns

### Saving to Widget
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
SharedLogger.shared.error("Error!", category: "Error")
```

### Logging (Widget)
```swift
WidgetLogger.widget("Timeline requested", category: "Timeline")
```

## Frameworks Used

- SwiftUI, Combine (UI/state)
- CoreLocation (GPS, geocoding)
- WeatherKit (weather data)
- MapKit (city search via MKLocalSearchCompleter)
- WidgetKit (Home Screen widgets: small/medium/large | Lock Screen widgets: circular/rectangular/inline)
- BackgroundTasks (BGTaskScheduler)

No external dependencies (SPM/CocoaPods).

## Known Issues

- `CFPrefsPlistSource` error in logs: Safe to ignore if App Groups configured correctly
- `CLGeocoder` deprecated warnings for iOS 26+: Still functional
- Widget refresh timing is controlled by iOS, not guaranteed to be immediate

## Debugging

```
# Simulate Background Fetch
Xcode → Debug → Simulate Background Fetch

# Clean Build
Cmd + Shift + K

# Verify App Group
print(WidgetDataService.shared.isAppGroupAvailable())
```

## Swift Style

- Prefer `struct` over `class` (value types first)
- Use `@Published` with Combine for reactive state
- `async/await` for concurrency
- camelCase for variables/functions, PascalCase for types
- Boolean prefixes: `is`, `has`, `should`
