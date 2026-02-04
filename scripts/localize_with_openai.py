#!/usr/bin/env python3
"""One-shot localization helper using OpenAI Responses API.

Scans user-facing strings in Swift files and location permission text in project.pbxproj,
then translates deduplicated strings and optionally applies replacements.

Artifacts:
- localization/translation_candidates.json
- localization/translation_results.json
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, List, Tuple
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

OPENAI_URL = "https://api.openai.com/v1/responses"
BATCH_SIZE = 25
MAX_RETRIES = 2

SPANISH_KEYWORDS = {
    "agregar",
    "busca",
    "buscar",
    "ciudad",
    "ciudades",
    "cancelar",
    "actualizar",
    "zona horaria",
    "conversor",
    "sin resultados",
    "intenta",
    "permiso",
    "ubicación",
    "ajustes",
    "muestra",
    "desliza",
    "tiempo mundial",
    "cerrar",
    "limpiar",
    "máximo",
    "esta ciudad",
    "no se pudo",
    "obteniendo",
    "solicitando",
    "lugar",
    "lugares",
}

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

PLIST_PATTERN = re.compile(
    r"INFOPLIST_KEY_NSLocation(?:AlwaysAndWhenInUse|WhenInUse)UsageDescription\s*=\s*\"((?:\\.|[^\"\\])*)\";"
)

FORMAT_PLACEHOLDER_RE = re.compile(r"%(?:\d+\$)?[#+0\- ]*(?:\d+)?(?:\.\d+)?[a-zA-Z@]")
INTERPOLATION_RE = re.compile(r"\\\([^\)]+\)")


@dataclass
class Context:
    file: str
    line: int
    kind: str
    target: str  # app | widget


@dataclass
class Candidate:
    source: str
    contexts: List[Context]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Translate user-facing app strings with OpenAI.")
    parser.add_argument("--model", default="gpt-4.1", help="OpenAI model to use (default: gpt-4.1)")
    parser.add_argument("--source-lang", default="es", help="Source language code (default: es)")
    parser.add_argument("--target-lang", default="en", help="Target language code (default: en)")
    parser.add_argument(
        "--include-targets",
        default="app,widget",
        help="Comma-separated targets to scan: app,widget (default: app,widget)",
    )
    parser.add_argument("--dry-run", action="store_true", help="Only scan and write candidate artifact")
    parser.add_argument("--apply", action="store_true", help="Translate and apply replacements/catalog updates")
    return parser.parse_args()


def is_spanish_like(text: str) -> bool:
    lower = text.lower()
    if any(ch in lower for ch in "áéíóúñ¿¡"):
        return True
    return any(token in lower for token in SPANISH_KEYWORDS)


def should_include_for_source_lang(text: str, source_lang: str) -> bool:
    if source_lang.lower() == "es":
        return is_spanish_like(text)
    return True


def unescape_string_literal(text: str) -> str:
    return bytes(text, "utf-8").decode("unicode_escape")


def escape_string_literal(text: str) -> str:
    return text.replace("\\", "\\\\").replace("\"", '\\"')


def extract_candidates(project_root: Path, include_targets: List[str], source_lang: str) -> List[Candidate]:
    buckets: Dict[str, List[Context]] = defaultdict(list)

    def add(source: str, file_path: Path, line_no: int, kind: str, target: str) -> None:
        if not source.strip():
            return
        if not should_include_for_source_lang(source, source_lang):
            return
        rel = str(file_path.relative_to(project_root))
        buckets[source].append(Context(file=rel, line=line_no, kind=kind, target=target))

    if "app" in include_targets:
        app_root = project_root / "Alexis Farenheit"
        for swift_file in app_root.rglob("*.swift"):
            for line_no, line in enumerate(swift_file.read_text(encoding="utf-8").splitlines(), start=1):
                if line.strip().startswith("//"):
                    continue
                for kind, pattern in USER_FACING_PATTERNS:
                    match = pattern.search(line)
                    if match:
                        add(match.group(1), swift_file, line_no, kind, "app")

        pbx = project_root / "Alexis Farenheit.xcodeproj" / "project.pbxproj"
        for line_no, line in enumerate(pbx.read_text(encoding="utf-8").splitlines(), start=1):
            match = PLIST_PATTERN.search(line)
            if match:
                add(match.group(1), pbx, line_no, "InfoPlistUsageDescription", "app")

    if "widget" in include_targets:
        widget_root = project_root / "AlexisExtensionFarenheit"
        for swift_file in widget_root.rglob("*.swift"):
            for line_no, line in enumerate(swift_file.read_text(encoding="utf-8").splitlines(), start=1):
                if line.strip().startswith("//"):
                    continue
                for kind, pattern in USER_FACING_PATTERNS:
                    match = pattern.search(line)
                    if match:
                        add(match.group(1), swift_file, line_no, kind, "widget")

    return [Candidate(source=source, contexts=contexts) for source, contexts in sorted(buckets.items())]


def write_candidates_artifact(path: Path, candidates: List[Candidate], args: argparse.Namespace) -> None:
    payload = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "sourceLanguage": args.source_lang,
        "targetLanguage": args.target_lang,
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


def chunked(values: List[str], size: int) -> Iterable[List[str]]:
    for idx in range(0, len(values), size):
        yield values[idx : idx + size]


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
    system = (
        "You are a professional software localization translator. "
        "Translate each source string preserving placeholders exactly (%d, %@, %1$d), "
        "Swift interpolation tokens like \\(...), punctuation, and units like °F/°C. "
        "Do not add explanations."
    )

    user_payload = {
        "source_language": source_lang,
        "target_language": target_lang,
        "strings": sources,
        "validation_feedback": validation_feedback,
    }

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

    body = {
        "model": model,
        "temperature": 0,
        "input": [
            {
                "role": "system",
                "content": [{"type": "input_text", "text": system}],
            },
            {
                "role": "user",
                "content": [
                    {
                        "type": "input_text",
                        "text": json.dumps(user_payload, ensure_ascii=False),
                    }
                ],
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


def translate_candidates(
    candidates: List[Candidate],
    api_key: str,
    model: str,
    source_lang: str,
    target_lang: str,
) -> List[dict]:
    final_targets: Dict[str, str] = {}
    validations: Dict[str, str] = {}

    for batch in chunked([c.source for c in candidates], BATCH_SIZE):
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
                valid, reason = validate_translation(source, target)
                if valid:
                    final_targets[source] = target
                    validations[source] = "ok"
                else:
                    next_pending.append(source)
                    issues.append(f"{source} -> {reason}")

            if next_pending and attempt < MAX_RETRIES:
                feedback = (
                    "Previous attempt failed validation. Fix only these strings and keep placeholders, "
                    f"interpolations, and units exactly: {issues}"
                )
                pending = next_pending
                continue

            for source in next_pending:
                final_targets[source] = source
                validations[source] = "fallback_due_to_validation"
            break

    results: List[dict] = []
    for candidate in candidates:
        target = final_targets.get(candidate.source, candidate.source)
        validation = validations.get(candidate.source, "fallback_missing_translation")
        status = "translated" if target != candidate.source else "fallback"
        results.append(
            {
                "source": candidate.source,
                "target": target,
                "status": status,
                "validation": validation,
                "contexts": [asdict(ctx) for ctx in candidate.contexts],
            }
        )
    return results


def write_results_artifact(path: Path, args: argparse.Namespace, results: List[dict]) -> None:
    payload = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "sourceLanguage": args.source_lang,
        "targetLanguage": args.target_lang,
        "model": args.model,
        "totalResults": len(results),
        "results": results,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def apply_replacements(project_root: Path, results: List[dict]) -> int:
    edits_by_file: Dict[Path, List[dict]] = defaultdict(list)

    for row in results:
        if row["target"] == row["source"]:
            continue
        for context in row["contexts"]:
            file_path = project_root / context["file"]
            edits_by_file[file_path].append(
                {
                    "line": context["line"],
                    "source": row["source"],
                    "target": row["target"],
                }
            )

    total_applied = 0
    for file_path, edits in edits_by_file.items():
        lines = file_path.read_text(encoding="utf-8").splitlines(keepends=True)
        for edit in sorted(edits, key=lambda item: item["line"]):
            idx = edit["line"] - 1
            if idx < 0 or idx >= len(lines):
                continue

            source_literal = f'"{escape_string_literal(edit["source"])}"'
            target_literal = f'"{escape_string_literal(edit["target"])}"'

            if source_literal in lines[idx]:
                lines[idx] = lines[idx].replace(source_literal, target_literal, 1)
                total_applied += 1

        file_path.write_text("".join(lines), encoding="utf-8")

    return total_applied


def update_catalog(catalog_path: Path, source_lang: str, target_lang: str, pairs: List[Tuple[str, str]]) -> None:
    if catalog_path.exists():
        catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    else:
        catalog = {
            "sourceLanguage": target_lang,
            "strings": {},
            "version": "1.0",
        }

    catalog["sourceLanguage"] = target_lang
    catalog.setdefault("strings", {})
    catalog["version"] = "1.0"

    for target_text, source_text in pairs:
        entry = catalog["strings"].setdefault(target_text, {})
        entry["extractionState"] = "manual"
        localizations = entry.setdefault("localizations", {})
        localizations[source_lang] = {
            "stringUnit": {
                "state": "translated",
                "value": source_text,
            }
        }

    ordered = {
        "sourceLanguage": catalog["sourceLanguage"],
        "strings": dict(sorted(catalog["strings"].items(), key=lambda item: item[0].lower())),
        "version": "1.0",
    }

    catalog_path.parent.mkdir(parents=True, exist_ok=True)
    catalog_path.write_text(json.dumps(ordered, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def update_catalogs(project_root: Path, results: List[dict], source_lang: str, target_lang: str) -> None:
    app_pairs: List[Tuple[str, str]] = []
    widget_pairs: List[Tuple[str, str]] = []

    for row in results:
        target_text = row["target"]
        source_text = row["source"]
        targets = {ctx["target"] for ctx in row["contexts"]}

        if "app" in targets:
            app_pairs.append((target_text, source_text))
        if "widget" in targets:
            widget_pairs.append((target_text, source_text))

    if app_pairs:
        update_catalog(
            project_root / "Alexis Farenheit" / "Localizable.xcstrings",
            source_lang,
            target_lang,
            app_pairs,
        )
    if widget_pairs:
        update_catalog(
            project_root / "AlexisExtensionFarenheit" / "Localizable.xcstrings",
            source_lang,
            target_lang,
            widget_pairs,
        )


def main() -> int:
    args = parse_args()

    if args.dry_run and args.apply:
        print("error: choose either --dry-run or --apply", file=sys.stderr)
        return 2
    if not args.dry_run and not args.apply:
        print("error: pass --dry-run or --apply", file=sys.stderr)
        return 2

    project_root = Path(__file__).resolve().parents[1]
    include_targets = [t.strip() for t in args.include_targets.split(",") if t.strip()]
    invalid_targets = [t for t in include_targets if t not in {"app", "widget"}]
    if invalid_targets:
        print(f"error: invalid targets: {', '.join(invalid_targets)}", file=sys.stderr)
        return 2

    candidates = extract_candidates(project_root, include_targets, args.source_lang)
    candidates_path = project_root / "localization" / "translation_candidates.json"
    results_path = project_root / "localization" / "translation_results.json"

    write_candidates_artifact(candidates_path, candidates, args)
    print(f"Wrote candidates: {candidates_path} ({len(candidates)} strings)")

    if args.dry_run:
        return 0

    if not candidates:
        write_results_artifact(results_path, args, [])
        print(f"No candidates found for source language '{args.source_lang}'.")
        return 0
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        print("error: OPENAI_API_KEY is required for --apply", file=sys.stderr)
        return 2

    results = translate_candidates(
        candidates=candidates,
        api_key=api_key,
        model=args.model,
        source_lang=args.source_lang,
        target_lang=args.target_lang,
    )
    write_results_artifact(results_path, args, results)
    print(f"Wrote results: {results_path}")

    replacements = apply_replacements(project_root, results)
    update_catalogs(project_root, results, source_lang=args.source_lang, target_lang=args.target_lang)

    translated = sum(1 for row in results if row["status"] == "translated")
    fallback = len(results) - translated
    print(f"Applied {replacements} in-file replacements")
    print(f"Translated: {translated}, fallback: {fallback}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
