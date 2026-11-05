// Cutting one block out of another, and putting a set of blocks back into the
// fewest blocks that say the same thing.

///|
/// The block that holds half of this one, the other half being the sibling.
fn half_block(prefix : Prefix) -> Prefix {
  make_prefix(masked_addr(prefix.net, prefix.plen - 1), prefix.plen - 1)
}

///|
/// The other half of the block's parent.
fn sibling(prefix : Prefix) -> Prefix {
  let shift = prefix.net.bits() - prefix.plen
  let net = if prefix.net.v4 {
    addr_of_u32(u32_of(prefix.net) ^ (1UL << shift))
  } else if shift < 64 {
    make_addr(prefix.net.hi, prefix.net.lo ^ (1UL << shift), false, None)
  } else {
    make_addr(prefix.net.hi ^ (1UL << (shift - 64)), prefix.net.lo, false, None)
  }
  make_prefix(net, prefix.plen)
}

///|
/// Whether two blocks of the same length are the two halves of one block.
fn are_siblings(a : Prefix, b : Prefix) -> Bool {
  a.net.v4 == b.net.v4 &&
  a.plen == b.plen &&
  a.plen > 0 &&
  sibling(a).net == b.net
}

///|
/// The parts of this block that the other one does not cover, largest first.
///
/// The other block only has to share the family; a block that merely touches this
/// one at the edge leaves it whole, one that covers it leaves nothing, and one
/// that sits over part of it leaves the surround. So the answer is always the
/// exact difference, whatever the caller passes.
///
/// ```mbt check
/// test {
///   let parts = @moonip.Prefix::parse("192.0.2.0/28").exclude(
///     @moonip.Prefix::parse("192.0.2.1/32"),
///   )
///   assert_eq(parts.length(), 4)
///   assert_eq(parts[0].to_string(), "192.0.2.8/29")
/// }
/// ```
pub fn Prefix::exclude(
  self : Prefix,
  other : Prefix,
) -> Array[Prefix] raise Refused {
  if self.net.v4 != other.net.v4 {
    raise Refused::Family
  }
  let block = self.masked()
  let cut = other.masked()
  if !block.overlaps(cut) {
    return [block]
  }
  if cut.contains(block.net) && cut.plen <= block.plen {
    return []
  }
  // The cut is strictly inside, so walk up from it and keep every half that stays
  // inside the block; reversing puts the largest first.
  let parts : Array[Prefix] = []
  let mut level = cut
  while level.plen > block.plen {
    let twin = sibling(level)
    if block.contains(twin.net) {
      parts.push(twin)
    }
    level = half_block(level)
  }
  parts.rev_in_place()
  parts
}

///|
/// The fewest blocks that hold exactly the addresses from `first` to `last`.
///
/// ```mbt check
/// test {
///   let blocks = @moonip.summarize(
///     @moonip.Addr::parse("192.0.2.0"),
///     @moonip.Addr::parse("192.0.2.130"),
///   )
///   assert_eq(blocks.length(), 3)
///   assert_eq(blocks[0].to_string(), "192.0.2.0/25")
/// }
/// ```
pub fn summarize(first : Addr, last : Addr) -> Array[Prefix] raise Refused {
  if first.v4 != last.v4 {
    raise Refused::Family
  }
  if first.compare(last) > 0 {
    raise Refused::Reversed
  }
  let limit = first.bits()
  let out : Array[Prefix] = []
  let mut cur = make_addr(first.hi, first.lo, first.v4, None)
  while cur.compare(last) <= 0 {
    // A block may be as large as the smaller of: the run of zero bits above the
    // current address, and what is left of the range.
    let (rest_hi, rest_lo) = sub128(last.hi, last.lo, cur.hi, cur.lo)
    let (size_hi, size_lo, carried) = add128(rest_hi, rest_lo, 0UL, 1UL)
    let room = if carried { limit } else { highest_bit(size_hi, size_lo) }
    let aligned = trailing_zeros(cur.hi, cur.lo)
    let span = if aligned < room { aligned } else { room }
    let bits = limit - span
    out.push(make_prefix(cur, bits))
    if bits == 0 {
      break
    }
    let (step_hi, step_lo) = power_of_two(span)
    let (nhi, nlo, overflowed) = add128(cur.hi, cur.lo, step_hi, step_lo)
    if overflowed {
      break
    }
    cur = make_addr(nhi, nlo, cur.v4, None)
  }
  out
}

///|
/// The fewest blocks that hold exactly the same addresses as the ones given.
///
/// Blocks of different families are collapsed separately and the IPv4 ones come
/// first, so the answer is always exact even though a mix of families has no
/// single ordering.
///
/// ```mbt check
/// test {
///   let halves = [
///     @moonip.Prefix::parse("192.0.2.0/25"),
///     @moonip.Prefix::parse("192.0.2.128/25"),
///   ]
///   let whole = @moonip.collapse(halves)
///   assert_eq(whole.length(), 1)
///   assert_eq(whole[0].to_string(), "192.0.2.0/24")
/// }
/// ```
pub fn collapse(blocks : ArrayView[Prefix]) -> Array[Prefix] {
  let v4 : Array[Prefix] = []
  let v6 : Array[Prefix] = []
  for block in blocks {
    let masked = block.masked()
    if masked.net.v4 {
      v4.push(masked)
    } else {
      v6.push(masked)
    }
  }
  let out = collapse_one_family(v4)
  for block in collapse_one_family(v6) {
    out.push(block)
  }
  out
}

///|
/// Collapse a list that already shares one family.
fn collapse_one_family(blocks : Array[Prefix]) -> Array[Prefix] {
  blocks.sort()
  let out : Array[Prefix] = []
  for block in blocks {
    let mut current = block
    let mut swallowed = false
    while out.length() > 0 {
      let last = out[out.length() - 1]
      if last.plen <= current.plen && last.contains(current.net) {
        swallowed = true
        break
      }
      if are_siblings(last, current) {
        out.pop() |> ignore
        current = half_block(current)
      } else {
        break
      }
    }
    if !swallowed {
      out.push(current)
    }
  }
  out
}

///|
/// `a - b` on two 128-bit numbers, `a` not being smaller than `b`.
fn sub128(
  hi : UInt64,
  lo : UInt64,
  bhi : UInt64,
  blo : UInt64,
) -> (UInt64, UInt64) {
  let borrow = if lo < blo { 1UL } else { 0UL }
  (hi - bhi - borrow, lo - blo)
}

///|
/// The position of the highest set bit, or 0 for zero.
fn highest_bit(hi : UInt64, lo : UInt64) -> Int32 {
  if hi != 0UL {
    64 + bit_index(hi)
  } else {
    bit_index(lo)
  }
}

///|
fn bit_index(word : UInt64) -> Int32 {
  let mut bit = 63
  while bit > 0 && ((word >> bit) & 1UL) == 0UL {
    bit = bit - 1
  }
  bit
}

///|
/// How many of the low bits are zero; 128 for an address that is all zeros.
fn trailing_zeros(hi : UInt64, lo : UInt64) -> Int32 {
  if lo != 0UL {
    count_low_zeros(lo)
  } else if hi != 0UL {
    64 + count_low_zeros(hi)
  } else {
    128
  }
}

///|
fn count_low_zeros(word : UInt64) -> Int32 {
  let mut bit = 0
  while bit < 63 && ((word >> bit) & 1UL) == 0UL {
    bit = bit + 1
  }
  bit
}
