"""Formatting. Currently one formatter (Python comment stripping +
blank-line collapsing) but built so another language could register an
extension -> processor mapping without restructuring anything.
"""

from __future__ import annotations

import ast
import io
import tokenize
from pathlib import Path


class PythonCommentRemover:
    """Strips comments from Python source and collapses excess blank lines."""

    extensions = (".py",)

    def __init__(self, max_blank_lines: int = 2) -> None:
        self.max_blank_lines = max_blank_lines

    def process(self, source: str) -> str:
        if not source:
            return source
        lines = self._strip_comments(source)
        return self._collapse_blanks(lines)

    def _strip_comments(self, source: str) -> list[str]:
        readline = io.BytesIO(source.encode("utf-8")).readline
        original = source.splitlines(keepends=True)
        padded = [""] + original

        spans: dict[int, list[tuple[int, int]]] = {}
        try:
            for tok in tokenize.tokenize(readline):
                if tok.type == tokenize.COMMENT:
                    row, cs = tok.start
                    _, ce = tok.end
                    spans.setdefault(row, []).append((cs, ce))
        except tokenize.TokenError:
            return original

        result: list[str] = []
        for lineno, line in enumerate(padded):
            if lineno == 0:
                continue
            if lineno not in spans:
                result.append(line)
                continue
            chars = list(line)
            for cs, ce in sorted(spans[lineno], reverse=True):
                del chars[cs:ce]
            cleaned = "".join(chars).rstrip()
            ending = "\r\n" if line.endswith("\r\n") else "\n"
            result.append((cleaned + ending) if cleaned else ending)
        return result

    def _collapse_blanks(self, lines: list[str]) -> str:
        out: list[str] = []
        blanks = 0
        for line in lines:
            if line.strip() == "":
                blanks += 1
                if blanks <= self.max_blank_lines:
                    out.append(line)
            else:
                blanks = 0
                out.append(line)
        while out and out[0].strip() == "":
            out.pop(0)
        return "".join(out)


FORMATTERS = {".py": PythonCommentRemover}


def format_file(path: Path, max_blank_lines: int = 2) -> bool:
    """Format one file in place. Returns True if it changed."""
    cls = FORMATTERS.get(path.suffix.lower())
    if cls is None:
        return False

    try:
        source = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return False

    cleaned = cls(max_blank_lines=max_blank_lines).process(source)
    if cleaned == source:
        return False

    if path.suffix.lower() == ".py":
        try:
            ast.parse(cleaned)
        except SyntaxError:
            return False  # never write something that doesn't parse

    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(cleaned, encoding="utf-8")
    tmp.replace(path)
    return True


def format_paths(paths: list[Path], max_blank_lines: int = 2) -> list[Path]:
    """Format a batch of files. Returns the list that actually changed."""
    changed = []
    for p in paths:
        if format_file(p, max_blank_lines=max_blank_lines):
            changed.append(p)
    return changed
