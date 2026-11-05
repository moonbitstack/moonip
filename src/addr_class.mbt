// Classification follows the two IANA special-purpose address registries, as
// they stood on 2026-10-31:
//   https://www.iana.org/assignments/iana-ipv4-special-registry/
//   https://www.iana.org/assignments/iana-ipv6-special-registry/
// An IPv4-mapped IPv6 address is judged by the IPv4 address inside it, the way a
// stack would route it.

///|
/// Whether the top `bits` of a 32-bit value match the block.
fn v4_within(value : UInt64, block : UInt64, bits : Int32) -> Bool {
  if bits <= 0 {
    true
  } else if bits >= 32 {
    value == block
  } else {
    let shift = 32 - bits
    value >> shift == block >> shift
  }
}

///|
/// Whether the top `bits` of a 128-bit value match the block.
fn v6_within(
  hi : UInt64,
  lo : UInt64,
  bhi : UInt64,
  blo : UInt64,
  bits : Int32,
) -> Bool {
  if bits <= 0 {
    true
  } else if bits <= 64 {
    if bits == 64 {
      hi == bhi
    } else {
      let shift = 64 - bits
      hi >> shift == bhi >> shift
    }
  } else if hi != bhi {
    false
  } else if bits >= 128 {
    lo == blo
  } else {
    let shift = 128 - bits
    lo >> shift == blo >> shift
  }
}

///|
/// Whether the address is in a block the IPv4 registry lists as not globally
/// reachable. Shared address space (100.64.0.0/10) is tracked separately, because
/// it is neither private-use nor reachable.
fn v4_unreachable(value : UInt64) -> Bool {
  let blocks = [
    (0x0000_0000UL, 8), // 0.0.0.0/8      this network
    (0x0A00_0000UL, 8), // 10.0.0.0/8     private-use
    (0x7F00_0000UL, 8), // 127.0.0.0/8    loopback
    (0xA9FE_0000UL, 16), // 169.254.0.0/16 link local
    (0xAC10_0000UL, 12), // 172.16.0.0/12  private-use
    (0xC000_0000UL, 24), // 192.0.0.0/24   IETF protocol assignments
    (0xC000_00AAUL, 31), // 192.0.0.170/31 NAT64 discovery
    (0xC000_0200UL, 24), // 192.0.2.0/24   documentation
    (0xC0A8_0000UL, 16), // 192.168.0.0/16 private-use
    (0xC612_0000UL, 15), // 198.18.0.0/15  benchmarking
    (0xC633_6400UL, 24), // 198.51.100.0/24 documentation
    (0xCB00_7100UL, 24), // 203.0.113.0/24 documentation
    (0xF000_0000UL, 4), // 240.0.0.0/4    reserved
    (0xFFFF_FFFFUL, 32), // 255.255.255.255 limited broadcast
  ]
  let mut inside = false
  for block in blocks {
    if v4_within(value, block.0, block.1) {
      inside = true
    }
  }
  if !inside {
    return false
  }
  // Two anycast addresses inside 192.0.0.0/24 are reachable.
  !(v4_within(value, 0xC000_0009UL, 32) || v4_within(value, 0xC000_000AUL, 32))
}

///|
/// Whether the address is in a block the IPv6 registry lists as not globally
/// reachable.
fn v6_unreachable(hi : UInt64, lo : UInt64) -> Bool {
  let blocks : Array[(UInt64, UInt64, Int32)] = [
    (0x0000_0000_0000_0000UL, 0x0000_0000_0000_0001UL, 128), // ::1/128
    (0x0000_0000_0000_0000UL, 0x0000_0000_0000_0000UL, 128), // ::/128
    (0x0000_0000_0000_0000UL, 0x0000_FFFF_0000_0000UL, 96), // ::ffff:0:0/96
    (0x0064_FF9B_0001_0000UL, 0x0000_0000_0000_0000UL, 48), // 64:ff9b:1::/48
    (0x0100_0000_0000_0000UL, 0x0000_0000_0000_0000UL, 64), // 100::/64
    (0x2001_0000_0000_0000UL, 0x0000_0000_0000_0000UL, 23), // 2001::/23
    (0x2001_0DB8_0000_0000UL, 0x0000_0000_0000_0000UL, 32), // 2001:db8::/32
    (0x2002_0000_0000_0000UL, 0x0000_0000_0000_0000UL, 16), // 2002::/16
    (0x3FFF_0000_0000_0000UL, 0x0000_0000_0000_0000UL, 20), // 3fff::/20
    (0xFC00_0000_0000_0000UL, 0x0000_0000_0000_0000UL, 7), // fc00::/7
    (0xFE80_0000_0000_0000UL, 0x0000_0000_0000_0000UL, 10), // fe80::/10
  ]
  let mut inside = false
  for block in blocks {
    if v6_within(hi, lo, block.0, block.1, block.2) {
      inside = true
    }
  }
  if !inside {
    return false
  }
  // Blocks inside 2001::/23 that are reachable after all.
  let reachable : Array[(UInt64, UInt64, Int32)] = [
    (0x2001_0001_0000_0000UL, 0x0000_0000_0000_0001UL, 128), // 2001:1::1/128 PCP anycast
    (0x2001_0001_0000_0000UL, 0x0000_0000_0000_0002UL, 128), // 2001:1::2/128 TURN anycast
    (0x2001_0003_0000_0000UL, 0x0000_0000_0000_0000UL, 32), // 2001:3::/32 AMT
    (0x2001_0004_0112_0000UL, 0x0000_0000_0000_0000UL, 48), // 2001:4:112::/48 AS112
    (0x2001_0020_0000_0000UL, 0x0000_0000_0000_0000UL, 28), // 2001:20::/28 ORCHIDv2
    (0x2001_0030_0000_0000UL, 0x0000_0000_0000_0000UL, 28), // 2001:30::/28 DRIP
  ]
  let mut exempt = false
  for block in reachable {
    if v6_within(hi, lo, block.0, block.1, block.2) {
      exempt = true
    }
  }
  !exempt
}

///|
/// Whether this address is the same address with any IPv4-mapped prefix removed,
/// which is how the two stacks treat it when the question is where it routes.
fn routed_as(addr : Addr) -> Addr {
  addr.unmap()
}

///|
/// Whether this is the unspecified address, `0.0.0.0` or `::`. An IPv4-mapped
/// address is judged by the IPv4 address inside it, like every other question
/// here.
pub fn Addr::is_unspecified(self : Addr) -> Bool {
  let addr = routed_as(self)
  if addr.v4 {
    u32_of(addr) == 0UL
  } else {
    addr.hi == 0UL && addr.lo == 0UL
  }
}

///|
/// Whether this is a loopback address: `127.0.0.0/8` for IPv4, `::1` for IPv6.
pub fn Addr::is_loopback(self : Addr) -> Bool {
  let addr = routed_as(self)
  if addr.v4 {
    v4_within(u32_of(addr), 0x7F00_0000UL, 8)
  } else {
    addr.hi == 0UL && addr.lo == 1UL
  }
}

///|
/// Whether this is a multicast address: `224.0.0.0/4` for IPv4, `ff00::/8` for
/// IPv6.
pub fn Addr::is_multicast(self : Addr) -> Bool {
  let addr = routed_as(self)
  if addr.v4 {
    v4_within(u32_of(addr), 0xE000_0000UL, 4)
  } else {
    addr.hi >> 56 == 0xFFUL
  }
}

///|
/// Whether this is a link-local address: `169.254.0.0/16` for IPv4 (RFC 3927),
/// `fe80::/10` for IPv6.
pub fn Addr::is_link_local(self : Addr) -> Bool {
  let addr = routed_as(self)
  if addr.v4 {
    v4_within(u32_of(addr), 0xA9FE_0000UL, 16)
  } else {
    v6_within(addr.hi, addr.lo, 0xFE80_0000_0000_0000UL, 0UL, 10)
  }
}

///|
/// Whether this is a deprecated site-local address, `fec0::/10` (RFC 3879). IPv4
/// has no such thing, so it is always false there.
pub fn Addr::is_site_local(self : Addr) -> Bool {
  if self.v4 {
    false
  } else {
    v6_within(self.hi, self.lo, 0xFEC0_0000_0000_0000UL, 0UL, 10)
  }
}

///|
/// Whether this address is reserved for a purpose other than unicast: `240.0.0.0/4`
/// for IPv4, and for IPv6 every block outside `2000::/3` and `fe80::/10`
/// (RFC 4291 section 2.4).
pub fn Addr::is_reserved(self : Addr) -> Bool {
  let addr = routed_as(self)
  if addr.v4 {
    v4_within(u32_of(addr), 0xF000_0000UL, 4)
  } else {
    // RFC 4291 section 2.4 reserves everything outside five blocks: global
    // unicast, unique local, link local, the deprecated site local one, and the
    // multicast space, which has a predicate of its own.
    !v6_within(addr.hi, addr.lo, 0x2000_0000_0000_0000UL, 0UL, 3) &&
    !v6_within(addr.hi, addr.lo, 0xFC00_0000_0000_0000UL, 0UL, 7) &&
    !v6_within(addr.hi, addr.lo, 0xFE80_0000_0000_0000UL, 0UL, 10) &&
    !v6_within(addr.hi, addr.lo, 0xFEC0_0000_0000_0000UL, 0UL, 10) &&
    !v6_within(addr.hi, addr.lo, 0xFF00_0000_0000_0000UL, 0UL, 8)
  }
}

///|
/// Whether the address sits in a block the IANA registries mark as not globally
/// reachable: the private-use ranges, loopback, link local, documentation,
/// benchmarking and the rest, with the IPv6 exceptions the registry itself names.
///
/// ```mbt check
/// test {
///   assert_true(@moonip.Addr::parse("10.1.2.3").is_private())
///   assert_false(@moonip.Addr::parse("8.8.8.8").is_private())
///   assert_true(@moonip.Addr::parse("fd00::1").is_private())
/// }
/// ```
pub fn Addr::is_private(self : Addr) -> Bool {
  let addr = routed_as(self)
  if addr.v4 {
    v4_unreachable(u32_of(addr))
  } else {
    v6_unreachable(addr.hi, addr.lo)
  }
}

///|
/// Whether the address is globally reachable: the opposite of `is_private`, except
/// for shared address space `100.64.0.0/10`, which is neither private nor
/// reachable and so answers false to both.
///
/// ```mbt check
/// test {
///   assert_true(@moonip.Addr::parse("8.8.8.8").is_global())
///   assert_true(@moonip.Addr::parse("2001:4860::1").is_global())
///   assert_false(@moonip.Addr::parse("100.64.0.1").is_global())
///   assert_false(@moonip.Addr::parse("100.64.0.1").is_private())
/// }
/// ```
pub fn Addr::is_global(self : Addr) -> Bool {
  let addr = routed_as(self)
  if addr.v4 {
    !v4_within(u32_of(addr), 0x6440_0000UL, 10) && !v4_unreachable(u32_of(addr))
  } else {
    !v6_unreachable(addr.hi, addr.lo)
  }
}
