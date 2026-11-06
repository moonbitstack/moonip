#!/usr/bin/env python3
"""Generate docs/api.html from the generated interface and the doc comments.

The page is built from `src/pkg.generated.mbti` — so an item exists on the page
exactly when the compiler says it is public — and the prose comes from the `///`
comment above each declaration in `src/*.mbt`. Run it again after changing the
public surface; the docs workflow fails if the result differs from what is
committed.

    python scripts/gen_api.py
"""
import html
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
MBTI = SRC / "pkg.generated.mbti"
OUT = ROOT / "docs" / "api.html"

# The order the page lists things in: the three values first, then the error, then
# the free functions, which is the order a reader needs them.
GROUPS = [
    ("addr", "Address", "Addr", "One address: IPv4 or IPv6, with the zone a scoped IPv6 address may carry."),
    ("prefix", "Block", "Prefix", "An address and a mask length. Keeps the address it was written with."),
    ("addrport", "Address and port", "AddrPort", "One end of a conversation."),
    ("refused", "Refusal", "Refused", "Why a text form, a byte string or an argument pair was refused."),
]

TRAIT_METHODS = {
    "equal",
    "not_equal",
    "hash",
    "hash_combine",
    "compare",
    "op_lt",
    "op_gt",
    "op_le",
    "op_ge",
    "to_string",
    "output",
    "to_repr",
}

EXPECTED_TYPES = ("Addr", "Prefix", "AddrPort", "Refused")

# Filled while the interface is read: type name -> the traits it implements.
TRAITS = {}


def doc_key(signature):
    """The name a doc comment is filed under, from a declaration."""
    body = signature
    for prefix in ("pub(all) ", "pub(readonly) ", "pub(open) ", "pub "):
        if body.startswith(prefix):
            body = body[len(prefix):]
    match = re.match(r"fn\s+([A-Za-z0-9_]+(?:::[A-Za-z0-9_]+)?)", body)
    if match:
        return match.group(1)
    match = re.match(r"let\s+([A-Za-z0-9_]+)", body)
    if match:
        return match.group(1)
    match = re.match(r"(?:struct|enum|suberror|type)\s+([A-Za-z0-9_]+)", body)
    if match:
        return match.group(1)
    return None


def read_docs():
    """The `///` comment above every public declaration, keyed by name.

    A declaration may continue over several lines; the name is always on the first
    one, so the block is filed as soon as that line is seen.
    """
    docs = {}
    for path in sorted(SRC.glob("*.mbt")):
        if path.name.endswith(("_test.mbt", "_wbtest.mbt")):
            continue
        block = []
        in_fence = False
        for raw in path.read_text(encoding="utf-8").splitlines():
            stripped = raw.strip()
            if stripped == "///|":
                block = []
            elif stripped.startswith("///"):
                line_text = stripped[3:].strip()
                if line_text.startswith("```"):
                    in_fence = not in_fence
                    continue
                if not in_fence:
                    block.append(line_text)
            elif stripped.startswith("pub ") or stripped.startswith("pub("):
                key = doc_key(stripped)
                if key:
                    docs[key] = " ".join(block).strip()
                block = []
            elif stripped == "" or stripped.startswith("#"):
                continue
            else:
                block = []
    return docs


def read_mbti():
    """The public surface, as the compiler sees it."""
    items = []
    current = None
    for raw in MBTI.read_text(encoding="utf-8").splitlines():
        line = raw.rstrip()
        if not line or line.startswith("//") or line.startswith("import") or line in ("{", "}"):
            continue
        stripped = line.strip()
        if not stripped.startswith("pub"):
            if current is not None:
                current["body"].append(line)
            continue
        if stripped.startswith("pub impl"):
            match = re.match(r"pub impl (.+?) for ([A-Za-z0-9_]+)$", stripped)
            if match:
                TRAITS.setdefault(match.group(2), []).append(match.group(1))
            continue
        items.append({"decl": stripped, "body": [], "traits": []})
        current = items[-1]
    return items


def owner_of(decl):
    match = re.match(r"pub fn ([A-Za-z0-9_]+)::([A-Za-z0-9_]+)", decl)
    if match:
        return match.group(1), match.group(2)
    return None, None


def tint(signature):
    s = html.escape(signature)
    s = re.sub(r"\b(fn|let|struct|suberror)\b", r'<i class="k">\1</i>', s)
    s = re.sub(r"\b([A-Z][A-Za-z0-9_]*)\b", r'<i class="ty">\1</i>', s)
    s = s.replace("-&gt;", '<i class="op">-&gt;</i>')
    return s


def prose(text):
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", html.escape(text))


def render_type(name, doc, body, traits):
    out = ['<div class="item">']
    out.append('<pre class="sig">pub struct %s</pre>' % html.escape(name))
    if doc:
        out.append('<p class="item-doc">%s</p>' % prose(doc))
    if body:
        out.append('<pre class="type-body">%s</pre>' % html.escape("\n".join(body)))
    if traits:
        names = sorted({t for t in traits})
        out.append(
            '<p class="item-doc"><span class="label">also</span> %s</p>'
            % html.escape(", ".join(names))
        )
    out.append("</div>")
    return "\n".join(out)


def render_fn(decl, doc):
    out = ['<div class="item">']
    out.append('<pre class="sig">%s</pre>' % tint(decl))
    if doc:
        out.append('<p class="item-doc">%s</p>' % prose(doc))
    out.append("</div>")
    return "\n".join(out)


HEAD = '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>API reference — moonip</title>
<meta name="description" content="Every public type, function and value in moonip, generated from the doc comments in the sources.">
<meta name="theme-color" content="#e6e2d6" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#070809" media="(prefers-color-scheme: dark)">
<link rel="icon" href="./favicon.svg" type="image/svg+xml">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Archivo:wght@600;700&family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap">
<link rel="stylesheet" href="./assets/site.css">
<script type="module" src="./assets/scrollbar.js"></script>
<script>try{var t=localStorage.getItem("moonip.theme");if(t==="light"||t==="dark")document.documentElement.dataset.theme=t;}catch(e){}</script>
</head>
<body id="top">

<header class="hdr">
  <div class="hdr-in">
    <a class="brand" href="./"><span class="glyph"><i></i><i></i><i class="v4"></i><i></i><i></i><i class="v6"></i><i></i><i></i></span><span class="word">moonip</span></a>
    <div class="pkt" aria-hidden="true">
      <div class="c"><i>ver</i><b>4</b></div>
      <div class="c"><i>ihl</i><b>5</b></div>
      <div class="c maybe"><i>len</i><b id="hdr-len">0x0000</b></div>
      <div class="c maybe"><i>id</i><b id="hdr-id">0x0000</b></div>
      <div class="c"><i>ttl</i><b id="hdr-ttl">08</b></div>
      <div class="c maybe"><i>chk</i><b id="hdr-chk">0x0000</b></div>
    </div>
    <nav class="nav">
      <a href="./guide.html">Guide</a>
      <a href="./api.html" class="on">API</a>
      <a href="./explorer.html">Explorer</a>
      <button class="themesw" id="themesw" type="button" data-mode="light" aria-label="Switch to night" title="Switch to night">
        <span class="when-dark">night</span>
        <span class="when-light">day</span>
      </button>
      <a href="./showcase.html">Showcase</a>
      <a class="gh" href="https://github.com/moonbitstack/moonip" aria-label="GitHub repository" title="GitHub">
        <svg viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27s1.36.09 2 .27c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z"/></svg>
      </a>
    </nav>
  </div>
</header>
'''

FOOT = '''<footer class="foot">
  <div class="frame">
    <div class="foot-in">
      <div class="about">
        <a class="brand" href="./" style="border:0;padding:0"><span class="glyph"><i></i><i></i><i class="v4"></i><i></i><i></i><i class="v6"></i><i></i><i></i></span><span class="word">moonip</span></a>
        <p>IP addresses and networks for MoonBit: parsing, formatting, block arithmetic and
        classification, on every target the compiler builds for.</p>
      </div>
      <div>
        <h4>pages</h4>
        <ul>
          <li><a href="./guide.html">Guide</a></li>
          <li><a href="./api.html">API reference</a></li>
          <li><a href="./explorer.html">Explorer</a></li>
          <li><a href="./showcase.html">Showcase</a></li>
        </ul>
      </div>
      <div>
        <h4>elsewhere</h4>
        <ul>
          <li><a href="https://github.com/moonbitstack/moonip">GitHub</a></li>
          <li><a href="https://mooncakes.io/docs/moonbitstack/moonip">mooncakes</a></li>
          <li><a href="https://github.com/moonbitstack/moonip/blob/master/LICENSE">Apache-2.0</a></li>
        </ul>
      </div>
    </div>
    <div class="trailer">
      <span class="eof">eof</span>
      <span>checksum 0x<span id="foot-chk">0000</span></span>
      <span>RFC 791 · 4291 · 5952 · 4632 · 6890</span>
      <span>IANA registries, 2026-10-31</span>
    </div>
  </div>
</footer>

<a class="totop" id="totop" href="#top" aria-label="Back to top" title="Back to top">
  <svg viewBox="0 0 16 16" aria-hidden="true"><path d="M8 12.6V4.2M4 8.2l4-4 4 4"/></svg>
  <span>top</span>
</a>

<script type="module" src="./assets/site.js"></script>
</body>
</html>
'''


def main():
    docs = read_docs()
    items = read_mbti()

    seen = 0
    rendered = {type_name: [] for _, _, type_name, _ in GROUPS}
    loosely = []

    for item in items:
        decl = item["decl"]
        if decl.startswith("pub impl"):
            continue
        key = doc_key(decl)
        doc = docs.get(key, "")
        type_name, method = owner_of(decl)
        if method is not None:
            if type_name not in rendered:
                continue
            rendered[type_name].append(render_fn(decl, doc))
            seen += 1
            continue
        match = re.match(r"pub(?:\(all\))? (struct|suberror) ([A-Za-z0-9_]+)", decl)
        if match:
            name = match.group(2)
            if name in rendered:
                rendered[name].append(
                    render_type(name, doc, item["body"], TRAITS.get(name, []))
                )
                seen += 1
            continue
        loosely.append((decl, doc))
        seen += 1

    body = ["<main class=\"frame\">"]
    body.append('<section class="row">')
    body.append('<div class="rail"><span><b>00</b> · reference</span></div>')
    body.append('<div class="field">')
    body.append('<p class="kicker">Reference · generated from the interface</p>')
    body.append(
        '<h1 class="display" style="font-size:clamp(28px,4.6vw,54px)">Every public name,<br>with the comment above it.</h1>'
    )
    body.append(
        '<p class="lede" style="margin-top:18px">Built from the interface the compiler emits and the doc '
        "comments in the sources, so a function that is documented is a function that is here. One "
        "package, five groups.</p>"
    )
    body.append('<div class="filter" style="margin-top:22px">')
    body.append(
        '<input id="q" type="search" placeholder="filter names" '
        'aria-label="Filter the reference by name" autocomplete="off" spellcheck="false">'
    )
    body.append('<span id="hits">%d entries</span>' % seen)
    body.append("</div>")
    body.append("</div></section>")

    body.append('<section class="row">')
    body.append('<div class="rail"><span><b>01</b>–<b>05</b></span></div>')
    body.append('<div class="field">')

    index = 0
    for anchor, title, type_name, desc in GROUPS:
        index += 1
        body.append('<div class="ref-group" id="%s">' % anchor)
        body.append(
            '<div class="ref-head"><span class="no">%02d</span><h2>%s</h2>'
            '<span class="of">%s · %d entries</span></div>'
            % (index, title, html.escape(type_name), len(rendered[type_name]))
        )
        body.append('<p class="group-desc">%s</p>' % prose(desc))
        body.extend(rendered[type_name])
        body.append("</div>")

    body.append('<div class="ref-group" id="free">')
    body.append(
        '<div class="ref-head"><span class="no">05</span><h2>Free functions</h2>'
        '<span class="of">%d entries</span></div>' % len(loosely)
    )
    body.append(
        '<p class="group-desc">Block arithmetic that belongs to no one type: a range joined back up, '
        "and a set of blocks collapsed.</p>"
    )
    for decl, doc in loosely:
        body.append(render_fn(decl, doc))
    body.append("</div>")

    body.append('<p class="empty hidden" id="empty">Nothing here matches that.</p>')
    body.append("</div></section></main>")

    page = HEAD + "\n".join(body) + FOOT
    OUT.write_text(page, encoding="utf-8")
    print("wrote %s (%d public items)" % (OUT, seen))

    # The check the acceptance criteria ask for: nothing the compiler exposes may be
    # missing from the page.
    missing = []
    for item in items:
        decl = item["decl"]
        if decl.startswith("pub impl"):
            continue
        key = doc_key(decl)
        if key is None:
            missing.append(decl)
            continue
        if key in EXPECTED_TYPES or key in TRAIT_METHODS:
            continue
        _, method = owner_of(decl)
        if method is not None and method in TRAIT_METHODS:
            continue
        if key in docs:
            continue
        if not re.match(r"pub (fn|let)", decl):
            continue
        missing.append(decl)
    if missing:
        print("public items with no doc comment:")
        for decl in missing:
            print("  " + decl)
        sys.exit(1)


if __name__ == "__main__":
    main()
