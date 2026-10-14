#!/usr/bin/env python3
"""`just i18n-check`: every language file must match the base locale.

Reads the `i18n` block from .quality.json, for example:

  "i18n": {
    "base": "en",
    "required": ["en", "nl"],
    "format": "json",
    "files": ["messages/{locale}.json"]
  }

  format     json (nested keys, plural objects) | strings (Apple .strings) | android (res/values*/strings.xml)
  files      one or more path patterns relative to the project root; `{locale}` marks the language
  base_file  optional stand-in for `{locale}` in the base file name (Shopify: "en.default")

Locales are discovered from the files on disk. Per pattern, every locale must have exactly
the base's keys and the same placeholders per key ({x}, Liquid's double-brace x, %@, %d,
%1$s), and every `required` locale must exist. Without an `i18n` block it prints `i18n: not configured` and
exits 0, so templates without i18n carry the check dormant.

Each run phones home via _diag.log() so the upstream repo can audit the check's health.
"""
from __future__ import annotations

import json
import re
import sys
import time
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

HOOK = "check_i18n"

try:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import _diag
except Exception:
    _diag = None


def _diag_log(status: str, duration_ms: int, meta: dict | None = None, error: BaseException | None = None) -> None:
    if _diag is None:
        return
    try:
        _diag.log(HOOK, status, duration_ms, meta=meta, error=error)
    except Exception:
        return


LOCALE_TOKEN = r"[a-z]{2,3}(?:[-_][A-Za-z0-9]{2,8})*"
PLURAL_FORMS = {"zero", "one", "two", "few", "many", "other"}
PLACEHOLDER = re.compile(
    r"\{\{\s*(?P<liquid>[\w.]+)\s*\}\}"
    r"|\{\s*(?P<brace>[A-Za-z_]\w*)\s*[,}]"
    r"|(?P<printf>%(?:\d+\$)?[-+0#]*\d*(?:\.\d+)?(?:ll|l|h|q|z)?[@dDiuUxXoOfFeEgGcCsSpaA])"
)
STRINGS_ENTRY = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', re.M)


def placeholders(text: str) -> Counter[str]:
    # Braces are concatenated, never written adjacent: cookiecutter renders this file through
    # Jinja, which would treat a literal double brace or brace-percent as template syntax.
    found: Counter[str] = Counter()
    for m in PLACEHOLDER.finditer(text.replace("%%", "")):
        if m["liquid"]:
            found["{" + "{ " + m["liquid"] + " }" + "}"] += 1
        elif m["brace"]:
            found["{" + m["brace"] + "}"] += 1
        else:
            # Position, flags, width and precision don't change the argument: %1$s == %s, %-d == %d.
            found[re.sub(r"^%(?:\d+\$)?[-+0#]*\d*(?:\.\d+)?", "%", m["printf"])] += 1
    return found


def _strings_in(node: object) -> list[str]:
    if isinstance(node, str):
        return [node]
    values = node.values() if isinstance(node, dict) else node if isinstance(node, list) else []
    return [s for value in values for s in _strings_in(value)]


def _variant_placeholders(texts: list[str]) -> Counter[str]:
    # Plural forms and variants may use a placeholder in some forms only ("1 file" / "{count} files").
    return Counter(set().union(*(placeholders(t) for t in texts)))


def _is_plural(node: object) -> bool:
    return isinstance(node, dict) and bool(node) and set(node) <= PLURAL_FORMS and "other" in node


def _flatten(node: object, prefix: str, out: dict[str, Counter[str]]) -> None:
    if isinstance(node, dict) and not _is_plural(node):
        for key, value in node.items():
            if not key.startswith("$"):
                _flatten(value, f"{prefix}.{key}" if prefix else key, out)
    elif isinstance(node, str):
        out[prefix] = placeholders(node)
    else:
        out[prefix] = _variant_placeholders(_strings_in(node))


def read_json(path: Path) -> dict[str, Counter[str]]:
    out: dict[str, Counter[str]] = {}
    _flatten(json.loads(path.read_text(encoding="utf-8-sig")), "", out)
    return out


def read_strings(path: Path) -> dict[str, Counter[str]]:
    raw = path.read_bytes()
    text = raw.decode("utf-16") if raw[:2] in (b"\xff\xfe", b"\xfe\xff") else raw.decode("utf-8-sig")
    return {key: placeholders(value) for key, value in STRINGS_ENTRY.findall(text)}


def read_android(path: Path) -> dict[str, Counter[str]]:
    out: dict[str, Counter[str]] = {}
    for el in ET.parse(path).getroot():
        name = el.get("name")
        if name is None or el.get("translatable") == "false":
            continue
        if el.tag == "string":
            out[name] = placeholders("".join(el.itertext()))
        elif el.tag in ("plurals", "string-array"):
            out[name] = _variant_placeholders(["".join(item.itertext()) for item in el])
    return out


READERS = {"json": read_json, "strings": read_strings, "android": read_android}


def base_path(pattern: str, cfg: dict) -> str:
    if cfg.get("format") == "android":
        return pattern.replace("-{locale}", "")
    return pattern.replace("{locale}", cfg.get("base_file", cfg["base"]))


def discover(root: Path, pattern: str, cfg: dict) -> dict[str, Path]:
    head, _, tail = pattern.partition("{locale}")
    token = re.compile(re.escape(head) + f"({LOCALE_TOKEN})" + re.escape(tail) + r"\Z")
    found = {}
    for path in root.glob(head + "*" + tail):
        m = token.match(path.relative_to(root).as_posix())
        if m:
            found[m.group(1)] = path
    base_file = root / base_path(pattern, cfg)
    if base_file.is_file():
        found[cfg["base"]] = base_file
    return found


def _show(counter: Counter[str]) -> str:
    return " ".join(sorted(counter.elements())) or "(none)"


def check_pattern(root: Path, pattern: str, cfg: dict, locales: set[str]) -> list[str]:
    base, read = cfg["base"], READERS[cfg["format"]]
    files = discover(root, pattern, cfg)
    locales.update(files)
    problems = [
        f"{loc}: missing {base_path(pattern, cfg) if loc == base else pattern.replace('{locale}', loc)}"
        for loc in sorted(set(cfg["required"]) | {base}) if loc not in files
    ]
    parsed = {}
    for loc, path in sorted(files.items()):
        try:
            parsed[loc] = read(path)
        except (ValueError, ET.ParseError) as e:
            problems.append(f"{path.relative_to(root).as_posix()}: cannot parse ({e})")
    if base not in parsed:
        return problems
    expected = parsed.pop(base)
    for loc, entries in parsed.items():
        rel = files[loc].relative_to(root).as_posix()
        problems += [f"{rel}: missing key {key}" for key in sorted(expected.keys() - entries.keys())]
        problems += [f"{rel}: extra key {key}" for key in sorted(entries.keys() - expected.keys())]
        problems += [
            f"{rel}: placeholders differ for {key}: {base} {_show(expected[key])} / {loc} {_show(entries[key])}"
            for key in sorted(expected.keys() & entries.keys()) if expected[key] != entries[key]
        ]
    return problems


def load_config(root: Path) -> dict | None:
    quality = root / ".quality.json"
    if not quality.is_file():
        return None
    cfg = json.loads(quality.read_text(encoding="utf-8")).get("i18n")
    if cfg is None:
        return None
    cfg = {"base": "en", "format": "json", **cfg}
    cfg.setdefault("required", [cfg["base"]])
    if cfg["format"] not in READERS or not cfg.get("files"):
        raise SystemExit(f"i18n: bad .quality.json i18n block (format one of {sorted(READERS)}, files non-empty): {cfg}")
    return cfg


def main() -> int:
    started = time.monotonic()
    root = Path.cwd()
    try:
        cfg = load_config(root)
        if cfg is None:
            print("i18n: not configured")
            _diag_log("noop", int((time.monotonic() - started) * 1000), meta={"reason": "not-configured"})
            return 0
        locales: set[str] = set()
        problems = [p for pattern in cfg["files"] for p in check_pattern(root, pattern, cfg, locales)]
    except Exception as e:
        _diag_log("error", int((time.monotonic() - started) * 1000), error=e)
        raise
    meta = {"locales": sorted(locales), "problems": len(problems)}
    _diag_log("ok", int((time.monotonic() - started) * 1000), meta=meta)
    for problem in problems:
        print(f"i18n: FAIL {problem}")
    if problems:
        print(f"i18n: {len(problems)} problem(s); every key in the base ({cfg['base']}) file must exist in each language file")
        return 1
    print(f"i18n: ok ({', '.join(sorted(locales))}; {len(cfg['files'])} file set(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
