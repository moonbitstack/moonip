#!/usr/bin/env python3
"""Check the skill's frontmatter: the name the registry files it under has to be
the module's, and the description has to say what the package does and when an
agent should reach for it, because that description is all an agent sees before
deciding to read the file.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SKILL = ROOT / "docs" / "skills" / "moonip" / "SKILL.md"
NAME = "moonip"


def main():
    text = SKILL.read_text(encoding="utf-8")
    front = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not front:
        sys.exit("SKILL.md has no frontmatter")
    fields = {}
    for line in front.group(1).splitlines():
        if ":" in line:
            key, value = line.split(":", 1)
            fields[key.strip()] = value.strip()
    if fields.get("name") != NAME:
        sys.exit("SKILL.md name must be %r, found %r" % (NAME, fields.get("name")))
    description = fields.get("description", "")
    if len(description) < 40:
        sys.exit("SKILL.md description is too short to choose on")
    print("SKILL.md: name %s, description %d characters" % (NAME, len(description)))


if __name__ == "__main__":
    main()
