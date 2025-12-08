# Alexis Farenheit - Project Structure

## Overview
iOS Temperature Converter app with WidgetKit extension. Converts between Fahrenheit and Celsius, shows current weather via WeatherKit, and includes home screen widgets.

## Architecture
- **Pattern**: MVVM with Combine bindings
- **iOS Target**: 17.0+ (using iOS 26 features where available)
- **Framework**: SwiftUI + WidgetKit

## File Structure

```
Alexis Farenheit/
├── Alexis_FarenheitApp.swift          # App entry point
├── ContentView.swift                   # Main view
├── Alexis Farenheit.entitlements      # App entitlements (WeatherKit, App Groups)
├── Assets.xcassets/
│
├── Core/
│   ├── Models/                         # Data models
│   ├── Services/
│   │   ├── LocationService.swift       # CoreLocation wrapper
│   │   ├── WeatherService.swift        # WeatherKit wrapper
│   │   └── WidgetDataService.swift     # App-Widget data sharing
│   └── Theme/
│       └── Color+Temperature.swift     # Temperature-based gradients
│
├── Features/
│   └── Home/
│       ├── ViewModels/
│       │   └── HomeViewModel.swift     # Main view model
│       └── Views/
│
├── UI/
│   └── Components/
│       ├── TemperatureDisplayView.swift  # Temperature card
│       ├── ConversionSliderView.swift    # Manual F/C slider
│       └── CitySearchView.swift          # City search autocomplete
│
└── Resources/

AlexisExtensionFarenheit/               # Widget Extension
├── AlexisExtensionFarenheitBundle.swift  # Widget bundle entry
├── AlexisExtensionFarenheit.swift        # Widget + views + provider
├── AlexisExtensionFarenheit.entitlements # Widget entitlements
├── Info.plist
└── Assets.xcassets/
```

## Key Components

### Services
- **LocationService**: CLLocationManager wrapper with permission handling
- **WeatherService**: WeatherKit API for current temperature
- **WidgetDataService**: Saves data to App Group for widget access

### ViewModels
- **HomeViewModel**: Orchestrates location, weather, and UI state

### Widget
- **TemperatureProvider**: TimelineProvider for widget updates
- **SmallWidgetView**: Compact temperature display
- **MediumWidgetView**: Temperature + conversion reference
- **LargeWidgetView**: Full card with conversion table

## Required Capabilities (Xcode)

### Main App Target
1. **WeatherKit** - For weather data
2. **App Groups** - `group.alexisaraujo.alexisfarenheit`

### Widget Extension Target
1. **App Groups** - `group.alexisaraujo.alexisfarenheit` (same as app)

## Info.plist Keys
- `NSLocationWhenInUseUsageDescription`
- `NSLocationAlwaysAndWhenInUseUsageDescription`

## Data Flow
1. User opens app → LocationService requests permission
2. On location update → WeatherService fetches temperature
3. Temperature received → HomeViewModel updates → WidgetDataService caches
4. Widget reads from App Group UserDefaults
5. WidgetCenter triggers timeline reload

## Build & Run
1. Open `Alexis Farenheit.xcodeproj` in Xcode
2. Add capabilities (WeatherKit, App Groups) to both targets
3. Assign entitlements files in Build Settings
4. Run on device (WeatherKit requires physical device)
