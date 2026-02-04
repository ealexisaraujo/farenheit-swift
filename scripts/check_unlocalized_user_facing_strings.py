#!/usr/bin/env python3
"""Fail if user-facing Spanish literals are found in source files.

Checks:
- Swift user-facing APIs (Text, Label, Button, alerts, accessibility, prompts, NSLocalizedString, error messages)
- App location usage descriptions in project.pbxproj
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import List

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
    "lugares disponibles",
    "todos",
    "búsqueda",
}

USER_FACING_PATTERNS = [
    re.compile(r"\bText\(\s*\"((?:\\.|[^\"\\])*)\""),
    re.compile(r"\bLabel\(\s*\"((?:\\.|[^\"\\])*)\"\s*,\s*systemImage:"),
    re.compile(r"\bButton\(\s*\"((?:\\.|[^\"\\])*)\""),
    re.compile(r"\.navigationTitle\(\s*\"((?:\\.|[^\"\\])*)\"\s*\)"),
    re.compile(r"\.accessibilityLabel\(\s*\"((?:\\.|[^\"\\])*)\"\s*\)"),
    re.compile(r"\.accessibilityHint\(\s*\"((?:\\.|[^\"\\])*)\"\s*\)"),
    re.compile(r"\.alert\(\s*\"((?:\\.|[^\"\\])*)\""),
    re.compile(r"\bTextField\(\s*\"((?:\\.|[^\"\\])*)\""),
    re.compile(r"\bprompt\s*:\s*\"((?:\\.|[^\"\\])*)\""),
    re.compile(r"\.configurationDisplayName\(\s*\"((?:\\.|[^\"\\])*)\"\s*\)"),
    re.compile(r"\.description\(\s*\"((?:\\.|[^\"\\])*)\"\s*\)"),
    re.compile(r"NSLocalizedString\(\s*\"((?:\\.|[^\"\\])*)\""),
    re.compile(r"\berrorMessage\s*=\s*\"((?:\\.|[^\"\\])*)\""),
]

PLIST_PATTERN = re.compile(
    r"INFOPLIST_KEY_NSLocation(?:AlwaysAndWhenInUse|WhenInUse)UsageDescription\s*=\s*\"((?:\\.|[^\"\\])*)\";"
)


@dataclass
class Violation:
    file: str
    line: int
    literal: str


def looks_spanish(text: str) -> bool:
    lower = text.lower()
    if any(ch in lower for ch in "áéíóúñ¿¡"):
        return True
    return any(token in lower for token in SPANISH_KEYWORDS)


def scan_swift(file_path: Path, project_root: Path) -> List[Violation]:
    violations: List[Violation] = []
    for line_no, line in enumerate(file_path.read_text(encoding="utf-8").splitlines(), start=1):
        if line.strip().startswith("//"):
            continue
        for pattern in USER_FACING_PATTERNS:
            match = pattern.search(line)
            if not match:
                continue
            literal = match.group(1)
            if looks_spanish(literal):
                violations.append(
                    Violation(
                        file=str(file_path.relative_to(project_root)),
                        line=line_no,
                        literal=literal,
                    )
                )
    return violations


def scan_pbx(file_path: Path, project_root: Path) -> List[Violation]:
    violations: List[Violation] = []
    for line_no, line in enumerate(file_path.read_text(encoding="utf-8").splitlines(), start=1):
        match = PLIST_PATTERN.search(line)
        if not match:
            continue
        literal = match.group(1)
        if looks_spanish(literal):
            violations.append(
                Violation(
                    file=str(file_path.relative_to(project_root)),
                    line=line_no,
                    literal=literal,
                )
            )
    return violations


def main() -> int:
    project_root = Path(__file__).resolve().parents[1]

    files = list((project_root / "Alexis Farenheit").rglob("*.swift"))
    files += list((project_root / "AlexisExtensionFarenheit").rglob("*.swift"))

    violations: List[Violation] = []
    for file_path in files:
        violations.extend(scan_swift(file_path, project_root))

    pbx = project_root / "Alexis Farenheit.xcodeproj" / "project.pbxproj"
    violations.extend(scan_pbx(pbx, project_root))

    if violations:
        print("Found Spanish user-facing literals in source code:")
        for item in violations:
            print(f"- {item.file}:{item.line}: {item.literal}")
        return 1

    print("No Spanish user-facing literals detected in source code.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
