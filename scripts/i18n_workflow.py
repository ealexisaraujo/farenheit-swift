#!/usr/bin/env python3
"""Automate end-to-end app localization onboarding for a new language.

This script performs the full workflow:
1) Add language to Xcode project regions (knownRegions in project.pbxproj)
2) Generate source inventory artifact
3) Translate strings with OpenAI
4) Apply translations to String Catalogs
5) Create localized InfoPlist.strings for location permission prompts
6) Validate via guardrail + optional xcodebuild tests

Artifacts are written to: localization/<language>/
"""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import re
import subprocess
import sys
from collections import defaultdict
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

OPENAI_URL = "https://api.openai.com/v1/responses"
BATCH_SIZE = 30
MAX_RETRIES = 2

USER_FACING_PATTERNS = [
    ("Text", re.compile(r"\bText\(\s*\"((?:\\.|[^\"\\])*)\"")),
    ("Label", re.compile(r"\bLabel\(\s*\"((?:\\.|[^\"\\])*)\"\s*,\s*systemImage:")),
    ("Button", re.compile(r"\bButton\(\s*\"((?:\\.|[^\"\\])*)\"")),
    ("navigationTitle", re.compile(r"\.navigationTitle\(\s*\"((?:\\.|[^\"\\])*)\"\s*\)")),
    ("accessibilityLabel", re.compile(r"\.accessibilityLabel\(\s*\"((?:\\.|[^\"\\])*)\"\s*\)")),
    ("accessibilityHint", re.compile(r"\.accessibilityHint\(\s*\"((?:\\.|[^\"\\])*)\"\s*\)")),
    ("alert", re.compile(r"\.alert\(\s*\"((?:\\.|[^\"\\])*)\"")),
    ("TextField", re.compile(r"\bTextField\(\s*\"((?:\\.|[^\"\\])*)\"")),
    ("searchPrompt", re.compile(r"\bprompt\s*:\s*\"((?:\\.|[^\"\\])*)\"")),
    ("widgetConfigName", re.compile(r"\.configurationDisplayName\(\s*\"((?:\\.|[^\"\\])*)\"\s*\)")),
    ("widgetConfigDescription", re.compile(r"\.description\(\s*\"((?:\\.|[^\"\\])*)\"\s*\)")),
    ("NSLocalizedString", re.compile(r"NSLocalizedString\(\s*\"((?:\\.|[^\"\\])*)\"")),
    ("errorMessageAssign", re.compile(r"\berrorMessage\s*=\s*\"((?:\\.|[^\"\\])*)\"")),
]

PLIST_KEY_PATTERN = re.compile(
    r"INFOPLIST_KEY_(NSLocationAlwaysAndWhenInUseUsageDescription|NSLocationWhenInUseUsageDescription)\s*=\s*\"((?:\\.|[^\"\\])*)\";"
)

FORMAT_PLACEHOLDER_RE = re.compile(r"%(?:\d+\$)?[#+0\- ]*(?:\d+)?(?:\.\d+)?[a-zA-Z@]")
INTERPOLATION_RE = re.compile(r"\\\([^\)]+\)")

SKIP_LITERALS = {
    "doc.text.magnifyingglass",
    "magnifyingglass",
    "arrow.triangle.2.circlepath",
    "plus.circle.fill",
    "arrow.left.arrow.right",
    "doc.text",
    "doc.badge.gearshape",
    "trash",
    "location.fill",
    "clock.fill",
    "arrow.counterclockwise",
    "globe.americas.fill",
    "mappin.slash",
    "mappin.circle.fill",
    "xmark.circle.fill",
    "line.3.horizontal",
    "lock.fill",
    "thermometer.medium",
    "equal",
    "chevron.right",
    "xmark",
    "clock",
    "gear",
    "ellipsis.circle",
    "arrow.clockwise",
}


@dataclass(frozen=True)
class Context:
    file: str
    line: int
    kind: str
    target: str  # app | widget


@dataclass
class Candidate:
    source: str
    contexts: List[Context]


@dataclass
class TranslationRow:
    source: str
    target: str
    status: str
    validation: str
    contexts: List[Context]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Automate language onboarding for this iOS project.")
    parser.add_argument("--language", required=True, help="Target language code, e.g. pt-BR, fr, de")
    parser.add_argument("--source-language", default="en", help="Source/base language code (default: en)")
    parser.add_argument("--model", default="gpt-4.1", help="OpenAI model (default: gpt-4.1)")
    parser.add_argument(
        "--include-targets",
        default="app,widget",
        help="Comma-separated targets to include: app,widget (default: app,widget)",
    )
    parser.add_argument("--dry-run", action="store_true", help="Only produce source inventory artifact")
    parser.add_argument("--skip-tests", action="store_true", help="Skip xcodebuild validation")
    parser.add_argument(
        "--destination",
        default="platform=iOS Simulator,name=iPhone 17,OS=26.2",
        help="xcodebuild test destination",
    )
    parser.add_argument("--project", default="Alexis Farenheit.xcodeproj", help="Xcode project path")
    parser.add_argument("--scheme", default="Alexis Farenheit", help="Xcode scheme for validation tests")
    parser.add_argument("--test-region", default=None, help="Override test region (default: derived from language)")
    return parser.parse_args()


def normalize_language_code(code: str) -> str:
    return code.replace("_", "-")


def derived_region(language: str) -> str:
    if "-" in language:
        return language.split("-", 1)[1].upper()
    return language.upper()


def escape_string_literal(text: str) -> str:
    return text.replace("\\", "\\\\").replace('"', '\\"')


def looks_translatable(text: str) -> bool:
    if not text.strip():
        return False
    if text in SKIP_LITERALS:
        return False
    # Skip format-only keys such as "%lld" or "%@: %@ / %@"; these are often
    # auto-extracted internals and can break string-symbol generation.
    if text.strip().startswith("%"):
        return False
    if text.startswith("\\("):
        return False
    if not re.search(r"[A-Za-z]", text):
        return False
    return True


def chunked(values: Sequence[str], size: int) -> Iterable[List[str]]:
    for idx in range(0, len(values), size):
        yield list(values[idx : idx + size])


def output_text_from_response(response_json: dict) -> str:
    if isinstance(response_json.get("output_text"), str) and response_json["output_text"].strip():
        return response_json["output_text"]

    chunks: List[str] = []
    for item in response_json.get("output", []):
        if item.get("type") != "message":
            continue
        for content in item.get("content", []):
            if content.get("type") in {"output_text", "text"}:
                text = content.get("text", "")
                if text:
                    chunks.append(text)
    return "\n".join(chunks)


def call_openai_batch(
    api_key: str,
    model: str,
    source_lang: str,
    target_lang: str,
    sources: List[str],
    validation_feedback: str | None,
) -> Dict[str, str]:
    schema = {
        "type": "object",
        "properties": {
            "translations": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "source": {"type": "string"},
                        "target": {"type": "string"},
                    },
                    "required": ["source", "target"],
                    "additionalProperties": False,
                },
            }
        },
        "required": ["translations"],
        "additionalProperties": False,
    }

    system_prompt = (
        "You are a professional software localization translator. "
        "Translate user-facing strings from source language to target language. "
        "Preserve placeholders exactly (%d, %@, %1$d), Swift interpolation tokens like \\(...), "
        "units (°F/°C), and punctuation. Return only valid JSON matching schema."
    )

    user_payload = {
        "source_language": source_lang,
        "target_language": target_lang,
        "strings": sources,
        "validation_feedback": validation_feedback,
    }

    body = {
        "model": model,
        "temperature": 0,
        "input": [
            {
                "role": "system",
                "content": [{"type": "input_text", "text": system_prompt}],
            },
            {
                "role": "user",
                "content": [{"type": "input_text", "text": json.dumps(user_payload, ensure_ascii=False)}],
            },
        ],
        "text": {
            "format": {
                "type": "json_schema",
                "name": "translations",
                "strict": True,
                "schema": schema,
            }
        },
    }

    request = Request(
        OPENAI_URL,
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urlopen(request, timeout=120) as resp:
            response_json = json.loads(resp.read().decode("utf-8"))
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"OpenAI API HTTP {exc.code}: {detail}") from exc
    except URLError as exc:
        raise RuntimeError(f"OpenAI API connection error: {exc}") from exc

    text = output_text_from_response(response_json).strip()
    if not text:
        raise RuntimeError("OpenAI API returned an empty response body")

    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Failed to parse OpenAI JSON output: {text[:500]}") from exc

    out: Dict[str, str] = {}
    for row in parsed.get("translations", []):
        source = row.get("source")
        target = row.get("target")
        if isinstance(source, str) and isinstance(target, str):
            out[source] = target
    return out


def extract_token_set(text: str) -> Tuple[Tuple[str, ...], Tuple[str, ...], Tuple[str, ...]]:
    placeholders = tuple(FORMAT_PLACEHOLDER_RE.findall(text))
    interpolations = tuple(INTERPOLATION_RE.findall(text))
    units = tuple(unit for unit in ("°F", "°C") if unit in text)
    return placeholders, interpolations, units


def validate_translation(source: str, target: str) -> Tuple[bool, str]:
    src_placeholders, src_interpolations, src_units = extract_token_set(source)
    dst_placeholders, dst_interpolations, dst_units = extract_token_set(target)

    if src_placeholders != dst_placeholders:
        return False, f"placeholder mismatch: expected {src_placeholders}, got {dst_placeholders}"
    if src_interpolations != dst_interpolations:
        return False, f"interpolation mismatch: expected {src_interpolations}, got {dst_interpolations}"
    if src_units != dst_units:
        return False, f"unit mismatch: expected {src_units}, got {dst_units}"
    if not target.strip():
        return False, "empty translation"
    return True, "ok"


def collect_catalog_keys(project_root: Path, target: str) -> List[Tuple[str, Context]]:
    if target == "app":
        catalog_path = project_root / "Alexis Farenheit" / "Localizable.xcstrings"
    else:
        catalog_path = project_root / "AlexisExtensionFarenheit" / "Localizable.xcstrings"

    if not catalog_path.exists():
        return []

    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    keys = list(catalog.get("strings", {}).keys())
    out: List[Tuple[str, Context]] = []
    for key in keys:
        if looks_translatable(key):
            out.append(
                (
                    key,
                    Context(file=str(catalog_path.relative_to(project_root)), line=0, kind="xcstrings_key", target=target),
                )
            )
    return out


def collect_code_keys(project_root: Path, target: str) -> List[Tuple[str, Context]]:
    if target == "app":
        root = project_root / "Alexis Farenheit"
    else:
        root = project_root / "AlexisExtensionFarenheit"

    out: List[Tuple[str, Context]] = []
    for swift_file in root.rglob("*.swift"):
        for line_no, line in enumerate(swift_file.read_text(encoding="utf-8").splitlines(), start=1):
            if line.strip().startswith("//"):
                continue
            for kind, pattern in USER_FACING_PATTERNS:
                match = pattern.search(line)
                if not match:
                    continue
                literal = match.group(1)
                if not looks_translatable(literal):
                    continue
                out.append(
                    (
                        literal,
                        Context(
                            file=str(swift_file.relative_to(project_root)),
                            line=line_no,
                            kind=kind,
                            target=target,
                        ),
                    )
                )
    return out


def collect_plist_keys(project_root: Path) -> Tuple[List[Tuple[str, Context]], Dict[str, str]]:
    pbx = project_root / "Alexis Farenheit.xcodeproj" / "project.pbxproj"
    lines = pbx.read_text(encoding="utf-8").splitlines()

    by_key: Dict[str, str] = {}
    out: List[Tuple[str, Context]] = []
    for line_no, line in enumerate(lines, start=1):
        match = PLIST_KEY_PATTERN.search(line)
        if not match:
            continue
        key_name = match.group(1)
        value = match.group(2)
        if key_name not in by_key:
            by_key[key_name] = value
        if looks_translatable(value):
            out.append(
                (
                    value,
                    Context(file=str(pbx.relative_to(project_root)), line=line_no, kind="InfoPlistUsageDescription", target="app"),
                )
            )

    required = {
        "NSLocationAlwaysAndWhenInUseUsageDescription",
        "NSLocationWhenInUseUsageDescription",
    }
    if set(by_key.keys()) != required:
        missing = required - set(by_key.keys())
        raise RuntimeError(f"Missing required InfoPlist usage description keys in project.pbxproj: {sorted(missing)}")

    return out, by_key


def build_candidates(project_root: Path, include_targets: Sequence[str]) -> Tuple[List[Candidate], Dict[str, str]]:
    grouped: Dict[str, List[Context]] = defaultdict(list)

    for target in include_targets:
        for source, ctx in collect_catalog_keys(project_root, target):
            grouped[source].append(ctx)
        for source, ctx in collect_code_keys(project_root, target):
            grouped[source].append(ctx)

    plist_candidates, plist_by_key = collect_plist_keys(project_root)
    for source, ctx in plist_candidates:
        grouped[source].append(ctx)

    result: List[Candidate] = []
    for source, contexts in sorted(grouped.items(), key=lambda item: item[0].lower()):
        unique_contexts = sorted(set(contexts), key=lambda c: (c.file, c.line, c.kind, c.target))
        result.append(Candidate(source=source, contexts=list(unique_contexts)))

    return result, plist_by_key


def write_candidates_artifact(path: Path, candidates: Sequence[Candidate], args: argparse.Namespace) -> None:
    payload = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "sourceLanguage": args.source_language,
        "targetLanguage": args.language,
        "includeTargets": sorted(set(args.include_targets.split(","))),
        "totalCandidates": len(candidates),
        "candidates": [
            {
                "source": c.source,
                "contexts": [asdict(ctx) for ctx in c.contexts],
            }
            for c in candidates
        ],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def translate_candidates(
    candidates: Sequence[Candidate], api_key: str, model: str, source_lang: str, target_lang: str
) -> List[TranslationRow]:
    final_targets: Dict[str, str] = {}
    validations: Dict[str, str] = {}

    ordered_sources = [c.source for c in candidates]
    for batch in chunked(ordered_sources, BATCH_SIZE):
        pending = list(batch)
        feedback = None

        for attempt in range(MAX_RETRIES + 1):
            if not pending:
                break

            translated = call_openai_batch(
                api_key=api_key,
                model=model,
                source_lang=source_lang,
                target_lang=target_lang,
                sources=pending,
                validation_feedback=feedback,
            )

            next_pending: List[str] = []
            issues: List[str] = []

            for source in pending:
                target = translated.get(source, source)
                ok, reason = validate_translation(source, target)
                if ok:
                    final_targets[source] = target
                    validations[source] = "ok"
                else:
                    next_pending.append(source)
                    issues.append(f"{source} -> {reason}")

            if next_pending and attempt < MAX_RETRIES:
                feedback = (
                    "Previous attempt failed validation. Fix only these entries and preserve placeholders/interpolations/units exactly: "
                    + "; ".join(issues)
                )
                pending = next_pending
                continue

            for source in next_pending:
                final_targets[source] = source
                validations[source] = "fallback_due_to_validation"
            break

    rows: List[TranslationRow] = []
    for candidate in candidates:
        target = final_targets.get(candidate.source, candidate.source)
        validation = validations.get(candidate.source, "fallback_missing_translation")
        status = "translated" if target != candidate.source else "fallback"
        rows.append(
            TranslationRow(
                source=candidate.source,
                target=target,
                status=status,
                validation=validation,
                contexts=candidate.contexts,
            )
        )
    return rows


def write_results_artifact(path: Path, args: argparse.Namespace, rows: Sequence[TranslationRow]) -> None:
    payload = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "sourceLanguage": args.source_language,
        "targetLanguage": args.language,
        "model": args.model,
        "totalResults": len(rows),
        "results": [
            {
                "source": row.source,
                "target": row.target,
                "status": row.status,
                "validation": row.validation,
                "contexts": [asdict(ctx) for ctx in row.contexts],
            }
            for row in rows
        ],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def ensure_known_region(project_root: Path, language: str) -> bool:
    pbx = project_root / "Alexis Farenheit.xcodeproj" / "project.pbxproj"
    lines = pbx.read_text(encoding="utf-8").splitlines()

    start_idx = None
    end_idx = None
    for idx, line in enumerate(lines):
        if "knownRegions = (" in line:
            start_idx = idx
            break
    if start_idx is None:
        raise RuntimeError("Could not locate knownRegions block in project.pbxproj")

    for idx in range(start_idx + 1, len(lines)):
        if lines[idx].strip() == ");":
            end_idx = idx
            break
    if end_idx is None:
        raise RuntimeError("Malformed knownRegions block in project.pbxproj")

    def normalize_region(token: str) -> str:
        return token.strip().strip(",").strip('"').strip()

    def format_region(region: str) -> str:
        if re.fullmatch(r"[A-Za-z0-9_]+", region):
            return region
        return f'"{region}"'

    original_tokens = [lines[idx].strip().strip(",") for idx in range(start_idx + 1, end_idx)]
    normalized = [normalize_region(token) for token in original_tokens if normalize_region(token)]

    unique_regions: List[str] = []
    seen = set()
    for region in normalized:
        if region in seen:
            continue
        seen.add(region)
        unique_regions.append(region)

    if language not in seen:
        if "Base" in unique_regions:
            base_idx = unique_regions.index("Base")
            unique_regions.insert(base_idx, language)
        else:
            unique_regions.append(language)

    # Keep Base last when present.
    if "Base" in unique_regions:
        unique_regions = [region for region in unique_regions if region != "Base"] + ["Base"]

    new_block = ["\t\t\t\t" + format_region(region) + "," for region in unique_regions]
    old_block = lines[start_idx + 1 : end_idx]
    changed = old_block != new_block
    if changed:
        lines[start_idx + 1 : end_idx] = new_block
        pbx.write_text("\n".join(lines) + "\n", encoding="utf-8")

    return changed


def get_known_regions(project_root: Path) -> List[str]:
    pbx = project_root / "Alexis Farenheit.xcodeproj" / "project.pbxproj"
    lines = pbx.read_text(encoding="utf-8").splitlines()

    start_idx = None
    end_idx = None
    for idx, line in enumerate(lines):
        if "knownRegions = (" in line:
            start_idx = idx
            break
    if start_idx is None:
        raise RuntimeError("Could not locate knownRegions block in project.pbxproj")

    for idx in range(start_idx + 1, len(lines)):
        if lines[idx].strip() == ");":
            end_idx = idx
            break
    if end_idx is None:
        raise RuntimeError("Malformed knownRegions block in project.pbxproj")

    def normalize_region(token: str) -> str:
        return token.strip().strip(",").strip('"').strip()

    raw_tokens = [lines[idx].strip().strip(",") for idx in range(start_idx + 1, end_idx)]
    normalized = [normalize_region(token) for token in raw_tokens if normalize_region(token)]

    unique_regions: List[str] = []
    seen = set()
    for region in normalized:
        if region in seen:
            continue
        seen.add(region)
        unique_regions.append(region)
    return unique_regions


def sync_info_plist_localizations(project_root: Path, regions: Sequence[str]) -> int:
    localizations = [region for region in regions if region != "Base"]
    plist_paths = [
        project_root / "Alexis-Farenheit-Info.plist",
        project_root / "AlexisExtensionFarenheit" / "Info.plist",
    ]

    changed = 0
    for plist_path in plist_paths:
        with plist_path.open("rb") as fp:
            payload = plistlib.load(fp)

        current = payload.get("CFBundleLocalizations")
        if current == localizations:
            continue

        payload["CFBundleLocalizations"] = list(localizations)
        with plist_path.open("wb") as fp:
            plistlib.dump(payload, fp, sort_keys=False)
        changed += 1

    return changed


def update_catalog(catalog_path: Path, language: str, translations: Dict[str, str]) -> int:
    if catalog_path.exists():
        catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    else:
        catalog = {"sourceLanguage": "en", "strings": {}, "version": "1.0"}

    catalog.setdefault("strings", {})
    catalog["sourceLanguage"] = "en"
    catalog["version"] = "1.0"

    changed = 0
    for source_key, localized_value in translations.items():
        entry = catalog["strings"].setdefault(source_key, {})
        if "extractionState" not in entry:
            entry["extractionState"] = "manual"
        localizations = entry.setdefault("localizations", {})
        previous = (
            localizations.get(language, {}).get("stringUnit", {}).get("value") if language in localizations else None
        )
        if previous != localized_value:
            changed += 1
        localizations[language] = {
            "stringUnit": {
                "state": "translated",
                "value": localized_value,
            }
        }

    ordered = {
        "sourceLanguage": "en",
        "strings": dict(sorted(catalog["strings"].items(), key=lambda item: item[0].lower())),
        "version": "1.0",
    }
    catalog_path.parent.mkdir(parents=True, exist_ok=True)
    catalog_path.write_text(json.dumps(ordered, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return changed


def sanitize_catalog_for_symbols(catalog_path: Path, language: str) -> int:
    """Remove risky localization metadata for auto-generated % keys.

    Some auto-extracted String Catalog keys that start with `%` can fail
    Swift symbol generation if marked as manual or manually localized.
    """
    if not catalog_path.exists():
        return 0

    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    strings = catalog.get("strings", {})
    changed = 0

    for key, entry in strings.items():
        if not key.startswith("%"):
            continue
        if not entry.get("isCommentAutoGenerated"):
            continue

        if entry.get("extractionState") == "manual":
            entry.pop("extractionState", None)
            changed += 1

        localizations = entry.get("localizations")
        if isinstance(localizations, dict) and language in localizations:
            localizations.pop(language, None)
            changed += 1

    if changed:
        ordered = {
            "sourceLanguage": catalog.get("sourceLanguage", "en"),
            "strings": dict(sorted(strings.items(), key=lambda item: item[0].lower())),
            "version": catalog.get("version", "1.0"),
        }
        catalog_path.write_text(json.dumps(ordered, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    return changed


def write_info_plist_strings(project_root: Path, language: str, translated_by_source: Dict[str, str], plist_by_key: Dict[str, str]) -> Path:
    out_dir = project_root / "Alexis Farenheit" / f"{language}.lproj"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_file = out_dir / "InfoPlist.strings"

    lines: List[str] = []
    for key in [
        "NSLocationAlwaysAndWhenInUseUsageDescription",
        "NSLocationWhenInUseUsageDescription",
    ]:
        source_value = plist_by_key[key]
        target_value = translated_by_source.get(source_value, source_value)
        lines.append(f'"{key}" = "{escape_string_literal(target_value)}";')

    out_file.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return out_file


def run_command(cmd: List[str], cwd: Path) -> None:
    process = subprocess.run(cmd, cwd=str(cwd), check=False)
    if process.returncode != 0:
        raise RuntimeError(f"Command failed ({process.returncode}): {' '.join(cmd)}")


def apply_translations(project_root: Path, language: str, rows: Sequence[TranslationRow], plist_by_key: Dict[str, str]) -> Dict[str, int]:
    app_map: Dict[str, str] = {}
    widget_map: Dict[str, str] = {}
    translated_by_source: Dict[str, str] = {}

    for row in rows:
        translated_by_source[row.source] = row.target
        targets = {ctx.target for ctx in row.contexts}
        if "app" in targets:
            app_map[row.source] = row.target
        if "widget" in targets:
            widget_map[row.source] = row.target

    app_changed = update_catalog(project_root / "Alexis Farenheit" / "Localizable.xcstrings", language, app_map)
    widget_changed = update_catalog(project_root / "AlexisExtensionFarenheit" / "Localizable.xcstrings", language, widget_map)
    app_sanitized = sanitize_catalog_for_symbols(project_root / "Alexis Farenheit" / "Localizable.xcstrings", language)
    widget_sanitized = sanitize_catalog_for_symbols(project_root / "AlexisExtensionFarenheit" / "Localizable.xcstrings", language)
    write_info_plist_strings(project_root, language, translated_by_source, plist_by_key)

    return {
        "appCatalogEntriesUpdated": app_changed,
        "widgetCatalogEntriesUpdated": widget_changed,
        "appSanitizedKeys": app_sanitized,
        "widgetSanitizedKeys": widget_sanitized,
    }


def validate(project_root: Path, args: argparse.Namespace) -> None:
    # Guardrail check
    run_command(["python3", "scripts/check_unlocalized_user_facing_strings.py"], project_root)

    if args.skip_tests:
        return

    base_cmd = [
        "xcodebuild",
        "test",
        "-project",
        args.project,
        "-scheme",
        args.scheme,
        "-destination",
        args.destination,
    ]
    run_command(base_cmd, project_root)

    region = args.test_region or derived_region(args.language)
    localized_cmd = base_cmd + ["-testLanguage", args.language, "-testRegion", region]
    run_command(localized_cmd, project_root)


def main() -> int:
    args = parse_args()
    language = normalize_language_code(args.language)

    include_targets = [token.strip() for token in args.include_targets.split(",") if token.strip()]
    invalid_targets = [token for token in include_targets if token not in {"app", "widget"}]
    if invalid_targets:
        print(f"error: invalid targets in --include-targets: {invalid_targets}", file=sys.stderr)
        return 2

    project_root = Path(__file__).resolve().parents[1]
    artifact_dir = project_root / "localization" / language
    artifact_dir.mkdir(parents=True, exist_ok=True)

    try:
        candidates, plist_by_key = build_candidates(project_root, include_targets)
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    candidates_path = artifact_dir / "translation_candidates.json"
    write_candidates_artifact(candidates_path, candidates, argparse.Namespace(**{**vars(args), "language": language}))
    print(f"Wrote candidates artifact: {candidates_path} ({len(candidates)} strings)")

    if args.dry_run:
        print("Dry-run complete. No project files were modified.")
        return 0

    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        print("error: OPENAI_API_KEY is required (except in --dry-run mode)", file=sys.stderr)
        return 2

    rows = translate_candidates(
        candidates=candidates,
        api_key=api_key,
        model=args.model,
        source_lang=args.source_language,
        target_lang=language,
    )
    results_path = artifact_dir / "translation_results.json"
    write_results_artifact(results_path, argparse.Namespace(**{**vars(args), "language": language}), rows)
    print(f"Wrote results artifact: {results_path}")

    region_added = ensure_known_region(project_root, language)
    known_regions = get_known_regions(project_root)
    plist_localizations_synced = sync_info_plist_localizations(project_root, known_regions)
    counters = apply_translations(project_root, language, rows, plist_by_key)

    translated = sum(1 for row in rows if row.status == "translated")
    fallback = len(rows) - translated

    print(f"Added language to knownRegions: {'yes' if region_added else 'already present'}")
    print(f"Info.plist localization list synced: {'yes' if plist_localizations_synced else 'already up to date'}")
    print(f"App catalog entries updated: {counters['appCatalogEntriesUpdated']}")
    print(f"Widget catalog entries updated: {counters['widgetCatalogEntriesUpdated']}")
    print(f"App catalog sanitized keys: {counters['appSanitizedKeys']}")
    print(f"Widget catalog sanitized keys: {counters['widgetSanitizedKeys']}")
    print(f"Translation summary: translated={translated}, fallback={fallback}")

    try:
        validate(project_root, argparse.Namespace(**{**vars(args), "language": language}))
        print("Validation complete.")
    except RuntimeError as exc:
        print(f"error: validation failed: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
