// Block arithmetic: cutting one block out of another, summarising a range,
// collapsing a set, splitting and joining. Checked against vectors generated from
// CPython's ipaddress, which is the only one of the two references that has these.

///|
fn join_blocks(blocks : ArrayView[Prefix]) -> String {
  let mut out = ""
  let mut first = true
  for block in blocks {
    if !first {
      out = out + "|"
    }
    first = false
    out = out + block.to_string()
  }
  out
}

///|
fn split_blocks(text : String) -> Array[Prefix] {
  let out : Array[Prefix] = []
  for piece in text.split("|") {
    out.push(parse_or_none(piece.to_owned()).unwrap())
  }
  out
}

///|
fn parse_or_none(text : String) -> Prefix? {
  Some(Prefix::parse(text, strict=false)) catch {
    _ => None
  }
}

///|
test "exclude: every case agrees with ipaddress" {
  for row in exclude_cases() {
    let (self_text, other_text, expected) = row
    let parts = Prefix::parse(self_text, strict=false).exclude(
      Prefix::parse(other_text, strict=false),
    )
    assert_eq(
      join_blocks(parts),
      expected,
      msg=self_text + " without " + other_text,
    )
  }
}

///|
test "exclude: an answer even when the blocks do not nest" {
  let block = Prefix::parse("192.0.2.0/24")
  // A block that merely touches the edge removes nothing.
  assert_eq(
    join_blocks(block.exclude(Prefix::parse("192.0.3.0/24"))),
    "192.0.2.0/24",
  )
  // A block that covers this one leaves nothing.
  assert_eq(block.exclude(Prefix::parse("0.0.0.0/0")).length(), 0)
  // A partial overlap leaves the surround, not an error.
  assert_eq(
    join_blocks(block.exclude(Prefix::parse("192.0.2.64/26"))),
    "192.0.2.128/25|192.0.2.0/26",
  )
  // Families are the one thing that cannot be answered.
  try {
    let _ = block.exclude(Prefix::parse("2001:db8::/32"))
    assert_true(false, msg="a family mix was accepted")
  } catch {
    Refused::Family => ()
    _ => assert_true(false, msg="wrong refusal for a family mix")
  }
}

///|
test "summarize: every case agrees with ipaddress" {
  for row in summarize_cases() {
    let (first, last, expected) = row
    let blocks = summarize(Addr::parse(first), Addr::parse(last))
    assert_eq(join_blocks(blocks), expected, msg=first + " to " + last)
  }
}

///|
test "summarize: a range that runs backwards is refused" {
  try {
    let _ = summarize(Addr::parse("192.0.2.10"), Addr::parse("192.0.2.1"))
    assert_true(false, msg="a reversed range was accepted")
  } catch {
    Refused::Reversed => ()
    _ => assert_true(false, msg="wrong refusal for a reversed range")
  }
  try {
    let _ = summarize(Addr::parse("192.0.2.1"), Addr::parse("2001:db8::1"))
    assert_true(false, msg="a family mix was accepted")
  } catch {
    Refused::Family => ()
    _ => assert_true(false, msg="wrong refusal for a family mix")
  }
  // One address is one block.
  assert_eq(
    join_blocks(summarize(Addr::parse("192.0.2.1"), Addr::parse("192.0.2.1"))),
    "192.0.2.1/32",
  )
}

///|
test "collapse: every case agrees with ipaddress" {
  for row in collapse_cases() {
    let (input, expected) = row
    assert_eq(
      join_blocks(collapse(split_blocks(input)[:])),
      expected,
      msg=input,
    )
  }
}

///|
test "collapse: duplicates, containment and mixed families" {
  let blocks = [
    Prefix::parse("10.0.0.0/8"),
    Prefix::parse("10.0.0.0/8"),
    Prefix::parse("10.1.0.0/16"),
  ]
  assert_eq(join_blocks(collapse(blocks[:])), "10.0.0.0/8")
  // A prefix written with host bits still stands for its block.
  let sloppy = [Prefix::parse("10.9.9.9/8", strict=false)]
  assert_eq(join_blocks(collapse(sloppy[:])), "10.0.0.0/8")
  // Both families are handled, IPv4 first, because no single order holds both.
  let mixed = [
    Prefix::parse("2001:db8::/33"),
    Prefix::parse("10.0.0.0/9"),
    Prefix::parse("2001:db8:8000::/33"),
    Prefix::parse("10.128.0.0/9"),
  ]
  assert_eq(join_blocks(collapse(mixed[:])), "10.0.0.0/8|2001:db8::/32")
  let empty : Array[Prefix] = []
  assert_eq(collapse(empty[:]).length(), 0)
}

///|
test "subnets and supernet: every case agrees with ipaddress" {
  for row in subnets_cases() {
    let (text, bits, expected) = row
    let parts = Prefix::parse(text, strict=false).subnets(bits~).collect()
    assert_eq(
      join_blocks(parts),
      expected,
      msg=text + " into /" + bits.to_string(),
    )
  }
  for row in supernet_cases() {
    let (text, bits, expected) = row
    assert_eq(
      Prefix::parse(text, strict=false).supernet(bits~).to_string(),
      expected,
      msg=text + " up to /" + bits.to_string(),
    )
  }
}

///|
test "subnets and supernet: the window of lengths" {
  let block = Prefix::parse("192.0.2.0/24")
  assert_eq(block.subnets(bits=24).collect().length(), 1)
  try {
    let _ = block.subnets(bits=23)
    assert_true(false, msg="a wider split was accepted")
  } catch {
    Refused::OutOfRange(limit~, got~) => {
      assert_eq(limit, 24)
      assert_eq(got, 23)
    }
    _ => assert_true(false, msg="wrong refusal for a wider split")
  }
  try {
    let _ = block.subnets(bits=33)
    assert_true(false, msg="a /33 split was accepted")
  } catch {
    Refused::OutOfRange(limit~, got~) => {
      assert_eq(limit, 32)
      assert_eq(got, 33)
    }
    _ => assert_true(false, msg="wrong refusal for a /33 split")
  }
  try {
    let _ = block.supernet(bits=25)
    assert_true(false, msg="a narrower supernet was accepted")
  } catch {
    Refused::OutOfRange(limit~, got~) => {
      assert_eq(limit, 24)
      assert_eq(got, 25)
    }
    _ => assert_true(false, msg="wrong refusal for a narrower supernet")
  }
  assert_eq(block.supernet(bits=0).to_string(), "0.0.0.0/0")
}

///|
test "subnets: a whole /0 splits without wrapping round" {
  let all = Prefix::parse("0.0.0.0/0")
  assert_eq(all.subnets(bits=1).collect().length(), 2)
  let ipv6 = Prefix::parse("::/0")
  assert_eq(
    join_blocks(ipv6.subnets(bits=2).collect()),
    "::/2|4000::/2|8000::/2|c000::/2",
  )
  assert_eq(ipv6.subnets(bits=128).next().unwrap().to_string(), "::/128")
}

///|
test "hosts: the ends of a block, and the two ends of a point-to-point link" {
  let block = Prefix::parse("192.0.2.0/30")
  assert_eq(join_blocks_hosts(block), "192.0.2.1|192.0.2.2")
  // RFC 3021: both addresses of a /31 are usable.
  assert_eq(
    join_blocks_hosts(Prefix::parse("192.0.2.0/31")),
    "192.0.2.0|192.0.2.1",
  )
  assert_eq(join_blocks_hosts(Prefix::parse("192.0.2.7/32")), "192.0.2.7")
  // IPv6 has no broadcast, so only the subnet-router anycast address is left out.
  assert_eq(
    join_blocks_hosts(Prefix::parse("2001:db8::/126")),
    "2001:db8::1|2001:db8::2|2001:db8::3",
  )
  assert_eq(
    join_blocks_hosts(Prefix::parse("2001:db8::/127")),
    "2001:db8::|2001:db8::1",
  )
  assert_eq(join_blocks_hosts(Prefix::parse("2001:db8::1/128")), "2001:db8::1")
}

///|
fn join_blocks_hosts(prefix : Prefix) -> String {
  let mut out = ""
  let mut first = true
  for host in prefix.hosts() {
    if !first {
      out = out + "|"
    }
    first = false
    out = out + host.to_string()
  }
  out
}
