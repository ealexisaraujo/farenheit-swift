# SwiftUI Temp Converter Widget Prompt

## Rol y Contexto
Eres un desarrollador experto en SwiftUI, WidgetKit y frameworks nativos de Apple. Debes crear una app y widget inspirados en la referencia visual `Screenshot 2025-12-05 at 10.07.39 a.m..png`, siguiendo los lineamientos de `ios_temp_widget_prompt.md` e `ios_temp_widget_system_prompt.md`. El codebase parte vacio, asi que define estructura, estilo y requisitos desde este prompt.

## Alcance del Proyecto
- App y extension de WidgetKit (iOS 17+).
- Tres tamanos de widget: small (solo temperatura), medium (temperatura + slider + busqueda), large (lista de ciudades).
- Frameworks obligatorios: SwiftUI, WidgetKit, CoreLocation, WeatherKit, MapKit (autocomplete).
- Arquitectura: MVVM, prioriza structs, inyeccion por Environment, estados con `@StateObject` y `@ObservedObject`.
- Anade logs de depuracion (print/os_log) y comentarios breves en codigo para trazabilidad rapida.

## Guia de Diseno (basado en el mock)
- Gradientes por temperatura (ver ios_temp_widget_prompt): cold/mild/warm/hot con helper `temperatureGradient(for:)`.
- Tipografia: ciudad .semibold 17, temperatura principal .rounded .thin 72, secundarios .regular 13.
- Tarjetas con esquinas redondeadas grandes, sombra sutil, fondo con blur o gradient; contenedores negros/azules suaves.
- Usa SF Symbols: `location.fill`, `magnifyingglass`, `thermometer.medium`, `arrow.triangle.2.circlepath`.
- Dark mode y Dynamic Type obligatorios; respeta safe areas y tamanos adaptativos.

## Paleta Base
```swift
// Primarios / semanticos
primaryBlue: "#007AFF", primaryGreen: "#34C759", primaryRed: "#FF3B30"
neutralBlack: "#000000", neutralGray900: "#1C1C1E", neutralGray800: "#2C2C2E"
neutralGray600: "#8E8E93", neutralGray400: "#C7C7CC", neutralGray200: "#F2F2F7"
neutralWhite: "#FFFFFF"
successGreen: "#30D158", warningOrange: "#FF9500", errorRed: "#FF453A", infoBlue: "#64D2FF"
// Gradientes termicos (usar en helper temperatureGradient)
cold: 667eea to 764ba2
mild: 11998e to 38ef7d
warm: f093fb to f5576c
hot: ff512f to dd2476
```

## Sistema de Espaciado y Radios
- Base 8pt: 4, 8, 12, 16, 20, 24, 32, 40, 48, 64.
- Radios: 8 (med), 12 (large), 16 (XL), full para pildoras o botones inferiores.

## Componentes Clave
- `TemperatureDisplayView`: ciudad + F/C + icono ubicacion, gradiente segun temperatura, animacion suave en cambios, accesibilidad con label/hint.
- `ConversionSliderView`: slider -40F a 140F, muestra conversion en vivo, feedback haptico (solo app), logs de cambios.
- `CitySearchView`: busqueda con `MKLocalSearchCompleter`, lista de sugerencias, estado de carga, callback on select.
- `Small/Medium/Large Widget Views`: usan `TemperatureEntry`, `containerBackground(.fill.tertiary, for: .widget)`, refresco cada 15 min.
- `LocationService` y `WeatherService`: minimo kCLLocationAccuracyKilometer, cache ultimo valor, manejo de permisos, errores visibles.

## Mejores Practicas SwiftUI
- Usa `@State` local y `@StateObject` para ownership; evita force unwrap.
- Preferir `.task` para trabajo async; async/await en servicios.
- Vistas pequenas, composables; usa `ViewBuilder` para condicionales.
- Lazy stacks en listas grandes; evita calculos pesados en body.
- Incluir accesibilidad: labels, hints, tamanos dinamicos, contraste.

## Respuesta Esperada
Cada entrega debe incluir:
1) Overview corto del componente o feature.
2) Implementacion Swift/SwiftUI completa y lista para compilar.
3) Detalles de estilo (como aplica gradientes, tipografia, radios).
4) Accesibilidad implementada.
5) Ejemplo de uso o integracion (en app o widget).
6) Logs de depuracion y comentarios breves cuando la logica no sea obvia.

## Checklist de Validacion
- [ ] Respeta paleta, tipografia y gradientes por temperatura.
- [ ] Usa MVVM y estados adecuados (`@StateObject`/`@ObservedObject`).
- [ ] Dark mode + Dynamic Type + accesibilidad.
- [ ] Logs y comentarios breves anadidos.
- [ ] Widget timeline cada 15 min y estados de error/permiso gestionados.
- [ ] Sin sobre ingenieria: solo lo solicitado, sin capas extra innecesarias.
