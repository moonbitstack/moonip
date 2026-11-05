#!/usr/bin/env python3
"""Generate the differential vectors under src/ from two mature implementations.

CPython's ipaddress and Go's net/netip are run over the same corpus. A row is kept
only when both agree on it; the rows where they disagree are printed and are
covered instead by hand-written tests that state which side this library takes and
why.

    python scripts/gen_vectors.py

The result is written and then formatted; CI runs this and fails when the
regenerated files differ from the committed ones.

The corpus in scripts/corpus comes from the two test suites (see
extract_corpus.py); the cases added here are the boundaries the suites do not
happen to spell out, plus a fixed-seed random sample so formatting is exercised on
shapes nobody thought to write down.
"""
import argparse
import ipaddress
import json
import pathlib
import random
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CORPUS = ROOT / "scripts" / "corpus"
SRC = ROOT / "src"

CHUNK = 120

CURATED_ADDRESSES = [
    "",
    " ",
    "1.2.3.4 ",
    " 1.2.3.4",
    "1.2.3.4\n",
    "1.2.3",
    "1.2.3.4.5",
    "1.2.3.256",
    "1.2.3.-1",
    "1.2.3.+1",
    "01.2.3.4",
    "1.2.3.04",
    "1.2.3.0004",
    "0.0.0.0",
    "255.255.255.255",
    "127.0.0.1",
    "0x7f.0.0.1",
    "127.1",
    "1.2.3.4/24",
    "[1.2.3.4]",
    "::",
    "::1",
    ":::",
    "1::2::3",
    "1:2:3:4:5:6:7:8",
    "1:2:3:4:5:6:7:8:9",
    "1:2:3:4:5:6:7",
    "12345::",
    "::ffff:1.2.3.4",
    "::ffff:01.2.3.4",
    "::1.2.3.4",
    "::1.2.3.256",
    "1:2:3:4:5:6:1.2.3.4",
    "1:2:3:4:5:6:7:1.2.3.4",
    "fe80::1%eth0",
    "fe80::1%",
    "fe80::1%a%b",
    "fe80::1%abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz",
    "::%eth0",
    "1.2.3.4%eth0",
    "[::1]",
    ":",
    "::1:",
    "1:",
    "2001:0DB8:0000:0000:0000:0000:0000:0001",
    "2002:c000:204::1",
    "2001:0:4136:e378:8000:63bf:3fff:fdd2",
    "64:ff9b::1.2.3.4",
    "::ffff:0:0",
    "0:0:0:0:0:0:0:0",
    "0000:0000:0000:0000:0000:0000:0000:0000",
]

CURATED_PREFIXES = [
    "",
    "/",
    "/24",
    "1.2.3.0/",
    "1.2.3.0/24/8",
    "1.2.3.0/-1",
    "1.2.3.0/+24",
    "1.2.3.0/024",
    "1.2.3.0/0",
    "1.2.3.0/32",
    "1.2.3.0/33",
    "1.2.3.4/24",
    "0.0.0.0/0",
    "255.255.255.255/32",
    "::/0",
    "::/128",
    "::/129",
    "2001:db8::1/32",
    "fe80::1%eth0/64",
    "fe80::/10",
    "::1/128",
    "2001:db8::/32",
    "10.0.0.0/8",
]

CURATED_ADDRPORTS = [
    "",
    "1.2.3.4",
    "1.2.3.4:",
    ":80",
    "1.2.3.4:0",
    "1.2.3.4:80",
    "1.2.3.4:65535",
    "1.2.3.4:65536",
    "1.2.3.4:080",
    "1.2.3.4:+80",
    "1.2.3.4:-1",
    "1.2.3.4: 80",
    "[::1]:80",
    "[::1]",
    "[::1]:",
    "[]:80",
    "[1.2.3.4]:80",
    "::1:80",
    "[::]:0",
    "[fe80::1%eth0]:80",
    "[::1]:65536",
    "[::1]x:80",
]


def mbt_str(text):
    out = text.replace("\\", "\\\\").replace('"', '\\"')
    out = out.replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")
    return '"' + out + '"'


def mbt_bool(value):
    return "true" if value else "false"


def run_go(requests):
    payload = json.dumps(requests)
    proc = subprocess.run(
        ["go", "run", str(ROOT / "scripts" / "reference_netip.go")],
        input=payload,
        capture_output=True,
        text=True,
        cwd=ROOT,
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr)
        raise SystemExit("the Go reference helper failed")
    return json.loads(proc.stdout)


def py_address(text):
    try:
        return ipaddress.ip_address(text)
    except ValueError:
        return None


def py_network(text, strict):
    try:
        return ipaddress.ip_network(text, strict=strict)
    except ValueError:
        return None


def exploded_of(addr):
    try:
        return addr.exploded
    except (AttributeError, ValueError):
        # CPython cannot explode a scoped address; the bits are still well defined.
        return None


def host_range(net):
    """First and last usable host, and how many there are, without walking them."""
    bits = net.prefixlen
    total = net.num_addresses
    if net.version == 4:
        if bits == 32:
            return str(net.network_address), str(net.network_address), "1"
        if bits == 31:
            return str(net.network_address), str(net.broadcast_address), "2"
        count = total - 2
        first = str(net.network_address + 1)
        last = str(net.broadcast_address - 1)
    else:
        if bits == 128:
            return str(net.network_address), str(net.network_address), "1"
        if bits == 127:
            return str(net.network_address), str(net[-1]), "2"
        count = total - 1
        first = str(net.network_address + 1)
        last = str(net[-1])
    return first, last, str(count) if count <= 4096 else "many"


def predicates(addr):
    site_local = getattr(addr, "is_site_local", False)
    return {
        "private": addr.is_private,
        "global": addr.is_global,
        "loopback": addr.is_loopback,
        "unspecified": addr.is_unspecified,
        "multicast": addr.is_multicast,
        "link_local": addr.is_link_local,
        "reserved": addr.is_reserved,
        "site_local": site_local,
    }


FLAG_ORDER = [
    "private",
    "global",
    "loopback",
    "unspecified",
    "multicast",
    "link_local",
    "reserved",
    "site_local",
]


def flags_of(addr):
    values = predicates(addr)
    bits = 0
    for index, name in enumerate(FLAG_ORDER):
        if values[name]:
            bits |= 1 << index
    return bits


def read_corpus(name):
    path = CORPUS / name
    if not path.exists():
        raise SystemExit("missing corpus file " + str(path))
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        rows.append(line)
    return rows


def render_chunks(doc, signature, rows, render, header):
    lines = [header, ""]
    total = len(rows)
    index = 0
    chunk = 0
    while index < total or chunk == 0:
        chunk += 1
        part = rows[index:index + CHUNK]
        lines.append("///|")
        lines.append("/// " + doc % (chunk, len(part)))
        lines.append("fn %s_%d() -> %s {" % (signature, chunk, signature_type(signature)))
        lines.append("  [")
        for row in part:
            lines.append("    " + render(row) + ",")
        lines.append("  ]")
        lines.append("}")
        lines.append("")
        index += CHUNK
    lines.append("///|")
    lines.append("/// Every `%s` row, in one array." % signature)
    lines.append("fn %s() -> %s {" % (signature, signature_type(signature)))
    lines.append("  let all : %s = []" % signature_type(signature))
    for part in range(1, chunk + 1):
        lines.append("  all.append(%s_%d()[:])" % (signature, part))
    lines.append("  all")
    lines.append("}")
    lines.append("")
    return "\n".join(lines) + "\n"


SIGNATURE_TYPES = {
    "addr_text_cases": "Array[(String, Bool, String, String, String)]",
    "addr_class_cases": "Array[(String, Int32)]",
    "go_class_cases": "Array[(String, Int32)]",
    "prefix_parse_cases": "Array[(String, Bool, String, String)]",
    "prefix_shape_cases": "Array[(String, String, String, String, String, String, String, String)]",
    "exclude_cases": "Array[(String, String, String)]",
    "summarize_cases": "Array[(String, String, String)]",
    "collapse_cases": "Array[(String, String)]",
    "subnets_cases": "Array[(String, Int32, String)]",
    "supernet_cases": "Array[(String, Int32, String)]",
    "addrport_cases": "Array[(String, Bool, String)]",
}


def signature_type(name):
    return SIGNATURE_TYPES[name]


def chunk_count(total):
    return max(1, (total + CHUNK - 1) // CHUNK)


def main():
    argparse.ArgumentParser().parse_args()

    random.seed(20261106)
    addresses = sorted(set(read_corpus("addresses.txt")) | set(CURATED_ADDRESSES))
    prefixes = sorted(set(read_corpus("prefixes.txt")) | set(CURATED_PREFIXES))

    # A fixed sample on top of the suites: random bits find formatting and masking
    # mistakes that hand-picked cases miss.
    sample = []
    for _ in range(120):
        value = random.getrandbits(32)
        sample.append(str(ipaddress.IPv4Address(value)))
    for _ in range(240):
        value = random.getrandbits(128)
        sample.append(str(ipaddress.IPv6Address(value)))
    for _ in range(60):
        value = random.getrandbits(32)
        bits = random.randint(0, 32)
        sample.append("%s/%d" % (ipaddress.IPv4Address(value), bits))
    for _ in range(60):
        value = random.getrandbits(128)
        bits = random.randint(0, 128)
        sample.append("%s/%d" % (ipaddress.IPv6Address(value), bits))

    all_text = sorted(set(addresses) | set(sample))
    go_answer = run_go({
        "addrs": all_text,
        "prefixes": prefixes,
        "addrports": sorted(set(CURATED_ADDRPORTS)),
    })
    go_addrs = dict(zip(all_text, go_answer["addrs"]))
    go_prefixes = dict(zip(prefixes, go_answer["prefixes"]))
    go_addrports = dict(zip(sorted(set(CURATED_ADDRPORTS)), go_answer["addrports"]))

    divergences = []
    text_rows = []
    for text in all_text:
        py = py_address(text)
        go = go_addrs[text]
        if (py is not None) != go["ok"]:
            divergences.append(
                "address %-52r python=%s go=%s" % (text, bool(py), go["ok"])
            )
            continue
        if py is None:
            text_rows.append((text, False, "", "", ""))
            continue
        canonical = str(py)
        if canonical != go["text"]:
            divergences.append(
                "format  %-52r python=%s go=%s" % (text, canonical, go["text"])
            )
            continue
        packed = py.packed.hex()
        if packed != go["bytes"]:
            divergences.append("bytes   %-52r python=%s go=%s" % (text, packed, go["bytes"]))
            continue
        # The two write an IPv4-mapped address differently in the expanded form
        # (dotted against hexadecimal) and Go appends the zone where CPython cannot
        # expand a scoped address at all; those rows are settled by hand below.
        mapped = py.version == 6 and int(py) >> 32 == 0xFFFF and int(py) >> 48 == 0
        if mapped or go["zoned"]:
            exploded = "-"
        else:
            exploded = exploded_of(py)
            if exploded is None or go["expanded"] != exploded:
                divergences.append(
                    "explode %-52r python=%s go=%s" % (text, exploded, go["expanded"])
                )
                continue
        text_rows.append((text, True, canonical, exploded, packed))

    # Prefixes: Python's strict form is the stricter of the two, Go is the looser.
    prefix_parse_rows = []
    prefix_shape_cases = []
    for text in prefixes:
        go = go_prefixes[text]
        strict_net = py_network(text, True) if "/" in text else None
        relaxed_net = py_network(text, False) if "/" in text else None
        strict_text = str(strict_net) if strict_net is not None else ""
        relaxed_text = str(relaxed_net) if relaxed_net is not None else ""
        if go["ok"] != (relaxed_net is not None):
            divergences.append(
                "prefix  %-40r python=%s go=%s" % (text, relaxed_net is not None, go["ok"])
            )
            continue
        if go["ok"] and go["masked"] != relaxed_text:
            divergences.append(
                "masked  %-40r python=%s go=%s" % (text, relaxed_text, go["masked"])
            )
            continue
        prefix_parse_rows.append((text, strict_net is not None, strict_text, relaxed_text))
        if relaxed_net is None:
            continue
        net = relaxed_net
        first_host, last_host, host_count = host_range(net)
        prefix_shape_cases.append((
            text,
            str(net),
            str(net.netmask),
            str(net.hostmask),
            str(net.broadcast_address) if net.version == 4 else "-",
            first_host,
            last_host,
            host_count,
        ))

    class_rows = []
    class_source = sorted({row[0] for row in text_rows if row[1]})
    for text in class_source:
        addr = py_address(text)
        if addr is None:
            continue
        class_rows.append((text, flags_of(addr)))

    go_class_rows = []
    # The four predicates net/netip keeps that mean the same thing here; the flags
    # are positioned to match FLAG_ORDER so a row can be compared with the other.
    GO_FLAGS = [
        ("loopback", 1 << FLAG_ORDER.index("loopback")),
        ("multicast", 1 << FLAG_ORDER.index("multicast")),
        ("link_local", 1 << FLAG_ORDER.index("link_local")),
        ("unspecified", 1 << FLAG_ORDER.index("unspecified")),
    ]
    GO_MASK = 0
    for _, bit in GO_FLAGS:
        GO_MASK |= bit
    for text, ours in class_rows:
        go = go_addrs[text]
        bits = 0
        for name, bit in GO_FLAGS:
            if go[name]:
                bits |= bit
        ours_bits = ours & GO_MASK
        if bits != ours_bits:
            divergences.append(
                "class   %-40r python-flags=%d go-flags=%d" % (text, ours_bits, bits)
            )
            continue
        go_class_rows.append((text, bits))

    # Operations: ipaddress is the only one of the two that has them.
    exclude_rows = []
    exclude_pairs = [
        ("192.0.2.0/28", "192.0.2.1/32"),
        ("192.0.2.0/24", "192.0.2.0/24"),
        ("192.0.2.0/24", "192.0.2.128/25"),
        ("192.0.2.0/24", "192.0.3.0/24"),
        ("10.0.0.0/8", "10.0.0.0/16"),
        ("10.0.0.0/8", "10.0.0.0/9"),
        ("0.0.0.0/0", "10.0.0.0/8"),
        ("2001:db8::/32", "2001:db8::1/128"),
        ("2001:db8::/32", "2001:db8:8000::/33"),
        ("::/0", "::/1"),
        ("192.0.2.0/30", "192.0.2.2/32"),
    ]
    for _ in range(24):
        base = ipaddress.IPv4Network("10.%d.0.0/16" % random.randint(0, 255))
        pick = int(base.network_address) + random.randrange(base.num_addresses)
        bits = random.randint(17, 28)
        inner = ipaddress.ip_network((ipaddress.IPv4Address(pick), bits), strict=False)
        exclude_pairs.append((str(base), str(inner)))
    for _ in range(12):
        base = ipaddress.IPv6Network("2001:db8::/32")
        pick = int(base.network_address) + random.randrange(1 << 32)
        bits = random.randint(33, 64)
        inner = ipaddress.ip_network((ipaddress.IPv6Address(pick), bits), strict=False)
        exclude_pairs.append((str(base), str(inner)))

    for a, b in exclude_pairs:
        left = py_network(a, False)
        right = py_network(b, False)
        try:
            parts = [str(part) for part in left.address_exclude(right)]
        except (ValueError, TypeError, AttributeError):
            continue
        exclude_rows.append((a, b, "|".join(parts)))

    summarize_rows = []
    summarize_pairs = [
        ("192.0.2.0", "192.0.2.130"),
        ("192.0.2.1", "192.0.2.1"),
        ("0.0.0.0", "255.255.255.255"),
        ("10.0.0.0", "10.0.0.255"),
        ("2001:db8::", "2001:db8::ff"),
    ]
    for _ in range(40):
        start = random.getrandbits(32)
        span = random.randint(0, 4000)
        first = ipaddress.IPv4Address(start)
        last = ipaddress.IPv4Address(min(start + span, 0xFFFFFFFF))
        summarize_pairs.append((str(first), str(last)))
    for _ in range(20):
        start = random.getrandbits(96)
        span = random.randint(0, 2000)
        first = ipaddress.IPv6Address((0x2001 << 112) | start)
        last = ipaddress.IPv6Address(int(first) + span)
        summarize_pairs.append((str(first), str(last)))

    for first, last in summarize_pairs:
        blocks = ipaddress.summarize_address_range(
            ipaddress.ip_address(first), ipaddress.ip_address(last)
        )
        summarize_rows.append((first, last, "|".join(str(block) for block in blocks)))

    collapse_rows = []
    collapse_sets = [
        ["192.0.2.0/25", "192.0.2.128/25"],
        ["192.0.2.0/26", "192.0.2.64/26", "192.0.2.128/26", "192.0.2.192/26"],
        ["192.0.2.0/24", "192.0.2.128/25"],
        ["2001:db8::/33", "2001:db8:8000::/33"],
        ["10.0.0.0/9", "10.128.0.0/9"],
        ["10.0.0.0/8", "10.1.0.0/16", "11.0.0.0/8"],
    ]
    for _ in range(24):
        base = ipaddress.IPv4Network("172.16.0.0/12")
        pieces = random.sample(list(base.subnets(new_prefix=24)), 6)
        collapse_sets.append([str(piece) for piece in pieces])
    for pieces in collapse_sets:
        nets = [py_network(item, False) for item in pieces]
        collapsed = [str(net) for net in ipaddress.collapse_addresses(nets)]
        collapse_rows.append(("|".join(pieces), "|".join(collapsed)))

    subnets_rows = []
    supernet_rows = []
    for text, bits in [
        ("10.0.0.0/8", 9),
        ("10.0.0.0/8", 10),
        ("192.0.2.0/24", 26),
        ("192.0.2.0/24", 24),
        ("192.0.2.0/32", 32),
        ("2001:db8::/32", 34),
        ("::/0", 2),
    ]:
        net = py_network(text, False)
        subnets_rows.append((text, bits, "|".join(str(part) for part in net.subnets(new_prefix=bits))))
        if bits <= net.prefixlen:
            supernet_rows.append((text, bits, str(net.supernet(new_prefix=bits))))

    # ipaddress has no address-with-port type, so this form is checked against
    # net/netip alone.
    addrport_rows = []
    for text in sorted(set(CURATED_ADDRPORTS)):
        go = go_addrports[text]
        addrport_rows.append((text, go["ok"], go["text"] if go["ok"] else ""))

    # The interpreter version is left out on purpose: a run with another 3.x would
    # otherwise rewrite every table for a comment, and the data it produces would
    # show up as a diff anyway.
    header = (
        "// Generated by scripts/gen_vectors.py. Do not edit.\n"
        "//\n"
        "// CPython ipaddress (3.13) and Go go1.25.5 net/netip were run over the same\n"
        "// corpus; only rows where both agree are kept.\n"
    )

    outputs = {
        "src/vectors_addr_text_wbtest.mbt": render_chunks(
            "Text cases, part %d (%d rows).", "addr_text_cases", text_rows,
            lambda row: "(%s, %s, %s, %s, %s)" % (
                mbt_str(row[0]), mbt_bool(row[1]), mbt_str(row[2]), mbt_str(row[3]), mbt_str(row[4])
            ), header),
        "src/vectors_addr_class_wbtest.mbt": render_chunks(
            "Classification cases, part %d (%d rows).", "addr_class_cases", class_rows,
            lambda row: "(%s, %d)" % (mbt_str(row[0]), row[1]), header),
        "src/vectors_go_class_wbtest.mbt": render_chunks(
            "Classification cases cross-checked with Go, part %d (%d rows).", "go_class_cases",
            go_class_rows, lambda row: "(%s, %d)" % (mbt_str(row[0]), row[1]), header),
        "src/vectors_prefix_parse_wbtest.mbt": render_chunks(
            "Prefix parsing cases, part %d (%d rows).", "prefix_parse_cases", prefix_parse_rows,
            lambda row: "(%s, %s, %s, %s)" % (
                mbt_str(row[0]), mbt_bool(row[1]), mbt_str(row[2]), mbt_str(row[3])
            ), header),
        "src/vectors_prefix_shape_wbtest.mbt": render_chunks(
            "Prefix shape cases, part %d (%d rows).", "prefix_shape_cases", prefix_shape_cases,
            lambda row: "(%s)" % ", ".join(mbt_str(item) for item in row), header),
        "src/vectors_prefix_ops_wbtest.mbt": (
            render_chunks("Block arithmetic cases, part %d (%d rows).", "exclude_cases",
                          exclude_rows,
                          lambda row: "(%s, %s, %s)" % (mbt_str(row[0]), mbt_str(row[1]), mbt_str(row[2])),
                          header)
            + render_chunks("Range summarising cases, part %d (%d rows).", "summarize_cases",
                            summarize_rows,
                            lambda row: "(%s, %s, %s)" % (mbt_str(row[0]), mbt_str(row[1]), mbt_str(row[2])),
                            header)
            + render_chunks("Collapsing cases, part %d (%d rows).", "collapse_cases",
                            collapse_rows,
                            lambda row: "(%s, %s)" % (mbt_str(row[0]), mbt_str(row[1])),
                            header)
            + render_chunks("Splitting cases, part %d (%d rows).", "subnets_cases",
                            subnets_rows,
                            lambda row: "(%s, %d, %s)" % (mbt_str(row[0]), row[1], mbt_str(row[2])),
                            header)
            + render_chunks("Joining cases, part %d (%d rows).", "supernet_cases",
                            supernet_rows,
                            lambda row: "(%s, %d, %s)" % (mbt_str(row[0]), row[1], mbt_str(row[2])),
                            header)
        ),
        "src/vectors_addr_port_wbtest.mbt": render_chunks(
            "Address-and-port cases, part %d (%d rows).", "addrport_cases", addrport_rows,
            lambda row: "(%s, %s, %s)" % (mbt_str(row[0]), mbt_bool(row[1]), mbt_str(row[2])),
            header),
    }

    for name, content in outputs.items():
        (ROOT / name).write_text(content, encoding="utf-8")

    print("addresses: %d rows (%d accepted)" % (len(text_rows), sum(1 for r in text_rows if r[1])))
    print("classification: %d rows, Go cross-check: %d rows" % (len(class_rows), len(go_class_rows)))
    print("prefixes: %d parse rows, %d shape rows" % (len(prefix_parse_rows), len(prefix_shape_cases)))
    print("exclude %d, summarize %d, collapse %d, subnets %d, supernet %d"
          % (len(exclude_rows), len(summarize_rows), len(collapse_rows), len(subnets_rows), len(supernet_rows)))
    print("address and port: %d rows" % len(addrport_rows))
    if divergences:
        print("")
        print("the two references disagree on %d rows:" % len(divergences))
        for line in divergences:
            print("  " + line)


if __name__ == "__main__":
    main()
