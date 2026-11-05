// Text forms, checked against the vectors generated from CPython's ipaddress and
// Go's net/netip.

///|
fn hex_of_bytes(bytes : Bytes) -> String {
  let digits = "0123456789abcdef"
  let mut out = ""
  for i = 0; i < bytes.length(); i = i + 1 {
    let value = bytes.at(i).to_int()
    let high = digits.get_char(value >> 4).unwrap().to_string()
    let low = digits.get_char(value & 0xF).unwrap().to_string()
    out = out + high + low
  }
  out
}

///|
fn parse_addr(text : String) -> Addr? {
  Some(Addr::parse(text)) catch {
    _ => None
  }
}

///|
/// Whether the refusal is the one expected, by variant.
fn refuses_with(text : String, expected : String) -> Bool {
  try {
    let _ = Addr::parse(text)
    false
  } catch {
    Refused::Malformed(at~) => expected == "malformed" && at >= 0
    Refused::OutOfRange(limit~, got~) =>
      expected == "out_of_range" && limit >= 0 && got >= 0
    _ => false
  }
}

///|
test "text: every case agrees with both reference implementations" {
  for row in addr_text_cases() {
    let (input, accepted, canonical, exploded, packed) = row
    let parsed = parse_addr(input)
    if !accepted {
      assert_true(parsed is None, msg="expected a refusal for {" + input + "}")
      continue
    }
    match parsed {
      None => assert_true(false, msg="refused {" + input + "}")
      Some(addr) => {
        assert_eq(addr.to_string(), canonical, msg="text {" + input + "}")
        if exploded != "-" {
          assert_eq(addr.exploded(), exploded, msg="exploded {" + input + "}")
        }
        assert_eq(
          hex_of_bytes(addr.encode()),
          packed,
          msg="bytes {" + input + "}",
        )
      }
    }
  }
}

///|
test "text: a refusal says where it stopped" {
  // The offset is what a caller needs to point at the typo, so it is part of the
  // contract even though neither reference reports one.
  assert_true(refuses_with("", "malformed"))
  assert_true(refuses_with("1.2.3", "malformed"))
  assert_true(refuses_with("1.2.3.4.5", "malformed"))
  assert_true(refuses_with("1.2.3.256", "out_of_range"))
  assert_true(refuses_with("01.2.3.4", "malformed"))
  assert_true(refuses_with(":::", "malformed"))
  assert_true(refuses_with("1::2::3", "malformed"))
  assert_true(refuses_with("12345::", "malformed"))
  assert_true(refuses_with("fe80::1%", "malformed"))
  try {
    let _ = Addr::parse("1.2.3.256")
    assert_true(false, msg="1.2.3.256 was accepted")
  } catch {
    Refused::OutOfRange(limit~, got~) => {
      assert_eq(limit, 255)
      assert_eq(got, 256)
    }
    _ => assert_true(false, msg="wrong refusal for 1.2.3.256")
  }
  try {
    let _ = Addr::parse("1.2.3.4.5")
    assert_true(false, msg="1.2.3.4.5 was accepted")
  } catch {
    Refused::Malformed(at~) => assert_eq(at, 7)
    _ => assert_true(false, msg="wrong refusal for 1.2.3.4.5")
  }
}

///|
test "text: a zone is an interface name, and only that" {
  let link = Addr::parse("fe80::1%eth0")
  assert_eq(link.zone(), Some("eth0"))
  assert_eq(link.to_string(), "fe80::1%eth0")
  assert_eq(link.exploded(), "fe80:0000:0000:0000:0000:0000:0000:0001")
  // Two per cent signs are a typo rather than a nested zone.
  assert_true(parse_addr("fe80::1%a%b") is None)
  // A zone needs an address to sit on.
  assert_true(parse_addr("::%eth0") is Some(_))
  assert_true(parse_addr("1.2.3.4%eth0") is None)
  // Nothing caps the length of an interface name.
  let long = "fe80::1%abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz"
  assert_eq(
    Addr::parse(long).zone(),
    Some("abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz"),
  )
}

///|
test "text: the canonical form is RFC 5952" {
  // A single zero group is written out; a run of two or more is compressed.
  assert_eq(
    Addr::parse("2001:db8:0:1:1:1:1:1").to_string(),
    "2001:db8:0:1:1:1:1:1",
  )
  assert_eq(
    Addr::parse("2001:db8:0:0:1:0:0:1").to_string(),
    "2001:db8::1:0:0:1",
  )
  assert_eq(Addr::parse("2001:db8::0:1").to_string(), "2001:db8::1")
  assert_eq(Addr::parse("2001:0:0:1:0:0:0:1").to_string(), "2001:0:0:1::1")
  assert_eq(Addr::parse("2001:DB8::1").to_string(), "2001:db8::1")
  assert_eq(Addr::parse("::").to_string(), "::")
  assert_eq(Addr::parse("::1").to_string(), "::1")
  assert_eq(Addr::parse("1::").to_string(), "1::")
  // Two runs of the same length: the left one is the one compressed.
  assert_eq(Addr::parse("1:0:0:2:0:0:3:4").to_string(), "1::2:0:0:3:4")
}

///|
test "text: an IPv4-mapped address keeps its dotted tail" {
  let mapped = Addr::parse("::ffff:192.0.2.1")
  assert_eq(mapped.to_string(), "::ffff:192.0.2.1")
  assert_eq(mapped.exploded(), "0000:0000:0000:0000:0000:ffff:192.0.2.1")
  assert_eq(mapped.unmap().to_string(), "192.0.2.1")
  assert_eq(Addr::parse("::ffff:c000:201").to_string(), "::ffff:192.0.2.1")
  assert_eq(Addr::parse("::ffff:0:0").to_string(), "::ffff:0.0.0.0")
}

///|
test "text: reverse pointers" {
  assert_eq(
    Addr::parse("192.0.2.1").reverse_pointer(),
    "1.2.0.192.in-addr.arpa",
  )
  assert_eq(
    Addr::parse("2001:db8::567:89ab").reverse_pointer(),
    "b.a.9.8.7.6.5.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.b.d.0.1.0.0.2.ip6.arpa",
  )
  // A zone names a link, not the address, so it is not in the name.
  assert_eq(
    Addr::parse("fe80::1%eth0").reverse_pointer(),
    "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.e.f.ip6.arpa",
  )
}
