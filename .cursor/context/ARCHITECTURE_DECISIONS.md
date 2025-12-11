# Architecture Decisions Record (ADR)

> Last Updated: December 11, 2025

This document records significant architectural decisions made during the development of Alexis Farenheit.

---

## ADR-001: Repository Pattern for Widget Data

### Status
**Accepted** ✅

### Context
The original implementation had multiple sources of truth for widget data:
- `widget_*` keys in UserDefaults (used by fresh WeatherKit fetches)
- `saved_cities` array in UserDefaults (used by widgets to display data)

This caused a **race condition** where widgets showed inconsistent temperatures.

### Decision
Implement the **Repository Pattern** with `saved_cities` as the **single source of truth**.

### Consequences
- ✅ Eliminates race conditions
- ✅ Consistent data across all widgets
- ⚠️ Requires duplicate code in widget extension (see ADR-002)

---

## ADR-002: Duplicate WidgetRepository in Widget Extension

### Status
**Accepted with caveat** ⚠️

### Context
iOS Widget Extensions run in a **separate process**. They cannot import code from the main app without a Shared Framework.

### Decision
Duplicate WidgetRepository with a lightweight version (~260 lines vs ~520 lines):

| Main App Version | Widget Extension Version |
|------------------|--------------------------|
| Protocol definition | ❌ Not needed |
| Legacy migration | ❌ Handled by main app |
| Throttled reloads | ❌ Not needed |
| Diagnostic utils | ❌ Not needed |
| Read/Write ops | ✅ Same |

### Synchronization Rules
Both files MUST maintain identical:
- `Keys.cities` = `"saved_cities"`
- `Keys.location` = `"widget_location"`
- Data structures (`WidgetCityData`, `SharedLocation`)
- App Group ID

---

## ADR-003: No `public` in App Extensions

### Decision
Remove all `public` modifiers from widget extension code. App Extensions don't export APIs.

---

## ADR-004: Explicit Memberwise Initializers

### Decision
Always provide explicit `public init(...)` for public structs because Swift's synthesized init is `internal`.

---

## ADR-005: UserDefaults Synchronization

### Decision
Call `defaults.synchronize()` before reads and after writes for reliable cross-process data sharing.

---

## Key Files

| File | Location | Purpose |
|------|----------|---------|
| `WidgetRepository.swift` | Main App | Full featured repository |
| `WidgetRepository.swift` | Widget Extension | Lightweight repository |
| `WidgetLogger.swift` | Widget Extension | Widget logging |