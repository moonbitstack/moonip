// Prefixes: parsing, masks and the questions one block asks about another,
// checked against the vectors generated from CPython's ipaddress and Go's
// net/netip.

///|
fn parse_prefix(text : String, strict : Bool) -> Prefix? {
  Some(Prefix::parse(text, strict~)) catch {
    _ => None
  }
}

///|
test "prefix: every parse agrees with the references" {
  for row in prefix_parse_cases() {
    let (text, accepted, canonical, relaxed) = row
    match parse_prefix(text, true) {
      Some(prefix) => {
        assert_true(
          accepted,
          msg="accepted {" + text + "} where the reference refused",
        )
        assert_eq(prefix.to_string(), canonical, msg="strict {" + text + "}")
      }
      None => assert_true(!accepted, msg="refused {" + text + "}")
    }
    match parse_prefix(text, false) {
      Some(prefix) =>
        assert_eq(prefix.to_string(), relaxed, msg="relaxed {" + text + "}")
      None => assert_eq(relaxed, "", msg="relaxed {" + text + "}")
    }
  }
}

///|
fn describe_hosts(prefix : Prefix) -> String {
  let hosts = prefix.hosts().collect()
  if hosts.length() == 0 {
    return "none"
  }
  hosts[0].to_string() +
  ".." +
  hosts[hosts.length() - 1].to_string() +
  " (" +
  hosts.length().to_string() +
  ")"
}

///|
test "prefix: masks, ends and usable hosts agree with the references" {
  for row in prefix_shape_cases() {
    let (
      text,
      masked,
      netmask,
      hostmask,
      broadcast,
      first_host,
      last_host,
      count,
    ) = row
    let prefix = Prefix::parse(text, strict=false)
    assert_eq(prefix.masked().to_string(), masked, msg="masked {" + text + "}")
    assert_eq(
      prefix.netmask().to_string(),
      netmask,
      msg="netmask {" + text + "}",
    )
    assert_eq(
      prefix.hostmask().to_string(),
      hostmask,
      msg="hostmask {" + text + "}",
    )
    match prefix.broadcast() {
      Some(last) =>
        assert_eq(last.to_string(), broadcast, msg="broadcast {" + text + "}")
      None => assert_eq(broadcast, "-", msg="broadcast {" + text + "}")
    }
    assert_eq(
      prefix.hosts().next().unwrap().to_string(),
      first_host,
      msg="first host {" + text + "}",
    )
    if count != "many" {
      assert_eq(
        describe_hosts(prefix),
        first_host + ".." + last_host + " (" + count + ")",
        msg="hosts {" + text + "}",
      )
    }
  }
}

///|
test "prefix: host bits are refused unless the caller says otherwise" {
  try {
    let _ = Prefix::parse("192.0.2.5/24")
    assert_true(false, msg="host bits were accepted with strict on")
  } catch {
    Refused::HostBits => ()
    _ => assert_true(false, msg="wrong refusal for host bits")
  }
  assert_eq(
    Prefix::parse("192.0.2.5/24", strict=false).to_string(),
    "192.0.2.0/24",
  )
  assert_eq(
    Prefix::parse("192.0.2.5/24", strict=false).addr().to_string(),
    "192.0.2.0",
  )
  // An interface keeps the address it was given until it is masked.
  let interface = Prefix::new(Addr::parse("192.0.2.5"), 24)
  assert_eq(interface.to_string(), "192.0.2.5/24")
  assert_eq(interface.masked().to_string(), "192.0.2.0/24")
  assert_eq(interface.addr().to_string(), "192.0.2.5")
  assert_eq(interface.bits(), 24)
}

///|
test "prefix: lengths and zones" {
  try {
    let _ = Prefix::parse("192.0.2.0/33")
    assert_true(false, msg="/33 was accepted")
  } catch {
    Refused::OutOfRange(limit~, got~) => {
      assert_eq(limit, 32)
      assert_eq(got, 33)
    }
    _ => assert_true(false, msg="wrong refusal for /33")
  }
  try {
    let _ = Prefix::parse("2001:db8::/129")
    assert_true(false, msg="/129 was accepted")
  } catch {
    Refused::OutOfRange(limit~, got~) => {
      assert_eq(limit, 128)
      assert_eq(got, 129)
    }
    _ => assert_true(false, msg="wrong refusal for /129")
  }
  // Neither reference agrees with the other on a zone in a prefix, and both
  // answers are wrong for a block: a zone names a link, and a block spans links.
  assert_true(parse_prefix("fe80::1%eth0/64", false) is None)
  assert_true(parse_prefix("fe80::/10", false) is Some(_))
  // A dotted netmask is not a length; only the bit count is read.
  assert_true(parse_prefix("192.0.2.0/255.255.255.0", false) is None)
  assert_true(parse_prefix("192.0.2.0/024", false) is None)
}

///|
test "prefix: containment, overlap and nesting" {
  let block = Prefix::parse("192.0.2.0/24")
  assert_true(block.contains(Addr::parse("192.0.2.0")))
  assert_true(block.contains(Addr::parse("192.0.2.255")))
  assert_true(!block.contains(Addr::parse("192.0.3.1")))
  assert_true(!block.contains(Addr::parse("192.0.1.255")))
  // Families never mix, not even through an IPv4-mapped address.
  assert_true(!block.contains(Addr::parse("::ffff:192.0.2.1")))
  assert_true(!block.contains(Addr::parse("::")))
  assert_true(block.overlaps(Prefix::parse("192.0.2.128/25")))
  assert_true(block.overlaps(Prefix::parse("0.0.0.0/0")))
  assert_true(!block.overlaps(Prefix::parse("192.0.3.0/24")))
  assert_true(!block.overlaps(Prefix::parse("2001:db8::/32")))
  assert_true(Prefix::parse("192.0.2.128/25").is_subnet_of(block))
  assert_true(block.is_subnet_of(block))
  assert_true(!block.is_subnet_of(Prefix::parse("192.0.2.128/25")))
  assert_true(
    Prefix::parse("2001:db8::/32").is_subnet_of(Prefix::parse("2000::/3")),
  )
  assert_true(
    !Prefix::parse("2001:db8::/32").is_subnet_of(Prefix::parse("192.0.2.0/24")),
  )
}

///|
test "prefix: blocks are values" {
  // Two prefixes of the same block compare equal and hash the same, so they can
  // key a map; the address as written is part of the value.
  let a = Prefix::parse("192.0.2.0/24")
  let b = Prefix::parse("192.0.2.0/24")
  assert_eq(a, b)
  assert_eq(a.hash(), b.hash())
  let seen : Map[Prefix, String] = Map([])
  seen[a] = "documentation"
  assert_eq(seen.get(b), Some("documentation"))
  assert_true(a < Prefix::parse("192.0.2.128/25"))
  assert_true(a < Prefix::parse("2001:db8::/32"))
  // A shorter mask on the same address sorts first, which is what collapse and
  // the containment walk rely on.
  assert_true(Prefix::new(Addr::parse("192.0.2.0"), 16) < a)
}
