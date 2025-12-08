# iOS Temperature Converter Widget - Development Prompt

## Project Overview

Build a minimal iOS Widget Extension that converts Fahrenheit to Celsius temperatures. The widget integrates with iOS built-in WeatherKit API and CoreLocation for automatic city detection and weather data.

---

## Technical Requirements

### Target Platform
- iOS 17.0+
- WidgetKit for Home Screen widgets
- SwiftUI for all UI components
- Xcode 15+

### Required Frameworks
```swift
import WidgetKit
import SwiftUI
import CoreLocation
import WeatherKit
```

### Widget Sizes to Support
- Small (systemSmall): Temperature display only
- Medium (systemMedium): Temperature + slider + city search
- Large (systemLarge): Full experience with city list

---

## Core Features

### 1. Automatic Location Detection
Use CoreLocation to detect the user's current city:

```swift
// CLLocationManager configuration
// Request whenInUse authorization
// Reverse geocode to get city name
// Handle location permission states gracefully
```

**Implementation notes:**
- Request location permission on first launch
- Cache last known location for widget refresh
- Display "Location unavailable" gracefully if permission denied
- Use `CLGeocoder` for reverse geocoding city names

### 2. Temperature Conversion Slider
Interactive slider for manual Fahrenheit input:

```swift
// Slider range: -40°F to 140°F
// Real-time Celsius conversion display
// Haptic feedback on value changes (in app, not widget)
```

**Conversion formula:**
```swift
func fahrenheitToCelsius(_ f: Double) -> Double {
    return (f - 32) * 5 / 9
}
```

### 3. City Search with WeatherKit
Integrate with iOS Weather built-in capabilities:

```swift
// Use WeatherService for temperature data
// MKLocalSearchCompleter for city autocomplete
// Display current temperature for searched cities
```

---

## File Structure

```
TempConverter/
├── TempConverterApp.swift           // Main app entry point
├── ContentView.swift                // Main app view with full controls
├── Models/
│   └── TemperatureData.swift        // Temperature model and conversion logic
├── Services/
│   ├── LocationService.swift        // CoreLocation wrapper
│   └── WeatherService.swift         // WeatherKit integration
├── Views/
│   ├── TemperatureDisplayView.swift // Large temperature display component
│   ├── ConversionSliderView.swift   // Interactive slider component
│   └── CitySearchView.swift         // City search with autocomplete
├── TempConverterWidget/
│   ├── TempConverterWidget.swift    // Widget configuration
│   ├── TempConverterWidgetBundle.swift
│   ├── Provider.swift               // Timeline provider
│   └── WidgetViews/
│       ├── SmallWidgetView.swift
│       ├── MediumWidgetView.swift
│       └── LargeWidgetView.swift
└── Resources/
    └── Assets.xcassets
```

---

## SwiftUI Implementation Details

### Main App View Structure

```swift
struct ContentView: View {
    @StateObject private var locationService = LocationService()
    @StateObject private var weatherService = WeatherService()
    @State private var manualFahrenheit: Double = 72
    @State private var searchText: String = ""
    @State private var isSearching: Bool = false
    
    var body: some View {
        // Implementation here
    }
}
```

### Temperature Display Component

```swift
struct TemperatureDisplayView: View {
    let fahrenheit: Double
    let cityName: String
    let countryCode: String
    
    private var celsius: Double {
        (fahrenheit - 32) * 5 / 9
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // City name with SF Symbol location icon
            // Large temperature display showing both units
            // Subtle animation on value change
        }
    }
}
```

### Conversion Slider Component

```swift
struct ConversionSliderView: View {
    @Binding var fahrenheit: Double
    
    var body: some View {
        VStack {
            // Custom styled slider
            // Min/max labels
            // Current value indicator
            // Haptic feedback integration
        }
    }
}
```

### City Search Component

```swift
struct CitySearchView: View {
    @Binding var searchText: String
    @StateObject private var searchCompleter = CitySearchCompleter()
    let onCitySelected: (String) -> Void
    
    var body: some View {
        // Search field with SF Symbol
        // Results list with city suggestions
        // Loading state indicator
    }
}
```

---

## Widget Implementation

### Timeline Provider

```swift
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> TemperatureEntry {
        TemperatureEntry(
            date: Date(),
            fahrenheit: 72,
            celsius: 22.2,
            cityName: "My Location",
            countryCode: "US"
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (TemperatureEntry) -> Void) {
        // Return current temperature data
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<TemperatureEntry>) -> Void) {
        // Refresh every 15 minutes
        // Fetch location and weather data
    }
}
```

### Widget Entry

```swift
struct TemperatureEntry: TimelineEntry {
    let date: Date
    let fahrenheit: Double
    let celsius: Double
    let cityName: String
    let countryCode: String
}
```

### Small Widget View

```swift
struct SmallWidgetView: View {
    let entry: TemperatureEntry
    
    var body: some View {
        ZStack {
            // Gradient background based on temperature
            // City name
            // Temperature in both units (F prominent, C secondary)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}
```

---

## Design Specifications

### Color Palette (Temperature-based gradients)

```swift
extension Color {
    // Cold temperatures (< 32°F)
    static let coldGradientStart = Color(hex: "667eea")
    static let coldGradientEnd = Color(hex: "764ba2")
    
    // Mild temperatures (32-70°F)
    static let mildGradientStart = Color(hex: "11998e")
    static let mildGradientEnd = Color(hex: "38ef7d")
    
    // Warm temperatures (70-85°F)
    static let warmGradientStart = Color(hex: "f093fb")
    static let warmGradientEnd = Color(hex: "f5576c")
    
    // Hot temperatures (> 85°F)
    static let hotGradientStart = Color(hex: "ff512f")
    static let hotGradientEnd = Color(hex: "dd2476")
}

func temperatureGradient(for fahrenheit: Double) -> LinearGradient {
    // Return appropriate gradient based on temperature range
}
```

### Typography

```swift
// Temperature display
.font(.system(size: 72, weight: .thin, design: .rounded))

// City name
.font(.system(size: 17, weight: .semibold, design: .default))

// Secondary info
.font(.system(size: 13, weight: .regular, design: .default))
```

### SF Symbols to Use
- `location.fill` - Current location indicator
- `magnifyingglass` - Search field
- `thermometer.medium` - Temperature icon
- `arrow.triangle.2.circlepath` - Refresh/sync indicator

---

## Location Service Implementation

```swift
class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    @Published var currentCity: String = "Unknown"
    @Published var currentCountry: String = ""
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var lastLocation: CLLocation?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }
    
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func requestLocation() {
        locationManager.requestLocation()
    }
    
    // Delegate methods implementation
}
```

---

## Weather Service Implementation

```swift
class WeatherService: ObservableObject {
    private let weatherService = WeatherService.shared
    
    @Published var currentTemperature: Double?
    @Published var isLoading: Bool = false
    @Published var error: Error?
    
    func fetchWeather(for location: CLLocation) async {
        isLoading = true
        do {
            let weather = try await weatherService.weather(for: location)
            await MainActor.run {
                self.currentTemperature = weather.currentWeather.temperature.converted(to: .fahrenheit).value
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
        }
    }
}
```

---

## App Intents for Widget Interactivity (iOS 17+)

```swift
struct SelectCityIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select City"
    static var description = IntentDescription("Choose a city for temperature display")
    
    @Parameter(title: "City")
    var city: String?
}
```

---

## Info.plist Required Entries

```xml
<!-- Location Permission -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to show local temperature</string>

<!-- WeatherKit Capability -->
<key>com.apple.developer.weatherkit</key>
<true/>
```

---

## Testing Checklist

- [ ] Widget displays correctly in all three sizes
- [ ] Location permission request works properly
- [ ] Temperature conversion is accurate
- [ ] City search returns relevant results
- [ ] Widget refreshes on timeline schedule
- [ ] Graceful handling when location permission denied
- [ ] Graceful handling when WeatherKit unavailable
- [ ] Dark mode support
- [ ] Dynamic Type support
- [ ] VoiceOver accessibility

---

## Performance Considerations

- Cache weather data to minimize API calls
- Use `TimelineReloadPolicy.after(Date)` for efficient widget updates
- Implement background app refresh for up-to-date widget data
- Minimize location accuracy for battery efficiency (use `kCLLocationAccuracyKilometer`)

---

## Error Handling

Handle these scenarios gracefully:
1. Location permission denied → Show manual city search
2. WeatherKit unavailable → Show manual slider mode only
3. Network unavailable → Show cached data with "Last updated" timestamp
4. Search returns no results → Show helpful empty state

---

## Accessibility

```swift
// Add accessibility labels
.accessibilityLabel("Temperature: \(fahrenheit) degrees Fahrenheit, \(celsius) degrees Celsius")
.accessibilityHint("Current temperature in \(cityName)")

// Support Dynamic Type
.dynamicTypeSize(...DynamicTypeSize.accessibility3)
```

---

## Localization Considerations

- Temperature formatting should respect user's locale
- City names should use localized versions when available
- Support RTL languages in layout

---

## Build & Deploy Notes

1. Enable WeatherKit capability in Xcode project settings
2. Register App ID with WeatherKit entitlement in Apple Developer Portal
3. Add Widget Extension target to the project
4. Configure App Groups for data sharing between app and widget
5. Test on physical device (WeatherKit requires real device)
