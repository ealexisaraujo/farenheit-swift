# Lottie iOS Setup Instructions

The new onboarding system requires the `lottie-ios` Swift Package Manager dependency.

## Adding Lottie to Your Xcode Project

1. **Open Xcode** and load the `Alexis Farenheit.xcodeproj`

2. **Add Swift Package Dependency:**
   - Select `File > Add Package Dependencies...`
   - Enter the package URL: `https://github.com/airbnb/lottie-ios`
   - Click `Add Package`
   - Select version rule: `Up to Next Major Version` from `4.0.0`
   - Click `Add Package`
   - Select the `Lottie` library and add it to the `Alexis Farenheit` target
   - Click `Add Package`

3. **Verify the dependency** appears in the Project Navigator under "Package Dependencies"

4. **Build the project** (`Cmd + B`) to ensure everything compiles correctly

## Animation Files

The following Lottie JSON animation files have been created in `Alexis Farenheit/Resources/Animations/`:

### Onboarding Animations
- `onboarding-thermometer.json` - Welcome screen hero animation
- `onboarding-location.json` - Location permission screen with globe and pin
- `onboarding-widget.json` - Widget showcase with phone animation
- `onboarding-success.json` - Completion celebration with checkmark and confetti

### Walkthrough Animations
- `walkthrough-tap.json` - Tap gesture hint animation
- `walkthrough-swipe.json` - Swipe gesture hint animation
- `walkthrough-expand.json` - Expand/unfold animation for tools panel

## Replacing Placeholder Animations

The current animation files are functional placeholders with basic geometric shapes. To upgrade to professional animations:

1. Visit [LottieFiles.com](https://lottiefiles.com) and search for:
   - "weather thermometer" or "temperature" for the welcome screen
   - "location pin" or "gps animation" for the location screen
   - "mobile notification" or "phone widget" for the widget screen
   - "success confetti" or "checkmark celebration" for the completion screen
   - "tap gesture" or "click finger" for tap hints
   - "swipe gesture" or "slide finger" for swipe hints
   - "expand animation" or "unfold" for expand animations

2. Download the Lottie JSON files

3. Replace the placeholder files in `Alexis Farenheit/Resources/Animations/`

4. Keep the same filenames to avoid code changes

## New Files Created

### Onboarding System
| File | Purpose | Lines |
|------|---------|-------|
| `LottieView.swift` | SwiftUI wrapper for Lottie animations | ~100 |
| `OnboardingConfiguration.swift` | Centralized config and page definitions | ~180 |
| `OnboardingPageView.swift` | Reusable page component | ~130 |
| `OnboardingView.swift` | Main 4-page onboarding flow | ~280 |

### Walkthrough System
| File | Purpose | Lines |
|------|---------|-------|
| `WalkthroughTypes.swift` | Target enum, preference key, coordinate space | ~50 |
| `WalkthroughCoordinator.swift` | Step state management | ~100 |
| `WalkthroughTooltipView.swift` | Lottie-powered floating tooltips | ~230 |

### Deleted Files (1,016 lines removed)
- `HomeOnboardingIntroView.swift` (647 lines) - Replaced by `OnboardingView.swift`
- `HomeWalkthroughOverlay.swift` (369 lines) - Replaced by `WalkthroughTooltipView.swift`

## Net Code Change

- **Removed**: ~1,016 lines (complex particle/orb animations, spotlight overlay)
- **Added**: ~1,070 lines (Lottie-based system)
- **Net**: Similar line count but much simpler, more maintainable code

## Localization

New localization strings have been added to `Localizable.xcstrings` for:
- All 4 onboarding page titles and subtitles
- Button labels for permission and completion
- All 4 walkthrough step titles and messages
- Navigation button labels (Next, Back, Skip, Done)

Supported languages: English (en), Portuguese (pt-BR), Spanish (es)
