---
name: moonip
description: IPv4 and IPv6 addresses, blocks and their classification for MoonBit. Use when a task needs to read, write, check or do arithmetic on an IP address or a CIDR prefix — parsing text from a config, URL, certificate or log, formatting one back, splitting a block, summarising a range, or deciding whether an address is private, loopback, link-local or globally reachable.
---

# moonip

One package, no dependencies, no I/O. `Addr` is one address, `Prefix` is a block,
`AddrPort` is an address with a port. Every parse and constructor raises
`Refused` rather than returning a flag.

## Install

```bash
moon add moonbitstack/moonip
```

```moonbit
import {
  "moonbitstack/moonip",
}
```

## Read an address, and write it back

`Addr::parse` takes RFC 4291 text and `to_string` gives RFC 5952 canonical text.
Both raise, so wrap them where the input comes from outside.

```moonbit
fn normalise(text : String) -> String {
  try {
    @moonip.Addr::parse(text).to_string()
  } catch {
    _ => "not an address: " + text
  }
}
```

Use `exploded()` when text has to be compared or sorted as text, and `encode()`
when a wire format wants the bytes — four for IPv4, sixteen for IPv6.

## Work out which block an address is in

```moonbit
let block = @moonip.Prefix::parse("10.20.0.0/16")
let inside = block.contains(@moonip.Addr::parse("10.20.3.4"))   // true
let network = block.masked()                                   // 10.20.0.0/16
let first_host = block.hosts().next().unwrap()                 // 10.20.0.1
```

A `Prefix` keeps the address it was written with, so `192.0.2.5/24` is an
interface on that block and `masked()` is the block. `Prefix::parse` refuses host
bits by default; pass `strict=false` to have them cleared instead.

`subnets(bits=...)`, `supernet(bits=...)`, `exclude`, `summarize` and `collapse`
do the arithmetic. `exclude` always answers with the exact difference, even for a
block that does not sit inside, so it never has to be guarded.

## Decide what an address is

Eight predicates, taken from the IANA special-purpose registries:

```moonbit
let addr = @moonip.Addr::parse("100.64.0.1")
addr.is_private()      // false: shared address space is not private-use
addr.is_global()       // false: it is not reachable either
addr.is_multicast()    // false
```

`is_private` means "a registry marks this as not globally reachable", which is
wider than RFC 1918: it covers loopback, link local, documentation and
benchmarking ranges too. An IPv4-mapped IPv6 address is judged by the IPv4
address inside it, the way a stack routes it.

## Things that catch people out

- The two families never mix. `contains`, `overlaps` and `is_subnet_of` answer
  false across families instead of raising, and `192.0.2.1` is not `::192.0.2.1`.
- `hosts()` is lazy. It is exact and cheap for a small block and unbounded for a
  `/0`; take the first few with `next()` instead of collecting.
- IPv4 has a broadcast address and IPv6 does not, so `broadcast()` returns
  `Addr?` and is `None` for IPv6.
- A zone (`fe80::1%eth0`) belongs to the value, so it takes part in equality and
  survives `next()`. It is not part of the encoded bytes.
- `AddrPort` needs brackets around an IPv6 address: `[::1]:80`, never `::1:80`.
