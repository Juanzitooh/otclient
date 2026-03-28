#!/usr/bin/env python3
"""Exporta os arquivos listados na wiki em um zip na raiz do repo.

Uso:
  python3 tools/export_wiki_bundle.py
  python3 tools/export_wiki_bundle.py --output /caminho/arquivo.zip
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED


EXCLUDED_PREFIXES = ("docs/roadmap/",)


def parse_paths(wiki_text: str) -> list[str]:
    # Captura caminhos em inline code: `path/to/file`
    return re.findall(r"`([^`]+)`", wiki_text)


def resolve_wiki_path(repo_root: Path) -> Path | None:
    candidates = (
        repo_root / "wiki.md",
        repo_root / "docs" / "wiki.md",
    )
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return None


def is_excluded(rel_path: Path) -> bool:
    rel = rel_path.as_posix()
    return any(rel.startswith(prefix) for prefix in EXCLUDED_PREFIXES)


def should_report_missing(rel_path: Path) -> bool:
    rel = rel_path.as_posix()
    # Evita ruido de tokens textuais como `status.md` que nao sao caminho real do bundle.
    return "/" in rel


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        "-o",
        default=None,
        help="Caminho do zip de saida (padrao: repo_root/codex_export_<repo>.zip)",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    wiki_path = resolve_wiki_path(repo_root)

    if wiki_path is None:
        print("Erro: wiki.md (raiz) ou docs/wiki.md nao encontrado no repo.", file=sys.stderr)
        return 1

    wiki_text = wiki_path.read_text(encoding="utf-8")
    raw_paths = parse_paths(wiki_text)

    # Sempre inclui a wiki encontrada, AGENTS global e o proprio script de export.
    paths = [
        wiki_path.relative_to(repo_root).as_posix(),
        "AGENTS.global.md",
        "tools/export_wiki_bundle.py",
    ] + raw_paths

    # Dedup preservando ordem
    seen = set()
    unique_paths = []
    for p in paths:
        if p not in seen:
            seen.add(p)
            unique_paths.append(p)

    files_to_add: list[Path] = []
    missing: list[str] = []
    for rel in unique_paths:
        rel_path = Path(rel)
        if is_excluded(rel_path):
            continue
        abs_path = repo_root / rel_path
        if abs_path.is_file():
            files_to_add.append(abs_path)
        elif abs_path.is_dir():
            files_to_add.extend(
                [
                    path
                    for path in abs_path.rglob("*")
                    if path.is_file() and not is_excluded(path.relative_to(repo_root))
                ]
            )
        else:
            if should_report_missing(rel_path):
                missing.append(rel)

    default_name = f"codex_export_{repo_root.name}.zip"
    output = Path(args.output) if args.output else (repo_root / default_name)
    output.parent.mkdir(parents=True, exist_ok=True)

    # Dedup por caminho relativo preservando ordem
    unique_files: list[Path] = []
    seen_rel = set()
    for file_path in files_to_add:
        rel = file_path.relative_to(repo_root)
        if rel in seen_rel:
            continue
        seen_rel.add(rel)
        unique_files.append(file_path)

    with ZipFile(output, "w", compression=ZIP_DEFLATED) as zipf:
        for file_path in unique_files:
            zipf.write(file_path, file_path.relative_to(repo_root))

    print(f"Gerado: {output}")
    print(f"Arquivos adicionados: {len(unique_files)}")
    print(f"Wiki usada: {wiki_path.relative_to(repo_root)}")
    print(f"Excluidos do bundle: {', '.join(EXCLUDED_PREFIXES)}")
    if missing:
        print("Aviso: caminhos listados na wiki nao encontrados:")
        for rel in missing:
            print(f"- {rel}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
