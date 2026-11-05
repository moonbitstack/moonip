// The address value itself: construction, neighbours, encodings and the
// conversions that only make sense on one family or the other.

///|
test "address: the four values everyone writes" {
  assert_eq(unspecified4.to_string(), "0.0.0.0")
  assert_eq(unspecified6.to_string(), "::")
  assert_eq(loopback4.to_string(), "127.0.0.1")
  assert_eq(loopback6.to_string(), "::1")
  assert_true(unspecified4.is_v4())
  assert_true(unspecified6.is_v6())
  assert_eq(unspecified4.bits(), 32)
  assert_eq(unspecified6.bits(), 128)
}

///|
test "address: built from parts" {
  let dotted = Addr::v4(b'\xc0', b'\x00', b'\x02', b'\x01')
  assert_eq(dotted.to_string(), "192.0.2.1")
  let halves = Addr::v6(0x2001_0DB8_0000_0000UL, 0x0000_0000_0000_0001UL)
  assert_eq(halves.to_string(), "2001:db8::1")
  assert_eq(halves.exploded(), "2001:0db8:0000:0000:0000:0000:0000:0001")
}

///|
test "address: neighbours, and the ends of each family" {
  assert_eq(Addr::parse("192.0.2.1").next().unwrap().to_string(), "192.0.2.2")
  assert_eq(Addr::parse("192.0.2.1").prev().unwrap().to_string(), "192.0.2.0")
  assert_true(Addr::parse("255.255.255.255").next() is None)
  assert_true(Addr::parse("0.0.0.0").prev() is None)
  assert_eq(
    Addr::parse("::ffff:ffff:ffff:ffff").next().unwrap().to_string(),
    "0:0:0:1::",
  )
  assert_eq(
    Addr::parse("1:0:0:0:0:0:0:0").prev().unwrap().to_string(),
    "0:ffff:ffff:ffff:ffff:ffff:ffff:ffff",
  )
  assert_true(
    Addr::parse("ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff").next() is None,
  )
  assert_true(Addr::parse("::").prev() is None)
  // The zone belongs to the link, not the address, and a neighbour is on the same
  // link.
  assert_eq(
    Addr::parse("fe80::1%eth0").next().unwrap().to_string(),
    "fe80::2%eth0",
  )
}

///|
test "address: the IPv4-mapped form" {
  let v4 = Addr::parse("192.0.2.1")
  assert_eq(v4.mapped().to_string(), "::ffff:192.0.2.1")
  assert_true(v4.mapped().is_v4_mapped())
  assert_true(!v4.is_v4_mapped())
  assert_eq(v4.mapped().unmap(), v4)
  // Anything that is not the mapped form comes back as it was.
  let plain = Addr::parse("2001:db8::1")
  assert_eq(plain.unmap(), plain)
  assert_eq(plain.mapped(), plain)
  assert_eq(
    Addr::parse("::ffff:192.0.2.1").mapped().to_string(),
    "::ffff:192.0.2.1",
  )
  // Unmapping drops the zone, which belongs to the IPv6 form.
  assert_eq(Addr::parse("::ffff:192.0.2.1%eth0").unmap().zone(), None)
}

///|
test "address: the two transition forms" {
  assert_eq(
    Addr::parse("2002:c000:0204::1").sixtofour().unwrap().to_string(),
    "192.0.2.4",
  )
  assert_true(Addr::parse("192.0.2.4").sixtofour() is None)
  assert_true(Addr::parse("2001:db8::1").sixtofour() is None)
  let (server, client) = Addr::parse("2001:0:4136:e378:8000:63bf:3fff:fdd2")
    .teredo()
    .unwrap()
  assert_eq(server.to_string(), "65.54.227.120")
  assert_eq(client.to_string(), "192.0.2.45")
  assert_true(Addr::parse("2001:db8::1").teredo() is None)
  assert_true(Addr::parse("192.0.2.1").teredo() is None)
}

///|
test "address: bytes in and out" {
  let v4 = Addr::parse("192.0.2.1")
  assert_eq(v4.encode().length(), 4)
  assert_eq(Addr::decode(v4.encode()[:]), v4)
  let v6 = Addr::parse("2001:db8::1")
  assert_eq(v6.encode().length(), 16)
  assert_eq(Addr::decode(v6.encode()[:]), v6)
  // A zone is not part of the address and does not survive the round trip.
  assert_eq(Addr::decode(Addr::parse("fe80::1%eth0").encode()[:]).zone(), None)
  try {
    let _ = Addr::decode(b"\x01\x02\x03")
    assert_true(false, msg="three bytes were accepted")
  } catch {
    Refused::Length(want~, got~) => {
      assert_eq(want, 16)
      assert_eq(got, 3)
    }
    _ => assert_true(false, msg="wrong refusal for three bytes")
  }
}

///|
test "address: zones" {
  let link = Addr::parse("fe80::1")
  assert_eq(link.zone(), None)
  assert_eq(link.with_zone(Some("en0")).to_string(), "fe80::1%en0")
  assert_eq(link.with_zone(Some("en0")).with_zone(None).to_string(), "fe80::1")
  // A zone says nothing about an IPv4 address, so it is ignored.
  assert_eq(Addr::parse("192.0.2.1").with_zone(Some("en0")).zone(), None)
  // The zone is part of the value.
  assert_true(Addr::parse("fe80::1") != Addr::parse("fe80::1%en0"))
  assert_true(Addr::parse("fe80::1") < Addr::parse("fe80::1%en0"))
}

///|
test "address: values can key a map" {
  let seen : Map[Addr, Int32] = Map([])
  seen[Addr::parse("192.0.2.1")] = 1
  seen[Addr::parse("::1")] = 2
  seen[Addr::parse("192.0.2.1")] = 3
  assert_eq(seen.length(), 2)
  assert_eq(seen.get(Addr::parse("192.0.2.1")), Some(3))
  assert_eq(seen.get(Addr::parse("::1")), Some(2))
  // The two families do not collide even when the low bits match.
  assert_true(Addr::parse("192.0.2.1") != Addr::parse("::192.0.2.1"))
  assert_eq(Addr::parse("192.0.2.1").hash(), Addr::parse("192.0.2.1").hash())
}

///|
test "address: the order sorts by family, then by number" {
  assert_true(Addr::parse("255.255.255.255") < Addr::parse("::"))
  assert_true(Addr::parse("192.0.2.1") < Addr::parse("192.0.2.2"))
  assert_true(Addr::parse("::2") < Addr::parse("::1:0"))
  let sorted = [
    Addr::parse("2001:db8::2"),
    Addr::parse("10.0.0.1"),
    Addr::parse("::1"),
  ]
  sorted.sort()
  assert_eq(sorted[0].to_string(), "10.0.0.1")
  assert_eq(sorted[1].to_string(), "::1")
  assert_eq(sorted[2].to_string(), "2001:db8::2")
}

///|
test "address: the debug form is the text form, quoted" {
  assert_eq(@debug.to_string(Addr::parse("192.0.2.1")), "\"192.0.2.1\"")
  assert_eq(@debug.to_string(Prefix::parse("192.0.2.0/24")), "\"192.0.2.0/24\"")
  assert_eq(@debug.to_string(AddrPort::parse("[::1]:80")), "\"[::1]:80\"")
}
