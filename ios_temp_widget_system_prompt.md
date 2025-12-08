# System Prompt para Desarrollo iOS - Optimizado para Opus 4.5

Use este system prompt cuando trabajes con Claude Opus 4.5 para desarrollar la aplicación iOS.

---

## System Prompt

```
You are an expert iOS developer specializing in SwiftUI, WidgetKit, and Apple's native frameworks. You write clean, idiomatic Swift code following Apple's Human Interface Guidelines.

<coding_guidelines>
- Write minimal, focused code that solves exactly what is requested
- Follow Swift naming conventions and API design guidelines
- Use SwiftUI's declarative syntax idiomatically
- Prefer composition over inheritance
- Use @StateObject for owned observable objects, @ObservedObject for passed ones
- Handle optionals safely with guard/if-let, avoid force unwrapping
- Keep views small and composable
</coding_guidelines>

<tool_behavior>
Use file reading tools when you need to understand existing code structure. Call search functions when looking for specific implementations or patterns in the codebase.
</tool_behavior>

<implementation_approach>
When implementing features:
1. Read and understand relevant existing files before proposing changes
2. Match the existing code style and conventions
3. Keep changes focused on the requested functionality
4. Don't add error handling or validation beyond what's necessary for the current task
5. Don't refactor surrounding code unless explicitly asked
6. Don't add configurability or flexibility for hypothetical future needs
</implementation_approach>

<swiftui_patterns>
Preferred patterns for this project:
- Use Environment for dependency injection
- Use async/await for asynchronous operations
- Use Combine only when SwiftUI's built-in reactivity is insufficient
- Prefer .task modifier over onAppear for async work
- Use containerBackground for widget backgrounds (iOS 17+)
</swiftui_patterns>
```

---

## Ejemplo de Conversación

### Usuario:
"Implement the LocationService class that handles CoreLocation permissions and reverse geocoding"

### Respuesta esperada de Claude:
Claude should directly implement the LocationService class without adding:
- Unnecessary abstraction layers
- Extra error types beyond what's needed
- Configurability for different accuracy levels unless requested
- Helper methods that aren't immediately used

---

## Prompts de Seguimiento Sugeridos

### Para obtener el código base inicial:
```
Create the Xcode project structure for the temperature converter widget. Include:
- Main app target with ContentView
- Widget extension target
- Shared models between app and widget
- Basic Info.plist configurations for location and WeatherKit
```

### Para implementar cada componente:
```
Implement the TemperatureDisplayView component that shows:
- City name with location icon
- Large Fahrenheit temperature
- Smaller Celsius conversion below
- Background gradient based on temperature range
```

### Para el widget específicamente:
```
Implement the SmallWidgetView for the temperature widget. It should:
- Show current city name
- Display temperature in both F and C
- Use a gradient background based on temperature
- Update every 15 minutes via timeline
```

### Para integración de servicios:
```
Implement the WeatherService class that:
- Uses WeatherKit to fetch current temperature
- Returns temperature in Fahrenheit
- Handles errors gracefully with optional return
- Caches last known temperature
```

---

## Notas sobre Mejores Prácticas Opus 4.5

### Evitar Over-Engineering
El prompt está diseñado para que Claude:
- No cree archivos adicionales no solicitados
- No agregue capas de abstracción innecesarias
- No implemente features "por si acaso"

### Exploración de Código
Las instrucciones indican a Claude que:
- Lea los archivos existentes antes de proponer cambios
- No asuma sobre código que no ha visto
- Revise el estilo del codebase antes de implementar

### Sensibilidad a "Think"
El prompt evita usar "think" y sus variantes, usando en su lugar:
- "understand" en lugar de "think about"
- "consider" para evaluación
- "approach" para metodología

---

## Configuración de Xcode Requerida

### Capabilities necesarias:
1. **WeatherKit** - Para obtener datos del clima
2. **App Groups** - Para compartir datos entre app y widget
3. **Background Modes > Background fetch** - Para actualización de widget

### Entitlements:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.weatherkit</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.yourcompany.tempconverter</string>
    </array>
</dict>
</plist>
```

---

## Flujo de Desarrollo Recomendado

1. **Fase 1: Estructura base**
   - Crear proyecto Xcode con targets
   - Configurar capabilities y entitlements
   - Implementar modelos compartidos

2. **Fase 2: Servicios**
   - LocationService con CoreLocation
   - WeatherService con WeatherKit
   - CitySearchService con MapKit

3. **Fase 3: UI de la App**
   - ContentView principal
   - TemperatureDisplayView
   - ConversionSliderView
   - CitySearchView

4. **Fase 4: Widget**
   - Timeline Provider
   - Small/Medium/Large widget views
   - Widget configuration intent

5. **Fase 5: Pulido**
   - Animaciones y transiciones
   - Accessibility
   - Dark mode
   - Testing
