# moonip

**IP addresses and networks for MoonBit.** IPv4, IPv6, classless prefixes and the
special-purpose ranges: parsing, formatting, block arithmetic and classification.
No sockets, no I/O, no dependencies.

<p align="center">
  <a href="https://moonbitstack.github.io/moonip/"><b>Home</b></a> ·
  <a href="https://moonbitstack.github.io/moonip/guide.html">Guide</a> ·
  <a href="https://moonbitstack.github.io/moonip/api.html">API reference</a> ·
  <a href="https://moonbitstack.github.io/moonip/explorer.html">Explorer</a> ·
  <a href="https://mooncakes.io/docs/moonbitstack/moonip">mooncakes</a>
</p>

```bash
moon add moonbitstack/moonip
```

```moonbit
fn main raise {
  let block = @moonip.Prefix::parse("192.0.2.0/24")
  println(block.netmask())                                    // 255.255.255.0
  println(block.contains(@moonip.Addr::parse("192.0.2.7")))    // true
  println(block.subnets(bits=26).collect().length())          // 4
}
```

## Three values

| Type | What it is | Made by |
|:--|:--|:--|
| `Addr` | One IPv4 or IPv6 address, plus the zone a scoped IPv6 address may carry | `Addr::parse`, `Addr::decode`, `Addr::v4`, `Addr::v6` |
| `Prefix` | An address and a mask length | `Prefix::parse`, `Prefix::new` |
| `AddrPort` | An address and a port | `AddrPort::parse`, `AddrPort::new` |

All three are immutable values that compare, hash and order, so they can key a
map or sort a list. Everything else in the package is a function over one of them.

## Addresses

`Addr::parse` reads the text forms of RFC 4291; `to_string` writes the canonical
form of RFC 5952.

```moonbit
let a = @moonip.Addr::parse("2001:0DB8:0000:0000:0000:0000:0000:0001")
a.to_string()          // 2001:db8::1
a.exploded()           // 2001:0db8:0000:0000:0000:0000:0000:0001
a.encode().length()    // 16

@moonip.Addr::parse("::ffff:192.0.2.1").unmap().to_string()   // 192.0.2.1
```

`next` and `prev` step through a family and stop at its ends. `reverse_pointer`
gives the name in the reverse DNS tree. `sixtofour` and `teredo` pull the IPv4
addresses back out of the two transition forms.

## Blocks

```moonbit
let block = @moonip.Prefix::parse("192.0.2.0/24")
block.masked()        // 192.0.2.0/24
block.netmask()       // 255.255.255.0
block.hostmask()      // 0.0.0.255
block.broadcast()     // Some(192.0.2.255)   IPv6 has none: None
```

A prefix keeps the address it was written with, so the same value can stand for
an interface on that block. `Prefix::parse` refuses host bits by default and
clears them with `strict=false`; `Prefix::new` keeps whatever it is given, and
`masked()` is how you ask for the block itself.

| Call | Answer |
|:--|:--|
| `contains`, `overlaps`, `is_subnet_of` | whether addresses or blocks meet |
| `hosts` | the addresses an interface can be given, lazily |
| `subnets`, `supernet` | split down, or the block that holds this one |
| `exclude` | the parts of a block outside another one |
| `summarize`, `collapse` | the fewest blocks holding a range or a set |

```moonbit
let parts = @moonip.summarize(
  @moonip.Addr::parse("192.0.2.0"),
  @moonip.Addr::parse("192.0.2.130"),
)
// 192.0.2.0/25 · 192.0.2.128/31 · 192.0.2.130/32
```

## Classification

Eight predicates, each a row of the IANA special-purpose address registries:

`is_unspecified` · `is_loopback` · `is_multicast` · `is_link_local` ·
`is_site_local` · `is_reserved` · `is_private` · `is_global`

`is_private` means "a registry marks this as not globally reachable": the RFC 1918
blocks, unique local addresses, loopback, link local, documentation, benchmarking
and the reserved space. Shared address space, `100.64.0.0/10`, is the one block
that is neither private nor reachable, and it answers false to both. An
IPv4-mapped IPv6 address is judged by the IPv4 address inside it.

## Refusals

Every call that can fail raises `Refused`, and the variant says what kind of
mistake it was:

| Variant | Meaning |
|:--|:--|
| `Malformed(at~)` | the text stopped making sense at character `at`, counted from 0 |
| `OutOfRange(limit~, got~)` | a number did not fit: a mask length or a port |
| `Length(want~, got~)` | a byte string was the wrong size |
| `HostBits` | host bits set below the mask while `strict` forbade it |
| `Family` | IPv4 against IPv6 |
| `Reversed` | a range that ends before it starts |

## Choices

Parsing is strict on purpose. These are refused rather than guessed at:

- a leading zero in an IPv4 field, which some resolvers would read as octal;
- a dotted netmask, `192.0.2.0/255.255.255.0`, in place of a mask length;
- a zone in a prefix, because a block spans links rather than sitting on one;
- a second `%` in a zone, or a zone on an IPv4 address;
- an unbracketed IPv6 address where a port is expected.

## Documents

- [Home](https://moonbitstack.github.io/moonip/)
- [Guide](https://moonbitstack.github.io/moonip/guide.html) — ten steps, each with the output it gives
- [API reference](https://moonbitstack.github.io/moonip/api.html) — generated from the doc comments
- [Explorer](https://moonbitstack.github.io/moonip/explorer.html) — the library compiled to JavaScript, running in the page
- [Skill](docs/skills/moonip/SKILL.md) — for an agent that has to use the package

Apache-2.0.
