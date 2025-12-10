# Alexis Farenheit - Project Structure

## Overview
iOS Temperature Converter app with WidgetKit extension. Converts between Fahrenheit and Celsius, shows current weather via WeatherKit, and includes Home Screen and Lock Screen widgets. Features multi-city support with timezone display and automatic widget updates when user moves between cities.

## Architecture
- **Pattern**: MVVM with Combine bindings
- **iOS Target**: 17.0+ (using iOS 26 features where available)
- **Framework**: SwiftUI + WidgetKit

## File Structure

```
Alexis Farenheit/
├── Alexis_FarenheitApp.swift          # App entry point, background task registration
├── ContentView.swift                   # Main view
├── Alexis Farenheit.entitlements      # App entitlements (WeatherKit, App Groups)
├── Assets.xcassets/
│
├── Core/
│   ├── Models/
│   │   └── CityModel.swift             # City data model with timezone
│   ├── Services/
│   │   ├── LocationService.swift       # CoreLocation + Significant Location Changes
│   │   ├── WeatherService.swift        # WeatherKit wrapper
│   │   ├── WidgetDataService.swift     # App-Widget data sharing
│   │   ├── BackgroundTaskService.swift # BGTaskScheduler + Significant Location
│   │   ├── CityStorageService.swift    # City persistence + Widget reload
│   │   ├── TimeZoneService.swift       # Time slider logic
│   │   ├── SharedLogger.swift          # File-based logging (JSON)
│   │   └── PerformanceMonitor.swift    # Performance tracking
│   └── Theme/
│       └── Color+Temperature.swift     # Temperature-based gradients
│
├── Features/
│   └── Home/
│       └── ViewModels/
│           └── HomeViewModel.swift     # Main view model (multi-city)
│
├── UI/
│   └── Components/
│       ├── CityCardView.swift          # Individual city card
│       ├── CityCardListView.swift      # Drag-and-drop city list
│       ├── TimeZoneSliderView.swift    # Time of day slider
│       ├── ConversionSliderView.swift  # Manual F/C slider
│       ├── CitySearchView.swift        # City search autocomplete
│       └── LogViewerView.swift         # Debug log viewer
│
└── Resources/

AlexisExtensionFarenheit/               # Widget Extension
├── AlexisExtensionFarenheitBundle.swift  # Widget bundle entry
├── AlexisExtensionFarenheit.swift        # Widget + views + provider (6 sizes)
├── WidgetLogger.swift                    # Widget-specific logging
├── AlexisExtensionFarenheit.entitlements # Widget entitlements
├── Info.plist
└── Assets.xcassets/
```

## Key Components

### Services
- **LocationService**: CLLocationManager + Significant Location Changes for background updates
- **WeatherService**: WeatherKit API for current temperature
- **WidgetDataService**: Saves data to App Group for widget access
- **BackgroundTaskService**: BGTaskScheduler + handles significant location changes
- **CityStorageService**: Multi-city persistence with widget reload throttling
- **TimeZoneService**: Time slider with 0-1439 minute range
- **SharedLogger**: JSON file logging shared between app and widget
- **PerformanceMonitor**: NSLog/OSLog performance tracking

### ViewModels
- **HomeViewModel**: Orchestrates location, weather, multi-city, and UI state

### Widget (Home Screen)
- **TemperatureProvider**: TimelineProvider for widget updates
- **SmallWidgetView**: Compact temperature display
- **MediumWidgetView**: Primary city + second city or conversion table
- **LargeWidgetView**: Up to 3 cities with day/night indicators

### Widget (Lock Screen - iOS 16+)
- **AccessoryCircularView**: Gauge with °F center, °C in corner
- **AccessoryRectangularView**: Horizontal layout with temperature hero
- **AccessoryInlineView**: Single line text for date area

## Required Capabilities (Xcode)

### Main App Target
1. **WeatherKit** - For weather data
2. **App Groups** - `group.alexisaraujo.alexisfarenheit`
3. **Background Modes** - Background fetch, Background processing

### Widget Extension Target
1. **App Groups** - `group.alexisaraujo.alexisfarenheit` (same as app)

## Info.plist Keys
- `NSLocationWhenInUseUsageDescription`
- `NSLocationAlwaysAndWhenInUseUsageDescription`
- `BGTaskSchedulerPermittedIdentifiers` - Array with `alexisaraujo.AlexisFarenheit.refresh`

## Data Flow

### Foreground Update
1. User opens app → LocationService requests permission
2. On location update → WeatherService fetches temperature
3. Temperature received → HomeViewModel updates → WidgetDataService caches
4. Widget reads from App Group UserDefaults
5. WidgetCenter triggers timeline reload

### Background Location Update (Significant Location Changes)
1. User moves ~500m+ → iOS detects significant location change
2. iOS wakes app in background → LocationService receives location
3. BackgroundTaskService.handleSignificantLocationChange() triggers
4. Reverse geocode + WeatherKit fetch → Save to App Group
5. Widget reloads with new city and temperature

## Build & Run
1. Open `Alexis Farenheit.xcodeproj` in Xcode
2. Add capabilities (WeatherKit, App Groups, Background Modes) to main app
3. Add capability (App Groups) to widget extension
4. Assign entitlements files in Build Settings
5. Run on device (WeatherKit requires physical device)
