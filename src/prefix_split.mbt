// Splitting a block up, and walking the addresses in it.

///|
/// `2^exponent` as the pair of words an address is kept in.
fn power_of_two(exponent : Int32) -> (UInt64, UInt64) {
  if exponent >= 64 {
    (1UL << (exponent - 64), 0UL)
  } else {
    (0UL, 1UL << exponent)
  }
}

///|
/// The sum of two 128-bit numbers, and whether it carried past the top.
fn add128(
  hi : UInt64,
  lo : UInt64,
  shi : UInt64,
  slo : UInt64,
) -> (UInt64, UInt64, Bool) {
  let low = lo + slo
  let carry = if low < lo { 1UL } else { 0UL }
  let high_sum = hi + shi
  let carried = high_sum < hi
  let high = high_sum + carry
  (high, low, carried || high < high_sum)
}

///|
/// The addresses that can be given to an interface in the block.
///
/// For IPv4 that is every address except the network and broadcast ones, with a
/// `/31` (RFC 3021) and a `/32` kept whole because both ends are usable there. For
/// IPv6 it is every address except the subnet-router anycast address at the
/// bottom, with a `/127` and a `/128` kept whole.
///
/// The iterator is lazy; a `/0` has a great many addresses and no one wants them
/// in an array.
///
/// ```mbt check
/// test {
///   let usable = @moonip.Prefix::parse("192.0.2.0/30").hosts().collect()
///   assert_eq(usable.length(), 2)
///   assert_eq(usable[0].to_string(), "192.0.2.1")
/// }
/// ```
pub fn Prefix::hosts(self : Prefix) -> Iter[Addr] {
  let block = self.masked()
  let limit = block.net.bits()
  if self.plen >= limit {
    return Iter::singleton(block.net)
  }
  if self.plen == limit - 1 {
    let ends = [block.net, last_addr(block)]
    let mut i = 0
    return Iter::new(fn() {
      if i < 2 {
        i = i + 1
        Some(ends[i - 1])
      } else {
        None
      }
    })
  }
  let stop = if block.net.v4 {
    last_addr(block).prev().unwrap()
  } else {
    last_addr(block)
  }
  let mut cur = block.net.next()
  Iter::new(fn() {
    match cur {
      None => None
      Some(addr) => {
        cur = if addr.compare(stop) >= 0 { None } else { addr.next() }
        Some(addr)
      }
    }
  })
}

///|
/// The blocks of length `bits` that together make up this one, in ascending order.
///
/// ```mbt check
/// test {
///   let halves = @moonip.Prefix::parse("10.0.0.0/8").subnets(bits=9).collect()
///   assert_eq(halves.length(), 2)
///   assert_eq(halves[1].to_string(), "10.128.0.0/9")
/// }
/// ```
pub fn Prefix::subnets(
  self : Prefix,
  bits~ : Int32,
) -> Iter[Prefix] raise Refused {
  let block = self.masked()
  let limit = block.net.bits()
  if bits < self.plen {
    raise Refused::OutOfRange(limit=self.plen, got=bits)
  }
  if bits > limit {
    raise Refused::OutOfRange(limit~, got=bits)
  }
  if bits == self.plen {
    return Iter::singleton(block)
  }
  let (step_hi, step_lo) = power_of_two(limit - bits)
  let stop = last_addr(block)
  let mut cur = Some(block.net)
  Iter::new(fn() {
    match cur {
      None => None
      Some(start) => {
        let (nhi, nlo, carried) = add128(start.hi, start.lo, step_hi, step_lo)
        let next = make_addr(nhi, nlo, start.v4, None)
        cur = if carried || next.compare(stop) > 0 { None } else { Some(next) }
        Some(make_prefix(start, bits))
      }
    }
  })
}

///|
/// The block of length `bits` that contains this one.
///
/// ```mbt check
/// test {
///   assert_eq(
///     @moonip.Prefix::parse("192.0.2.0/24").supernet(bits=16).to_string(),
///     "192.0.0.0/16",
///   )
/// }
/// ```
pub fn Prefix::supernet(self : Prefix, bits~ : Int32) -> Prefix raise Refused {
  if bits < 0 || bits > self.plen {
    raise Refused::OutOfRange(limit=self.plen, got=bits)
  }
  make_prefix(masked_addr(self.net, bits), bits)
}
