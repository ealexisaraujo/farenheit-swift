# Alexis Farenheit

## Localization Workflow

- Scan candidates without changing source:
  - `python3 scripts/localize_with_openai.py --source-lang es --target-lang en --include-targets app,widget --dry-run`
- Translate and apply (requires `OPENAI_API_KEY` in environment):
  - `python3 scripts/localize_with_openai.py --model gpt-4.1 --source-lang es --target-lang en --include-targets app,widget --apply`
- Guardrail check (fails if new Spanish user-facing literals are added to source):
  - `python3 scripts/check_unlocalized_user_facing_strings.py`

Generated artifacts:
- `localization/translation_candidates.json`
- `localization/translation_results.json`

Manual QA checklist:
- `localization/QA_CHECKLIST.md`
