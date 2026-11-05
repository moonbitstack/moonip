///|
/// An IPv4 or IPv6 address, and the zone an IPv6 scoped address may carry.
///
/// The value never changes once made, compares by its bits, and can be a key in a
/// map. IPv4 keeps its 32 bits in the low word with `v4` set, so `1.2.3.4` and
/// `::1.2.3.4` are two different addresses that never compare equal.
pub struct Addr {
  hi : UInt64
  lo : UInt64
  v4 : Bool
  zone : String?
}

///|
fn make_addr(hi : UInt64, lo : UInt64, v4 : Bool, zone : String?) -> Addr {
  Addr::{ hi, lo, v4, zone, }
}

///|
/// An IPv4 address from its 32 bits held in the low word.
fn addr_of_u32(value : UInt64) -> Addr {
  make_addr(0UL, value & 0xFFFF_FFFFUL, true, None)
}

///|
/// The 32 bits of an IPv4 address.
fn u32_of(addr : Addr) -> UInt64 {
  addr.lo & 0xFFFF_FFFFUL
}

///|
/// 0.0.0.0, the address that means "this host, no address yet".
pub let unspecified4 : Addr = addr_of_u32(0UL)

///|
/// ::, the same idea in IPv6.
pub let unspecified6 : Addr = Addr::v6(0UL, 0UL)

///|
/// 127.0.0.1, the near end of the loopback range.
pub let loopback4 : Addr = addr_of_u32(0x7F00_0001UL)

///|
/// ::1, the only loopback address IPv6 has.
pub let loopback6 : Addr = Addr::v6(0UL, 1UL)

///|
/// An IPv4 address from its four octets.
pub fn Addr::v4(a : Byte, b : Byte, c : Byte, d : Byte) -> Addr {
  let value = (a.to_uint64() << 24) |
    (b.to_uint64() << 16) |
    (c.to_uint64() << 8) |
    d.to_uint64()
  addr_of_u32(value)
}

///|
/// An IPv6 address from its two halves: `hi` the top 64 bits, `lo` the bottom 64.
pub fn Addr::v6(hi : UInt64, lo : UInt64) -> Addr {
  make_addr(hi, lo, false, None)
}

///|
/// Whether this is an IPv4 address.
pub fn Addr::is_v4(self : Addr) -> Bool {
  self.v4
}

///|
/// Whether this is an IPv6 address. An IPv4-mapped address such as
/// `::ffff:192.0.2.1` is IPv6 here; `unmap` is how it becomes IPv4.
pub fn Addr::is_v6(self : Addr) -> Bool {
  !self.v4
}

///|
/// The zone (RFC 4007), when the address came with one.
pub fn Addr::zone(self : Addr) -> String? {
  self.zone
}

///|
/// The same address on another zone. A zone only means something to a scoped IPv6
/// address, so on IPv4 this returns the address unchanged.
pub fn Addr::with_zone(self : Addr, zone : String?) -> Addr {
  if self.v4 {
    self
  } else {
    make_addr(self.hi, self.lo, false, zone)
  }
}

///|
/// The next address, or `None` at the top of the family.
pub fn Addr::next(self : Addr) -> Addr? {
  if self.v4 {
    if self.lo == 0xFFFF_FFFFUL {
      None
    } else {
      Some(make_addr(0UL, self.lo + 1UL, true, self.zone))
    }
  } else if self.lo == 0xFFFF_FFFF_FFFF_FFFFUL {
    if self.hi == 0xFFFF_FFFF_FFFF_FFFFUL {
      None
    } else {
      Some(make_addr(self.hi + 1UL, 0UL, false, self.zone))
    }
  } else {
    Some(make_addr(self.hi, self.lo + 1UL, false, self.zone))
  }
}

///|
/// The address before this one, or `None` at the bottom of the family.
pub fn Addr::prev(self : Addr) -> Addr? {
  if self.v4 {
    if self.lo == 0UL {
      None
    } else {
      Some(make_addr(0UL, self.lo - 1UL, true, self.zone))
    }
  } else if self.lo == 0UL {
    if self.hi == 0UL {
      None
    } else {
      Some(make_addr(self.hi - 1UL, 0xFFFF_FFFF_FFFF_FFFFUL, false, self.zone))
    }
  } else {
    Some(make_addr(self.hi, self.lo - 1UL, false, self.zone))
  }
}

///|
/// Whether this is an IPv4-mapped IPv6 address, that is, one in `::ffff:0:0/96`.
pub fn Addr::is_v4_mapped(self : Addr) -> Bool {
  !self.v4 && self.hi == 0UL && self.lo >> 32 == 0xFFFFUL
}

///|
/// The IPv4 address inside an IPv4-mapped IPv6 one; anything else comes back
/// unchanged. The zone goes with the IPv6 form and is dropped.
pub fn Addr::unmap(self : Addr) -> Addr {
  if self.is_v4_mapped() {
    addr_of_u32(self.lo)
  } else {
    self
  }
}

///|
/// The IPv4-mapped IPv6 form of an IPv4 address; a real IPv6 address comes back
/// unchanged.
pub fn Addr::mapped(self : Addr) -> Addr {
  if self.v4 {
    make_addr(0UL, 0xFFFF_0000_0000UL | self.lo, false, None)
  } else {
    self
  }
}

///|
/// The IPv4 address carried by a 6to4 address, `2002::/16` (RFC 3056).
pub fn Addr::sixtofour(self : Addr) -> Addr? {
  if self.v4 || self.hi >> 48 != 0x2002UL {
    None
  } else {
    Some(addr_of_u32((self.hi >> 16) & 0xFFFF_FFFFUL))
  }
}

///|
/// The server and client addresses carried by a Teredo address, `2001::/32`
/// (RFC 4380). The client is stored inverted (RFC 5991), so the last 32 bits are
/// read as a complement.
pub fn Addr::teredo(self : Addr) -> (Addr, Addr)? {
  if self.v4 || self.hi >> 32 != 0x2001_0000UL {
    None
  } else {
    let server = addr_of_u32(self.hi & 0xFFFF_FFFFUL)
    let client = addr_of_u32(UInt64::lnot(self.lo) & 0xFFFF_FFFFUL)
    Some((server, client))
  }
}

///|
/// The four or sixteen bytes of the address, big-endian, the way a packet or a
/// certificate option carries them. A zone is not part of the address and is not
/// written.
pub fn Addr::encode(self : Addr) -> Bytes {
  if self.v4 {
    let out = Array::makei(4, fn(i) {
      ((self.lo >> (24 - i * 8)) & 0xFFUL).to_byte()
    })
    Bytes::from_array(out[:])
  } else {
    let out = Array::makei(16, fn(i) {
      if i < 8 {
        ((self.hi >> (56 - i * 8)) & 0xFFUL).to_byte()
      } else {
        ((self.lo >> (56 - (i - 8) * 8)) & 0xFFUL).to_byte()
      }
    })
    Bytes::from_array(out[:])
  }
}

///|
/// Read the address back from four (IPv4) or sixteen (IPv6) bytes.
pub fn Addr::decode(bytes : BytesView) -> Addr raise Refused {
  match bytes.length() {
    4 => {
      let mut lo = 0UL
      for i = 0; i < 4; i = i + 1 {
        lo = (lo << 8) | bytes.at(i).to_uint64()
      }
      addr_of_u32(lo)
    }
    16 => {
      let mut hi = 0UL
      let mut lo = 0UL
      for i = 0; i < 8; i = i + 1 {
        hi = (hi << 8) | bytes.at(i).to_uint64()
      }
      for i = 0; i < 8; i = i + 1 {
        lo = (lo << 8) | bytes.at(8 + i).to_uint64()
      }
      make_addr(hi, lo, false, None)
    }
    n => raise Refused::Length(want=16, got=n)
  }
}

///|
/// How many bits the address has: 32 for IPv4, 128 for IPv6.
pub fn Addr::bits(self : Addr) -> Int32 {
  if self.v4 {
    32
  } else {
    128
  }
}

///|
pub impl Eq for Addr with fn equal(self, other) {
  self.v4 == other.v4 &&
  self.hi == other.hi &&
  self.lo == other.lo &&
  self.zone == other.zone
}

///|
pub extend Addr with Eq::{equal, not_equal}

///|
pub impl Hash for Addr with fn hash_combine(self, hasher) {
  Hash::hash_combine(self.v4, hasher)
  Hash::hash_combine(self.hi, hasher)
  Hash::hash_combine(self.lo, hasher)
  Hash::hash_combine(self.zone, hasher)
}

///|
pub extend Addr with Hash::{hash, hash_combine}

///|
/// The order is IPv4 before IPv6, then the address as an unsigned number, then the
/// zone. Sorting addresses by it gives the same order as sorting their encoded
/// bytes, with the two families kept apart instead of interleaved.
pub impl Compare for Addr with fn compare(self, other) {
  if self.v4 != other.v4 {
    if self.v4 {
      -1
    } else {
      1
    }
  } else if self.hi != other.hi {
    if self.hi < other.hi {
      -1
    } else {
      1
    }
  } else if self.lo != other.lo {
    if self.lo < other.lo {
      -1
    } else {
      1
    }
  } else {
    match (self.zone, other.zone) {
      (None, None) => 0
      (None, Some(_)) => -1
      (Some(_), None) => 1
      (Some(a), Some(b)) => a.compare(b)
    }
  }
}

///|
pub extend Addr with Compare::{compare, op_lt, op_gt, op_le, op_ge}

///|
pub impl Debug for Addr with fn to_repr(self) {
  Repr::Repr(self.to_string())
}

///|
pub extend Addr with @debug.Debug::{to_repr}
