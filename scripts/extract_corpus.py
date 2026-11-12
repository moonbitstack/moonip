#!/usr/bin/env python3
"""Pull the literal address strings out of the two reference test suites.

This runs once, when the corpus is refreshed; the corpus it writes is what the
build uses. Both suites are pinned by tag in the arguments so the corpus can be
rebuilt exactly:

    python scripts/extract_corpus.py \
        --python-suite /tmp/test_ipaddress.py --go-suite /tmp/netip_test.go

CPython v3.13.12 ``Lib/test/test_ipaddress.py`` and Go go1.25.5
``src/net/netip/netip_test.go`` are the two files. Every quoted literal that could
be an address is taken, valid or not: the suites carry dozens of deliberately
broken ones and those are half the value.
"""
import argparse
import pathlib
import re

HERE = pathlib.Path(__file__).resolve().parent
CORPUS = HERE / "corpus"

# A single- or double-quoted literal, with the escapes left alone: none of the
# address cases need them and unescaping would invent characters.
LITERAL = re.compile(r'"((?:[^"\\]|\\.){1,60})"' + "|" + r"'((?:[^'\\]|\\.){1,60})'")
LOOKS_LIKE_ADDRESS = re.compile(r"^[0-9A-Za-z:.\[\]/_-]+$")


def collect(path):
    found = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        for match in LITERAL.finditer(line):
            text = match.group(1) if match.group(1) is not None else match.group(2)
            if "." not in text and ":" not in text:
                continue
            if not any(c.isdigit() for c in text):
                continue
            if not LOOKS_LIKE_ADDRESS.match(text):
                continue
            found.append(text)
    return found


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--python-suite", required=True)
    parser.add_argument("--go-suite", required=True)
    args = parser.parse_args()

    py = collect(pathlib.Path(args.python_suite))
    go = collect(pathlib.Path(args.go_suite))

    CORPUS.mkdir(parents=True, exist_ok=True)
    addresses = sorted(set(py) | set(go))
    prefixes = sorted(t for t in addresses if "/" in t)
    plain = sorted(t for t in addresses if "/" not in t)

    header = (
        "# Address strings taken from CPython v3.13.12 Lib/test/test_ipaddress.py\n"
        "# (%d candidates) and Go go1.25.5 src/net/netip/netip_test.go (%d candidates),\n"
        "# deduplicated and sorted. Rebuild with scripts/extract_corpus.py.\n"
        % (len(py), len(go))
    )
    (CORPUS / "addresses.txt").write_text(
        header + "\n".join(plain) + "\n", encoding="utf-8", newline="\n"
    )
    (CORPUS / "prefixes.txt").write_text(
        header + "\n".join(prefixes) + "\n", encoding="utf-8", newline="\n"
    )
    print("addresses: %d, prefixes: %d" % (len(plain), len(prefixes)))


if __name__ == "__main__":
    main()
