///|
/// An address and a port: one end of a TCP or UDP conversation.
///
/// ```mbt check
/// test {
///   let end = @moonip.AddrPort::parse("[::1]:443")
///   assert_eq(end.to_string(), "[::1]:443")
///   assert_eq(end.port(), 443)
/// }
/// ```
pub struct AddrPort {
  addr : Addr
  port : Int32
}

///|
fn make_addr_port(addr : Addr, port : Int32) -> AddrPort {
  AddrPort::{ addr, port, }
}

///|
/// An address and a port, the port being 0 to 65535.
pub fn AddrPort::new(addr : Addr, port : Int32) -> AddrPort raise Refused {
  if port < 0 || port > 65535 {
    raise Refused::OutOfRange(limit=65535, got=port)
  }
  make_addr_port(addr, port)
}

///|
/// Read `1.2.3.4:80` or `[::1]:80`.
///
/// The brackets around an IPv6 address are what tells the last colon from the ones
/// in the address, so an IPv6 address without them is refused rather than guessed
/// at.
pub fn AddrPort::parse(text : StringView) -> AddrPort raise Refused {
  let n = text.char_length()
  if n == 0 {
    raise Refused::Malformed(at=0)
  }
  if text.get_char(0).unwrap() == '[' {
    let mut close = -1
    let mut i = 1
    while i < n {
      if text.get_char(i).unwrap() == ']' {
        close = i
        break
      }
      i = i + 1
    }
    if close < 0 {
      raise Refused::Malformed(at=n)
    }
    let addr = Addr::parse(string_between(text, 1, close))
    if addr.is_v4() {
      // Square brackets only ever hold an IPv6 address.
      raise Refused::Malformed(at=close)
    }
    if close + 1 >= n || text.get_char(close + 1).unwrap() != ':' {
      raise Refused::Malformed(at=close + 1)
    }
    return make_addr_port(addr, parse_port(text, close + 2, n))
  }
  let mut colon = -1
  let mut i = 0
  while i < n {
    let c = text.get_char(i).unwrap()
    if c == ':' {
      colon = i
      break
    } else if c == ']' {
      raise Refused::Malformed(at=i)
    }
    i = i + 1
  }
  if colon <= 0 {
    raise Refused::Malformed(at=0)
  }
  let addr = Addr::parse(string_between(text, 0, colon))
  if addr.is_v6() {
    // An IPv6 address has colons of its own and has to be bracketed.
    raise Refused::Malformed(at=colon)
  }
  make_addr_port(addr, parse_port(text, colon + 1, n))
}

///|
/// The decimal port between two positions.
fn parse_port(
  text : StringView,
  start : Int32,
  end : Int32,
) -> Int32 raise Refused {
  if start >= end {
    raise Refused::Malformed(at=start)
  }
  let mut value = 0
  let mut i = start
  while i < end {
    let c = text.get_char(i).unwrap()
    if c < '0' || c > '9' {
      raise Refused::Malformed(at=i)
    }
    value = value * 10 + (c.to_int() - 48)
    if value > 65535 {
      raise Refused::OutOfRange(limit=65535, got=value)
    }
    i = i + 1
  }
  value
}

///|
/// The address half.
pub fn AddrPort::addr(self : AddrPort) -> Addr {
  self.addr
}

///|
/// The port half, 0 to 65535.
pub fn AddrPort::port(self : AddrPort) -> Int32 {
  self.port
}

///|
pub impl Eq for AddrPort with fn equal(self, other) {
  self.port == other.port && self.addr == other.addr
}

///|
pub extend AddrPort with Eq::{equal, not_equal}

///|
pub impl Hash for AddrPort with fn hash_combine(self, hasher) {
  Hash::hash_combine(self.addr, hasher)
  Hash::hash_combine(self.port, hasher)
}

///|
pub extend AddrPort with Hash::{hash, hash_combine}

///|
/// By address, then by port, so a list sorted this way groups one host's ports
/// together.
pub impl Compare for AddrPort with fn compare(self, other) {
  let order = self.addr.compare(other.addr)
  if order != 0 {
    order
  } else {
    self.port.compare(other.port)
  }
}

///|
pub extend AddrPort with Compare::{compare, op_lt, op_gt, op_le, op_ge}

///|
/// The text form, with an IPv6 address in brackets.
pub impl Show for AddrPort with fn to_string(self) {
  if self.addr.v4 {
    self.addr.to_string() + ":" + self.port.to_string()
  } else {
    "[" + self.addr.to_string() + "]:" + self.port.to_string()
  }
}

///|
pub extend AddrPort with Show::{to_string, output}

///|
pub impl Debug for AddrPort with fn to_repr(self) {
  Repr::Repr(self.to_string())
}

///|
pub extend AddrPort with @debug.Debug::{to_repr}
