///|
/// The value of a hexadecimal digit, or -1 when the character is not one.
fn hex_value(c : Char) -> Int32 {
  let code = c.to_int()
  if code >= 48 && code <= 57 {
    code - 48
  } else if code >= 97 && code <= 102 {
    code - 87
  } else if code >= 65 && code <= 70 {
    code - 55
  } else {
    -1
  }
}

///|
/// The characters between two positions, both counted in characters. Views index
/// bytes, so a zone name with any character outside ASCII would otherwise be cut
/// in the wrong place.
fn string_between(text : StringView, start : Int32, end : Int32) -> String {
  let mut out = ""
  let mut i = start
  while i < end {
    out = out + text.get_char(i).unwrap().to_string()
    i = i + 1
  }
  out
}

///|
/// Four dotted decimal fields, ending exactly at `end`.
fn parse_v4_from(
  text : StringView,
  start : Int32,
  end : Int32,
) -> Addr raise Refused {
  let mut i = start
  let mut value = 0UL
  let mut field = 0
  while true {
    let field_start = i
    let mut number = 0
    while i < end {
      let c = text.get_char(i).unwrap()
      if c < '0' || c > '9' {
        break
      }
      if i - field_start == 3 {
        raise Refused::Malformed(at=i)
      }
      number = number * 10 + (c.to_int() - 48)
      i = i + 1
    }
    if i == field_start {
      raise Refused::Malformed(at=i)
    }
    if i - field_start > 1 && text.get_char(field_start).unwrap() == '0' {
      // A leading zero would read as octal to some resolvers, so it is refused
      // outright rather than guessed at.
      raise Refused::Malformed(at=field_start)
    }
    if number > 255 {
      raise Refused::OutOfRange(limit=255, got=number)
    }
    value = (value << 8) | number.to_uint64()
    field = field + 1
    if field == 4 {
      break
    }
    if i >= end || text.get_char(i).unwrap() != '.' {
      raise Refused::Malformed(at=i)
    }
    i = i + 1
  }
  if i != end {
    raise Refused::Malformed(at=i)
  }
  addr_of_u32(value)
}

///|
/// The hex groups of an IPv6 address, with one `::` allowed to stand for the run of
/// zero groups it replaces.
fn parse_v6_body(
  text : StringView,
  end : Int32,
) -> (UInt64, UInt64) raise Refused {
  let groups : Array[Int32] = []
  let mut i = 0
  let mut gap = -1
  if end >= 2 && text.get_char(0).unwrap() == ':' {
    if text.get_char(1).unwrap() != ':' {
      raise Refused::Malformed(at=0)
    }
    gap = 0
    i = 2
    if i >= end {
      return (0UL, 0UL)
    }
  }
  while i < end {
    let group_start = i
    let mut value = 0
    while i < end {
      let digit = hex_value(text.get_char(i).unwrap())
      if digit < 0 {
        break
      }
      if i - group_start == 4 {
        raise Refused::Malformed(at=i)
      }
      value = (value << 4) | digit
      i = i + 1
    }
    if i == group_start {
      raise Refused::Malformed(at=i)
    }
    if i < end && text.get_char(i).unwrap() == '.' {
      // The last two groups may be written as one dotted quad instead.
      if (gap < 0 && groups.length() != 6) || groups.length() > 6 {
        raise Refused::Malformed(at=group_start)
      }
      let quad = parse_v4_from(text, group_start, end)
      groups.push(((quad.lo >> 16) & 0xFFFFUL).to_int())
      groups.push((quad.lo & 0xFFFFUL).to_int())
      i = end
      break
    }
    groups.push(value)
    if i >= end {
      break
    }
    if text.get_char(i).unwrap() != ':' {
      raise Refused::Malformed(at=i)
    }
    i = i + 1
    if i >= end {
      raise Refused::Malformed(at=i - 1)
    }
    if text.get_char(i).unwrap() == ':' {
      if gap >= 0 {
        raise Refused::Malformed(at=i)
      }
      gap = groups.length()
      i = i + 1
      if i >= end {
        break
      }
    }
  }
  let parsed = groups.length()
  if gap < 0 {
    if parsed != 8 {
      raise Refused::Malformed(at=end)
    }
  } else if parsed > 7 {
    // `::` has to stand for at least one group of zeros, or it is not shorter.
    raise Refused::Malformed(at=end)
  }
  let padding = if gap < 0 { 0 } else { 8 - parsed }
  let full : Array[Int32] = []
  let mut k = 0
  while k < 8 {
    if gap >= 0 && k >= gap && k < gap + padding {
      full.push(0)
    } else if gap >= 0 && k >= gap + padding {
      full.push(groups[k - padding])
    } else {
      full.push(groups[k])
    }
    k = k + 1
  }
  let hi = (full[0].to_uint64() << 48) |
    (full[1].to_uint64() << 32) |
    (full[2].to_uint64() << 16) |
    full[3].to_uint64()
  let lo = (full[4].to_uint64() << 48) |
    (full[5].to_uint64() << 32) |
    (full[6].to_uint64() << 16) |
    full[7].to_uint64()
  (hi, lo)
}

///|
fn parse_v6_text(text : StringView, n : Int32) -> Addr raise Refused {
  let mut pct = -1
  let mut i = 0
  while i < n {
    if text.get_char(i).unwrap() == '%' {
      pct = i
      break
    }
    i = i + 1
  }
  let zone = if pct < 0 {
    None
  } else {
    if pct + 1 >= n {
      raise Refused::Malformed(at=pct + 1)
    }
    let mut j = pct + 1
    while j < n {
      if text.get_char(j).unwrap() == '%' {
        raise Refused::Malformed(at=j)
      }
      j = j + 1
    }
    Some(string_between(text, pct + 1, n))
  }
  let body_end = if pct < 0 { n } else { pct }
  let (hi, lo) = parse_v6_body(text, body_end)
  match zone {
    None => Addr::v6(hi, lo)
    Some(name) => Addr::v6(hi, lo).with_zone(Some(name))
  }
}

///|
/// Read an address out of its text form: four dotted decimal fields, or the colon
/// form of RFC 4291 with an optional `%zone`.
pub fn Addr::parse(text : StringView) -> Addr raise Refused {
  let n = text.char_length()
  let mut i = 0
  while i < n {
    let c = text.get_char(i).unwrap()
    if c == '.' {
      return parse_v4_from(text, 0, n)
    } else if c == ':' {
      return parse_v6_text(text, n)
    } else if c == '%' {
      // A zone needs an address to sit on.
      raise Refused::Malformed(at=i)
    }
    i = i + 1
  }
  raise Refused::Malformed(at=0)
}

///|
fn decimal_octets(value : UInt64) -> String {
  let a = (value >> 24) & 0xFFUL
  let b = (value >> 16) & 0xFFUL
  let c = (value >> 8) & 0xFFUL
  let d = value & 0xFFUL
  a.to_int().to_string() +
  "." +
  b.to_int().to_string() +
  "." +
  c.to_int().to_string() +
  "." +
  d.to_int().to_string()
}

///|
/// One 16-bit group in lower-case hexadecimal, without leading zeros.
fn hex_group(value : Int32) -> String {
  let digits = "0123456789abcdef"
  let mut out = ""
  let mut started = false
  let mut shift = 12
  while shift >= 0 {
    let nibble = (value >> shift) & 0xF
    if nibble != 0 || started || shift == 0 {
      started = true
      out = out + digits.get_char(nibble).unwrap().to_string()
    }
    shift = shift - 4
  }
  out
}

///|
/// One 16-bit group as exactly four lower-case hexadecimal digits.
fn hex_group_fixed(value : Int32) -> String {
  let digits = "0123456789abcdef"
  let mut out = ""
  let mut shift = 12
  while shift >= 0 {
    out = out + digits.get_char((value >> shift) & 0xF).unwrap().to_string()
    shift = shift - 4
  }
  out
}

///|
fn groups_of(addr : Addr) -> Array[Int32] {
  [
    ((addr.hi >> 48) & 0xFFFFUL).to_int(),
    ((addr.hi >> 32) & 0xFFFFUL).to_int(),
    ((addr.hi >> 16) & 0xFFFFUL).to_int(),
    (addr.hi & 0xFFFFUL).to_int(),
    ((addr.lo >> 48) & 0xFFFFUL).to_int(),
    ((addr.lo >> 32) & 0xFFFFUL).to_int(),
    ((addr.lo >> 16) & 0xFFFFUL).to_int(),
    (addr.lo & 0xFFFFUL).to_int(),
  ]
}

///|
/// The longest run of two or more zero groups, leftmost when two runs tie, as
/// RFC 5952 section 4.2 asks. Returns (start, length), length 0 for no run.
fn zero_run(groups : Array[Int32], count : Int32) -> (Int32, Int32) {
  let mut best_start = 0
  let mut best = 0
  let mut i = 0
  while i < count {
    if groups[i] == 0 {
      let start = i
      while i < count && groups[i] == 0 {
        i = i + 1
      }
      if i - start > best {
        best = i - start
        best_start = start
      }
    } else {
      i = i + 1
    }
  }
  if best < 2 {
    (0, 0)
  } else {
    (best_start, best)
  }
}

///|
/// The text form of the address, in the canonical shape of RFC 5952: lower-case
/// hexadecimal, no leading zeros in a group, the longest run of zero groups
/// replaced by `::`, and an IPv4-mapped address written with its four dotted
/// decimal fields at the end.
///
/// ```mbt check
/// test {
///   assert_eq(
///     @moonip.Addr::parse("2001:0DB8:0000:0000:0000:0000:0000:0001").to_string(),
///     "2001:db8::1",
///   )
///   assert_eq(
///     @moonip.Addr::parse("::ffff:192.0.2.1").to_string(),
///     "::ffff:192.0.2.1",
///   )
/// }
/// ```
pub impl Show for Addr with fn to_string(self) {
  if self.v4 {
    return decimal_octets(u32_of(self))
  }
  let mapped = self.is_v4_mapped()
  let count = if mapped { 6 } else { 8 }
  let groups = groups_of(self)
  let (run_start, run_length) = zero_run(groups, count)
  let mut out = ""
  let mut i = 0
  while i < count {
    if run_length > 0 && i == run_start {
      out = out + "::"
      i = i + run_length
    } else {
      if i > 0 && !(run_length > 0 && i == run_start + run_length) {
        out = out + ":"
      }
      out = out + hex_group(groups[i])
      i = i + 1
    }
  }
  if mapped {
    out = out + ":" + decimal_octets(self.lo & 0xFFFF_FFFFUL)
  }
  match self.zone {
    None => out
    Some(name) => out + "%" + name
  }
}

///|
pub extend Addr with Show::{to_string, output}

///|
/// Every group written out in full, four hexadecimal digits each, with nothing
/// compressed. Handy for anything that compares text rather than reads it: two
/// addresses are equal exactly when their exploded forms are.
///
/// ```mbt check
/// test {
///   assert_eq(
///     @moonip.Addr::parse("2001:db8::1").exploded(),
///     "2001:0db8:0000:0000:0000:0000:0000:0001",
///   )
/// }
/// ```
pub fn Addr::exploded(self : Addr) -> String {
  if self.v4 {
    return decimal_octets(u32_of(self))
  }
  let groups = groups_of(self)
  let count = if self.is_v4_mapped() { 6 } else { 8 }
  let mut out = ""
  let mut i = 0
  while i < count {
    if i > 0 {
      out = out + ":"
    }
    out = out + hex_group_fixed(groups[i])
    i = i + 1
  }
  if self.is_v4_mapped() {
    out = out + ":" + decimal_octets(self.lo & 0xFFFF_FFFFUL)
  }
  out
}

///|
/// The name this address has in the reverse DNS tree: `4.3.2.1.in-addr.arpa` for
/// IPv4, and the thirty-two nibbles of the address in reverse order under
/// `ip6.arpa` for IPv6 (RFC 3596).
///
/// ```mbt check
/// test {
///   assert_eq(
///     @moonip.Addr::parse("192.0.2.1").reverse_pointer(),
///     "1.2.0.192.in-addr.arpa",
///   )
///   assert_eq(
///     @moonip.Addr::parse("::1").reverse_pointer(),
///     "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.ip6.arpa",
///   )
/// }
/// ```
pub fn Addr::reverse_pointer(self : Addr) -> String {
  let digits = "0123456789abcdef"
  if self.v4 {
    let value = u32_of(self)
    let mut out = ""
    for shift in [0, 8, 16, 24] {
      out = out + ((value >> shift) & 0xFFUL).to_int().to_string() + "."
    }
    out + "in-addr.arpa"
  } else {
    let mut out = ""
    let groups = groups_of(self)
    let mut i = 7
    while i >= 0 {
      let mut shift = 0
      while shift < 16 {
        out = out +
          digits.get_char((groups[i] >> shift) & 0xF).unwrap().to_string() +
          "."
        shift = shift + 4
      }
      i = i - 1
    }
    out + "ip6.arpa"
  }
}
