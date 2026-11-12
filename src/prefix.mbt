///|
/// A network: an address and the number of leading bits that all addresses in it
/// share, written `192.0.2.0/24`.
///
/// The address is kept as it was given, so `192.0.2.5/24` stands for "this host on
/// that link" the way an interface does; every question about the block itself
/// works on `masked`, which is the same prefix with the host bits cleared.
pub struct Prefix {
  net : Addr
  plen : Int32
}

///|
fn make_prefix(net : Addr, plen : Int32) -> Prefix {
  Prefix::{ net, plen, }
}

///|
/// The top `count` bits of a 64-bit word.
fn top_bits(count : Int32) -> UInt64 {
  if count <= 0 {
    0UL
  } else if count >= 64 {
    0xFFFF_FFFF_FFFF_FFFFUL
  } else {
    0xFFFF_FFFF_FFFF_FFFFUL << (64 - count)
  }
}

///|
/// The mask of an IPv4 address as a 32-bit value.
fn v4_mask(bits : Int32) -> UInt64 {
  top_bits(bits) >> 32
}

///|
/// The top `bits` of an address, as the two words it is kept in.
fn mask_words(addr : Addr, bits : Int32) -> (UInt64, UInt64) {
  if addr.v4 {
    (0UL, u32_of(addr) & v4_mask(bits))
  } else if bits <= 64 {
    (addr.hi & top_bits(bits), 0UL)
  } else {
    (addr.hi, addr.lo & top_bits(bits - 64))
  }
}

///|
/// The same address with every bit below the prefix mask cleared.
fn masked_addr(addr : Addr, bits : Int32) -> Addr {
  let (hi, lo) = mask_words(addr, bits)
  make_addr(hi, lo, addr.v4, None)
}

///|
/// A prefix from an address and a length. The address is kept whole; use `masked`
/// to turn it into the network it names.
pub fn Prefix::new(addr : Addr, bits : Int32) -> Prefix raise Refused {
  let limit = addr.bits()
  if bits < 0 || bits > limit {
    raise Refused::OutOfRange(limit~, got=bits)
  }
  // A zone says which link an address is on, not which block, so it is dropped.
  make_prefix(make_addr(addr.hi, addr.lo, addr.v4, None), bits)
}

///|
/// Read a prefix from `address/length`.
///
/// With `strict` on, bits set below the mask are refused; with it off they are
/// cleared, which is how a block is usually written by hand.
///
/// ```mbt check
/// test {
///   let subnet = @moonip.Prefix::parse("192.0.2.0/24")
///   assert_eq(subnet.to_string(), "192.0.2.0/24")
///   assert_eq(
///     @moonip.Prefix::parse("192.0.2.5/24", strict=false).to_string(),
///     "192.0.2.0/24",
///   )
/// }
/// ```
pub fn Prefix::parse(
  text : StringView,
  strict~ : Bool = true,
) -> Prefix raise Refused {
  let n = text.char_length()
  let mut slash = -1
  let mut i = 0
  while i < n {
    let c = text.get_char(i).unwrap()
    if c == '/' {
      if slash >= 0 {
        raise Refused::Malformed(at=i)
      }
      slash = i
    } else if c == '%' {
      raise Refused::Malformed(at=i)
    }
    i = i + 1
  }
  if slash < 0 {
    raise Refused::Malformed(at=n)
  }
  if slash == 0 {
    raise Refused::Malformed(at=0)
  }
  let addr = Addr::parse(string_between(text, 0, slash))
  let limit = addr.bits()
  let start = slash + 1
  if start >= n {
    raise Refused::Malformed(at=start)
  }
  if n - start > 1 && text.get_char(start).unwrap() == '0' {
    raise Refused::Malformed(at=start)
  }
  let mut bits = 0
  let mut j = start
  while j < n {
    let c = text.get_char(j).unwrap()
    if c < '0' || c > '9' {
      raise Refused::Malformed(at=j)
    }
    bits = bits * 10 + (c.to_int() - 48)
    if bits > limit {
      raise Refused::OutOfRange(limit~, got=bits)
    }
    j = j + 1
  }
  let prefix = make_prefix(addr, bits)
  let masked = prefix.masked()
  if strict && masked.net != prefix.net {
    raise Refused::HostBits
  }
  masked
}

///|
/// The address as written, host bits and all.
pub fn Prefix::addr(self : Prefix) -> Addr {
  self.net
}

///|
/// The length of the mask in bits: 0 to 32 for IPv4, 0 to 128 for IPv6.
pub fn Prefix::bits(self : Prefix) -> Int32 {
  self.plen
}

///|
/// The block itself: the address with every bit below the mask cleared.
pub fn Prefix::masked(self : Prefix) -> Prefix {
  make_prefix(masked_addr(self.net, self.plen), self.plen)
}

///|
/// The mask as an address, `255.255.255.0` or `ffff:ffff:ffff:ffff::`.
pub fn Prefix::netmask(self : Prefix) -> Addr {
  if self.net.v4 {
    addr_of_u32(v4_mask(self.plen))
  } else if self.plen <= 64 {
    make_addr(top_bits(self.plen), 0UL, false, None)
  } else {
    make_addr(0xFFFF_FFFF_FFFF_FFFFUL, top_bits(self.plen - 64), false, None)
  }
}

///|
/// The complement of the mask, `0.0.0.255` or `::ffff:ffff:ffff:ffff`.
pub fn Prefix::hostmask(self : Prefix) -> Addr {
  let mask = self.netmask()
  if self.net.v4 {
    addr_of_u32(UInt64::lnot(u32_of(mask)) & 0xFFFF_FFFFUL)
  } else {
    make_addr(UInt64::lnot(mask.hi), UInt64::lnot(mask.lo), false, None)
  }
}

///|
/// The last address of the block, or `None` for IPv6, which has no broadcast
/// address: the top of an IPv6 block is an ordinary unicast address.
pub fn Prefix::broadcast(self : Prefix) -> Addr? {
  if self.net.v4 {
    let block = self.masked()
    Some(
      addr_of_u32(
        u32_of(block.net) | (UInt64::lnot(v4_mask(self.plen)) & 0xFFFF_FFFFUL),
      ),
    )
  } else {
    None
  }
}

///|
/// Whether the address falls inside the block. An IPv4-mapped IPv6 address is
/// matched against IPv6 blocks only; `unmap` first if you mean the IPv4 one.
pub fn Prefix::contains(self : Prefix, addr : Addr) -> Bool {
  if self.net.v4 != addr.v4 {
    return false
  }
  let here = masked_addr(self.net, self.plen)
  let there = masked_addr(addr, self.plen)
  here.hi == there.hi && here.lo == there.lo
}

///|
/// Whether two blocks share at least one address. Blocks of different families
/// never do.
pub fn Prefix::overlaps(self : Prefix, other : Prefix) -> Bool {
  if self.net.v4 != other.net.v4 {
    return false
  }
  let a = self.masked()
  let b = other.masked()
  let a_end = last_addr(a)
  let b_end = last_addr(b)
  a.net.compare(b_end) <= 0 && b.net.compare(a_end) <= 0
}

///|
/// The last address in the block, broadcast or not.
fn last_addr(prefix : Prefix) -> Addr {
  if prefix.net.v4 {
    addr_of_u32(
      u32_of(prefix.net) | (UInt64::lnot(v4_mask(prefix.plen)) & 0xFFFF_FFFFUL),
    )
  } else {
    let mask = prefix.netmask()
    make_addr(
      prefix.net.hi | UInt64::lnot(mask.hi),
      prefix.net.lo | UInt64::lnot(mask.lo),
      false,
      None,
    )
  }
}

///|
/// Whether this block sits inside the other one, equal blocks included.
pub fn Prefix::is_subnet_of(self : Prefix, other : Prefix) -> Bool {
  if self.net.v4 != other.net.v4 {
    return false
  }
  self.plen >= other.plen && other.contains(self.net)
}

///|
/// Whether this block holds the other one, equal blocks included. The same test as
/// `is_subnet_of` with the two sides the other way round, for callers who read
/// better that way.
///
/// ```mbt check
/// test {
///   let wide = @moonip.Prefix::parse("10.0.0.0/8")
///   assert_true(wide.is_supernet_of(@moonip.Prefix::parse("10.1.0.0/16")))
///   assert_false(wide.is_supernet_of(@moonip.Prefix::parse("11.0.0.0/8")))
/// }
/// ```
pub fn Prefix::is_supernet_of(self : Prefix, other : Prefix) -> Bool {
  other.is_subnet_of(self)
}

///|
/// Whether the block is a single address, that is, a `/32` or a `/128`.
pub fn Prefix::is_single_ip(self : Prefix) -> Bool {
  self.plen == self.net.bits()
}

///|
/// How many addresses the block holds, or `None` when that is more than a `UInt64`
/// can count: an IPv6 block shorter than `/64`. An IPv4 block always answers,
/// `0.0.0.0/0` with 4294967296.
///
/// ```mbt check
/// test {
///   assert_eq(@moonip.Prefix::parse("192.0.2.0/24").num_addresses(), Some(256UL))
///   assert_eq(@moonip.Prefix::parse("2001:db8::/32").num_addresses(), None)
/// }
/// ```
pub fn Prefix::num_addresses(self : Prefix) -> UInt64? {
  let space = self.net.bits() - self.plen
  if space >= 64 {
    None
  } else {
    Some(1UL << space)
  }
}

///|
pub impl Eq for Prefix with fn equal(self, other) {
  self.plen == other.plen && self.net == other.net
}

///|
pub extend Prefix with Eq::{equal, not_equal}

///|
pub impl Hash for Prefix with fn hash_combine(self, hasher) {
  Hash::hash_combine(self.net, hasher)
  Hash::hash_combine(self.plen, hasher)
}

///|
pub extend Prefix with Hash::{hash, hash_combine}

///|
/// IPv4 before IPv6, then the block's first address, then the mask from long to
/// short. That ordering puts a block before everything inside it, which is what
/// `collapse` needs.
pub impl Compare for Prefix with fn compare(self, other) {
  let order = self.net.compare(other.net)
  if order != 0 {
    order
  } else {
    self.plen.compare(other.plen)
  }
}

///|
pub extend Prefix with Compare::{compare, op_lt, op_gt, op_le, op_ge}

///|
/// The text form, `address/length`, with the address as it was given.
pub impl Show for Prefix with fn to_string(self) {
  self.net.to_string() + "/" + self.plen.to_string()
}

///|
pub extend Prefix with Show::{to_string, output}

///|
pub impl Debug for Prefix with fn to_repr(self) {
  Repr::Repr(self.to_string())
}

///|
pub extend Prefix with @debug.Debug::{to_repr}
