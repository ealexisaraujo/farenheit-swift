# Localization QA Checklist

## Build and unit tests
- `xcodebuild test -project 'Alexis Farenheit.xcodeproj' -scheme 'Alexis Farenheit' -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'`
- `xcodebuild test -project 'Alexis Farenheit.xcodeproj' -scheme 'Alexis Farenheit' -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -testLanguage es -testRegion ES`

## Manual app checks in Xcode
1. Edit scheme -> Run -> Options -> Application Language = `English` and verify all app/widget UI is English.
2. Edit scheme -> Run -> Options -> Application Language = `Spanish` and verify all app/widget UI is Spanish.
3. Edit scheme -> Run -> Arguments Passed On Launch: add `-NSShowNonLocalizedStrings YES` and verify no missing localization markers.
4. Edit scheme -> Run -> Application Language = `Right to Left Pseudolanguage` and verify layout resilience.
5. Edit scheme -> Run -> Application Language = `Double-Length Pseudolanguage` and verify clipping/overlap.

## Widget checks
- Add small, medium, large, and lock screen widget families.
- Verify localized title/description in widget gallery and localized text inside each widget family.
- Verify timeline hints and conversion labels in Spanish and English.

## Permission checks
- Validate location permission prompts in English and Spanish.
- Confirm `NSLocationWhenInUseUsageDescription` and `NSLocationAlwaysAndWhenInUseUsageDescription` text matches localization.
