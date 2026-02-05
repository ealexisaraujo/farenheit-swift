# i18n Workflow Script (`scripts/i18n_workflow.py`)

This script automates the full localization onboarding flow for a new language:

1. Add language to Xcode project regions (`knownRegions` in `project.pbxproj`)
2. Sync `CFBundleLocalizations` in app + extension `Info.plist`
3. Add localized location permission prompts (`<lang>.lproj/InfoPlist.strings`)
4. Generate source inventory artifact (candidate strings)
5. Generate translations with OpenAI and apply them to app/widget `Localizable.xcstrings`
6. Validate with guardrails and optional `xcodebuild` test runs

## Prerequisites

- Python 3.10+
- `OPENAI_API_KEY` in environment (required unless `--dry-run`)
- Xcode CLI tools installed (`xcodebuild`) for validation

## Quick Start

### 1) Dry-run (inventory only, no file mutation)

```bash
python3 scripts/i18n_workflow.py --language pt-BR --dry-run
```

This writes:
- `localization/pt-BR/translation_candidates.json`

### 2) Full run (translate + apply + validate)

```bash
export OPENAI_API_KEY="<your_key>"
python3 scripts/i18n_workflow.py --language pt-BR
```

This writes:
- `localization/pt-BR/translation_candidates.json`
- `localization/pt-BR/translation_results.json`

And updates:
- `Alexis Farenheit.xcodeproj/project.pbxproj` (adds language to `knownRegions`)
- `Alexis-Farenheit-Info.plist` (`CFBundleLocalizations`)
- `AlexisExtensionFarenheit/Info.plist` (`CFBundleLocalizations`)
- `Alexis Farenheit/Localizable.xcstrings`
- `AlexisExtensionFarenheit/Localizable.xcstrings`
- `Alexis Farenheit/pt-BR.lproj/InfoPlist.strings`

## Common Options

- `--language <code>`: target locale (required), e.g. `pt-BR`, `fr`, `de`
- `--model <model>`: OpenAI model (default: `gpt-4.1`)
- `--include-targets app,widget`: limit target scopes
- `--skip-tests`: skip `xcodebuild` validation steps
- `--destination "platform=iOS Simulator,name=iPhone 17,OS=26.2"`: custom simulator
- `--project "Alexis Farenheit.xcodeproj"`
- `--scheme "Alexis Farenheit"`
- `--test-region BR`: override derived test region

## Validation Behavior

By default (without `--skip-tests`), script runs:

1. `python3 scripts/check_unlocalized_user_facing_strings.py`
2. `xcodebuild test` (default language)
3. `xcodebuild test -testLanguage <lang> -testRegion <region>`

## Reliability Controls

- Placeholder/interpolation guard checks:
  - `%d`, `%@`, `%1$d`
  - Swift interpolation tokens (`\(...)`)
  - Units (`°F`, `°C`)
- Automatic retry when translation validation fails
- Fallback to source text when retries cannot produce a valid translation
- Artifact files capture full candidate and translation output for auditing

## Recommended PR Flow

1. Run `--dry-run` and inspect candidate artifact
2. Run full translation apply
3. Review diffs in both `Localizable.xcstrings` files
4. Run app manually in target language and check widget copy
5. Commit with artifacts under `localization/<lang>/`
