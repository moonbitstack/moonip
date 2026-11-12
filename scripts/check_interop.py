#!/usr/bin/env python3
"""Have two mature implementations read what this library writes.

The vectors under `src/` check one direction: CPython's ipaddress and Go's
net/netip produce the answers, and the library replays them. This checks the
other direction, which the vectors cannot see: the library writes the text and
the bytes, and the two references read them back and say the same thing. A form
only this library likes fails here.

    python scripts/check_interop.py

The rows come from `src/examples/03-exchange`, which prints, for each input on its
command line, the canonical text, the encoded bytes, and for a block the two masks
and the broadcast address. Inputs the library refuses are reported as such and
skipped: refusing a malformed string is the vectors' business, not this one's.
"""

import ipaddress
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CORPUS = ROOT / "scripts" / "corpus"
EXAMPLE = "src/examples/03-exchange"
BATCH = 200

# Addresses and blocks the sample corpus does not happen to contain, chosen for
# what they do to a writer: the compression tie, the mapped tail, the ends of each
# family, and the two transition forms.
EXTRA = [
    "0.0.0.0", "255.255.255.255", "127.0.0.1", "169.254.1.1", "192.0.2.1",
    "100.64.0.1", "224.0.0.1", "240.0.0.1", "1.2.3.4",
    "::", "::1", "::ffff:0:0", "::ffff:192.0.2.1", "::192.0.2.1",
    "1::", "1::1", "1:0:0:2:0:0:3:4", "1:0:0:2:0:0:0:3", "0:0:0:0:0:0:0:1",
    "2001:db8::1", "2001:db8:0:0:1:0:0:1", "2002:c000:204::1",
    "2001:0:4136:e378:8000:63bf:3fff:fdd2", "fe80::1", "fe80::1%eth0",
    "fc00::1", "ff02::1", "ff01::1", "64:ff9b::1.2.3.4", "3fff::1",
    "0.0.0.0/0", "10.0.0.0/8", "192.0.2.0/24", "192.0.2.7/32", "203.0.113.0/26",
    "::/0", "::/1", "2001:db8::/32", "2001:db8::/64", "fe80::/10", "ff00::/8",
]


def corpus():
    rows = []
    for name in ("addresses.txt", "prefixes.txt"):
        path = CORPUS / name
        for line in path.read_text(encoding="utf-8").splitlines():
            if line and not line.startswith("#"):
                rows.append(line)
    rows.extend(EXTRA)
    # Order does not matter, repetition does not help.
    return list(dict.fromkeys(rows))


def read_rows(inputs):
    """Run the example over a batch and return (rows by input, refused inputs)."""
    rows, refused = {}, set()
    for start in range(0, len(inputs), BATCH):
        part = inputs[start:start + BATCH]
        proc = subprocess.run(
            ["moon", "run", EXAMPLE, "--target", "native", "--", *part],
            cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace",
        )
        if proc.returncode != 0:
            sys.stderr.write(proc.stdout + proc.stderr)
            raise SystemExit("the example did not run")
        for line in proc.stdout.splitlines():
            if line.startswith("# refused "):
                refused.add(line[len("# refused "):])
            elif line[:2] in ("a\t", "p\t"):
                fields = line.split("\t")
                rows[fields[1]] = fields
    return rows, refused


def ask_go(texts, prefixes):
    payload = json.dumps({"addrs": texts, "prefixes": prefixes, "addrports": []})
    proc = subprocess.run(
        ["go", "run", str(ROOT / "scripts" / "reference_netip.go")],
        input=payload, capture_output=True, text=True, cwd=ROOT,
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr)
        raise SystemExit("the Go reference helper failed")
    return json.loads(proc.stdout)


def main():
    inputs = corpus()
    rows, refused = read_rows(inputs)

    missing = [text for text in inputs if text not in rows and text not in refused]
    if missing:
        print("the example answered nothing for %d inputs, first few:" % len(missing))
        for text in missing[:5]:
            print("  " + repr(text))
        return 1

    addr_rows = [row for row in rows.values() if row[0] == "a"]
    prefix_rows = [row for row in rows.values() if row[0] == "p"]

    problems = []
    go = ask_go([row[2] for row in addr_rows], [row[2] for row in prefix_rows])
    go_addrs = dict(zip((row[2] for row in addr_rows), go["addrs"]))
    go_prefixes = dict(zip((row[2] for row in prefix_rows), go["prefixes"]))

    for row in addr_rows:
        given, text, packed = row[1], row[2], row[3]
        try:
            addr = ipaddress.ip_address(text)
        except ValueError as exc:
            problems.append("ipaddress cannot read %r (written from %r): %s" % (text, given, exc))
            continue
        if str(addr) != text:
            problems.append("ipaddress reads %r as %r" % (text, str(addr)))
        if addr.packed.hex() != packed:
            problems.append("ipaddress reads %r as bytes %s, not %s" % (text, addr.packed.hex(), packed))
        said = go_addrs[text]
        if not said["ok"]:
            problems.append("net/netip cannot read %r (written from %r)" % (text, given))
            continue
        if said["text"] != text:
            problems.append("net/netip reads %r as %r" % (text, said["text"]))
        if said["bytes"] != packed:
            problems.append("net/netip reads %r as bytes %s, not %s" % (text, said["bytes"], packed))

    for row in prefix_rows:
        given, text, netmask, hostmask, broadcast = row[1], row[2], row[3], row[4], row[5]
        try:
            net = ipaddress.ip_network(text)
        except ValueError as exc:
            problems.append("ipaddress cannot read %r (written from %r): %s" % (text, given, exc))
            continue
        if str(net) != text:
            problems.append("ipaddress reads %r as %r" % (text, str(net)))
        if str(net.netmask) != netmask:
            problems.append("ipaddress gives %r the netmask %s, not %s" % (text, net.netmask, netmask))
        if str(net.hostmask) != hostmask:
            problems.append("ipaddress gives %r the hostmask %s, not %s" % (text, net.hostmask, hostmask))
        if broadcast != "-" and str(net.broadcast_address) != broadcast:
            problems.append(
                "ipaddress gives %r the last address %s, not %s" % (text, net.broadcast_address, broadcast)
            )
        said = go_prefixes[text]
        if not said["ok"]:
            problems.append("net/netip cannot read %r (written from %r)" % (text, given))
            continue
        if said["masked"] != text:
            problems.append("net/netip reads %r as the block %r" % (text, said["masked"]))
        if said["netmask"] != netmask:
            problems.append("net/netip gives %r the netmask %s, not %s" % (text, said["netmask"], netmask))
        if broadcast != "-" and said["last"] != broadcast:
            problems.append(
                "net/netip gives %r the last address %s, not %s" % (text, said["last"], broadcast)
            )

    print(
        "read back by ipaddress and net/netip: %d addresses, %d blocks, %d inputs refused"
        % (len(addr_rows), len(prefix_rows), len(refused))
    )
    if problems:
        print("%d rows where the written form and a reference disagree:" % len(problems))
        for line in problems[:40]:
            print("  " + line)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
