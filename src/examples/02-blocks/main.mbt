///|
/// Blocks: one block split up, a range joined back into blocks, one block cut out
/// of another, and a set of blocks collapsed to the fewest that say the same thing.
///
///     moon run src/examples/02-blocks --target native
#coverage.skip
fn main raise {
  let block = prefix_of("192.0.2.0/24")
  println("split " + block.to_string() + " into /26:")
  for part in block.subnets(bits=26) {
    println("  " + part.to_string())
  }

  println("")
  println("join 192.0.2.0 to 192.0.2.130:")
  for part in @moonip.summarize(addr_of("192.0.2.0"), addr_of("192.0.2.130")) {
    println("  " + part.to_string())
  }

  println("")
  println("cut 192.0.2.64/26 out of " + block.to_string() + ":")
  for part in block.exclude(prefix_of("192.0.2.64/26")) {
    println("  " + part.to_string())
  }

  println("")
  let pieces = [
    prefix_of("10.0.0.0/25"),
    prefix_of("10.0.0.128/25"),
    prefix_of("10.0.1.0/24"),
    prefix_of("10.0.2.0/24"),
  ]
  println("collapse four pieces:")
  for part in @moonip.collapse(pieces[:]) {
    println("  " + part.to_string())
  }

  println("")
  let v6 = prefix_of("2001:db8::/32")
  println(v6.to_string() + " holds " + count_of(v6) + " addresses;")
  println("  its mask     " + v6.netmask().to_string())
  println("  its first    " + v6.hosts().next().unwrap().to_string())
  println(
    "  /48 subnets  " + v6.subnets(bits=48).collect().length().to_string(),
  )
}

///|
fn addr_of(text : String) -> @moonip.Addr raise @moonip.Refused {
  @moonip.Addr::parse(text)
}

///|
fn prefix_of(text : String) -> @moonip.Prefix {
  @moonip.Prefix::parse(text, strict=false) catch {
    _ => abort("bad prefix in the example: " + text)
  }
}

///|
/// How many addresses a block holds, as a power of two: the count itself does not
/// fit in any integer the language has once the block is wider than a /64.
fn count_of(prefix : @moonip.Prefix) -> String {
  "2^" + (prefix.addr().bits() - prefix.bits()).to_string()
}
