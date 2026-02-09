# AGENTS.md

Project quick-reference for automation agents and contributors.

## Build & Run (Xcode)
- Open project: `open "Alexis Farenheit.xcodeproj"`
- WeatherKit requires a physical device (not simulator).
- Main App and Widget Extension must share the App Group capability.

## Localization Workflow
- Scan candidates without changing source:
  - `python3 scripts/localize_with_openai.py --source-lang es --target-lang en --include-targets app,widget --dry-run`
- Translate and apply (requires `OPENAI_API_KEY`):
  - `python3 scripts/localize_with_openai.py --model gpt-4.1 --source-lang es --target-lang en --include-targets app,widget --apply`
- Guardrail check (fails if new Spanish user-facing literals are added):
  - `python3 scripts/check_unlocalized_user_facing_strings.py`

Generated artifacts:
- `localization/translation_candidates.json`
- `localization/translation_results.json`

Manual QA checklist:
- `localization/QA_CHECKLIST.md`

Localization QA (xcodebuild):
- `xcodebuild test -project 'Alexis Farenheit.xcodeproj' -scheme 'Alexis Farenheit' -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'`
- `xcodebuild test -project 'Alexis Farenheit.xcodeproj' -scheme 'Alexis Farenheit' -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -testLanguage es -testRegion ES`

## New Language Automation
- One-command language onboarding:
  - `python3 scripts/i18n_workflow.py --language pt-BR`
- Dry-run (inventory only, no file mutation):
  - `python3 scripts/i18n_workflow.py --language pt-BR --dry-run`
- Documentation:
  - `localization/I18N_WORKFLOW_SCRIPT.md`

## Debugging (Xcode)
- Simulate Background Fetch: `Xcode → Debug → Simulate Background Fetch`
- Clean build: `Cmd + Shift + K`
- Verify App Group availability:
  - `print(WidgetDataService.shared.isAppGroupAvailable())`
