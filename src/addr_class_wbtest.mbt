// Classification, checked against the vectors generated from CPython's ipaddress
// (all eight registry predicates) and Go's net/netip (the four it shares, plus the
// two multicast scopes it names separately).

///|
let flag_private : Int32 = 1

///|
let flag_global : Int32 = 2

///|
let flag_loopback : Int32 = 4

///|
let flag_unspecified : Int32 = 8

///|
let flag_multicast : Int32 = 16

///|
let flag_link_local : Int32 = 32

///|
let flag_reserved : Int32 = 64

///|
let flag_site_local : Int32 = 128

///|
fn bit(condition : Bool, flag : Int32) -> Int32 {
  if condition {
    flag
  } else {
    0
  }
}

///|
fn flags_of(addr : Addr) -> Int32 {
  bit(addr.is_private(), flag_private) |
  bit(addr.is_global(), flag_global) |
  bit(addr.is_loopback(), flag_loopback) |
  bit(addr.is_unspecified(), flag_unspecified) |
  bit(addr.is_multicast(), flag_multicast) |
  bit(addr.is_link_local(), flag_link_local) |
  bit(addr.is_reserved(), flag_reserved) |
  bit(addr.is_site_local(), flag_site_local)
}

///|
test "classification: every case agrees with ipaddress" {
  for row in addr_class_cases() {
    let (text, expected) = row
    let addr = Addr::parse(text)
    assert_eq(flags_of(addr), expected, msg="classification of {" + text + "}")
  }
}

///|
test "classification: the four predicates net/netip also has agree with it" {
  for row in go_class_cases() {
    let (text, expected) = row
    let addr = Addr::parse(text)
    let mine = bit(addr.is_loopback(), flag_loopback) |
      bit(addr.is_multicast(), flag_multicast) |
      bit(addr.is_link_local(), flag_link_local) |
      bit(addr.is_unspecified(), flag_unspecified)
    assert_eq(mine, expected, msg="classification of {" + text + "}")
  }
}

///|
test "classification: the IANA registry, block by block" {
  // Every row of iana-ipv4-special-registry and iana-ipv6-special-registry, by
  // first and last address, with the boundaries that decide a block's ends.
  let private4 = [
    ("0.0.0.0", "0.255.255.255"),
    ("10.0.0.0", "10.255.255.255"),
    ("127.0.0.0", "127.255.255.255"),
    ("169.254.0.0", "169.254.255.255"),
    ("172.16.0.0", "172.31.255.255"),
    ("192.0.0.0", "192.0.0.255"),
    ("192.0.2.0", "192.0.2.255"),
    ("192.168.0.0", "192.168.255.255"),
    ("198.18.0.0", "198.19.255.255"),
    ("198.51.100.0", "198.51.100.255"),
    ("203.0.113.0", "203.0.113.255"),
    ("240.0.0.0", "255.255.255.255"),
  ]
  for row in private4 {
    let (first, last) = row
    assert_true(Addr::parse(first).is_private(), msg=first)
    assert_true(Addr::parse(last).is_private(), msg=last)
    assert_true(!Addr::parse(first).is_global(), msg=first)
  }
  // The two anycast addresses inside 192.0.0.0/24 are reachable.
  assert_true(Addr::parse("192.0.0.8").is_private())
  assert_true(!Addr::parse("192.0.0.9").is_private())
  assert_true(!Addr::parse("192.0.0.10").is_private())
  assert_true(Addr::parse("192.0.0.11").is_private())
  // Shared address space is neither private nor reachable.
  assert_true(!Addr::parse("100.64.0.1").is_private())
  assert_true(!Addr::parse("100.64.0.1").is_global())
  assert_true(Addr::parse("8.8.8.8").is_global())

  let private6 = [
    ("::", "::"),
    ("::1", "::1"),
    ("::ffff:0.0.0.1", "::ffff:0.0.0.1"),
    ("64:ff9b:1::", "64:ff9b:1:ffff:ffff:ffff:ffff:ffff"),
    ("100::", "100::ffff:ffff:ffff:ffff"),
    ("2001::", "2001:1ff:ffff:ffff:ffff:ffff:ffff:ffff"),
    ("2001:db8::", "2001:db8:ffff:ffff:ffff:ffff:ffff:ffff"),
    ("2002::", "2002:ffff:ffff:ffff:ffff:ffff:ffff:ffff"),
    ("3fff::", "3fff:fff:ffff:ffff:ffff:ffff:ffff:ffff"),
    ("fc00::", "fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"),
    ("fe80::", "febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff"),
  ]
  for row in private6 {
    let (first, last) = row
    assert_true(Addr::parse(first).is_private(), msg=first)
    assert_true(Addr::parse(last).is_private(), msg=last)
  }
  // The blocks the registry marks reachable inside 2001::/23.
  let reachable6 = [
    "2001:1::1", "2001:1::2", "2001:3::1", "2001:4:112::1", "2001:20::1", "2001:30::1",
  ]
  for text in reachable6 {
    assert_true(!Addr::parse(text).is_private(), msg=text)
    assert_true(Addr::parse(text).is_global(), msg=text)
  }
  assert_true(Addr::parse("2001:2::1").is_private())
  assert_true(Addr::parse("2001:2:0:ffff::1").is_private())
  assert_true(Addr::parse("2001:db9::1").is_global())
  assert_true(Addr::parse("64:ff9b::1.2.3.4").is_global())
  assert_true(Addr::parse("2620:4f:8000::1").is_global())
}

///|
test "classification: predicates that are their own thing" {
  assert_true(Addr::parse("0.0.0.0").is_unspecified())
  assert_true(Addr::parse("::").is_unspecified())
  assert_true(!Addr::parse("0.0.0.1").is_unspecified())
  assert_true(Addr::parse("255.255.255.255").is_reserved())
  assert_true(Addr::parse("224.0.0.1").is_multicast())
  assert_true(Addr::parse("ff02::1").is_multicast())
  assert_true(!Addr::parse("223.255.255.255").is_multicast())
  assert_true(Addr::parse("fec0::1").is_site_local())
  assert_true(!Addr::parse("fec0::1").is_reserved())
  assert_true(!Addr::parse("192.0.2.1").is_site_local())
  assert_true(Addr::parse("FE80::1").is_link_local())
  assert_true(!Addr::parse("fec0::1").is_link_local())
  assert_true(Addr::parse("127.0.0.1").is_loopback())
  assert_true(Addr::parse("::1").is_loopback())
  assert_true(!Addr::parse("::2").is_loopback())
}

///|
test "classification: the multicast scopes agree with net/netip" {
  for row in go_scope_cases() {
    let (text, expected) = row
    let addr = Addr::parse(text)
    let mine = bit(addr.is_interface_local_multicast(), 1) |
      bit(addr.is_link_local_multicast(), 2)
    assert_eq(mine, expected, msg="multicast scope of {" + text + "}")
  }
}

///|
test "classification: the two multicast scopes have their own predicates" {
  // RFC 4291 section 2.7 puts the scope in the second and third octets of an
  // ff00::/8 address; 1 is the interface, 2 the link.
  assert_true(Addr::parse("ff01::1").is_interface_local_multicast())
  assert_true(!Addr::parse("ff01::1").is_link_local_multicast())
  assert_true(Addr::parse("ff02::fb").is_link_local_multicast())
  assert_true(!Addr::parse("ff02::fb").is_interface_local_multicast())
  assert_true(!Addr::parse("ff05::1").is_interface_local_multicast())
  assert_true(!Addr::parse("ff05::1").is_link_local_multicast())
  // Both are multicast, and neither is link-local unicast.
  assert_true(Addr::parse("ff02::1").is_multicast())
  assert_true(!Addr::parse("ff02::1").is_link_local())
  // IPv4's link-local multicast is 224.0.0.0/24 (RFC 1112); the rest of 224/4 is
  // multicast with a wider scope, and IPv4 has no interface-local scope.
  assert_true(Addr::parse("224.0.0.1").is_link_local_multicast())
  assert_true(Addr::parse("224.0.0.255").is_link_local_multicast())
  assert_true(!Addr::parse("224.0.1.1").is_link_local_multicast())
  assert_true(!Addr::parse("239.255.255.250").is_link_local_multicast())
  assert_true(!Addr::parse("224.0.0.1").is_interface_local_multicast())
  // Link-local unicast is a different predicate.
  assert_true(!Addr::parse("169.254.1.1").is_link_local_multicast())
  assert_true(!Addr::parse("fe80::1").is_link_local_multicast())
  // An IPv4-mapped address is judged as the IPv4 one, like the rest.
  assert_true(Addr::parse("::ffff:224.0.0.1").is_link_local_multicast())
}

///|
test "classification: an IPv4-mapped address is judged as the IPv4 one" {
  // ipaddress unmaps before asking, and so does this library; net/netip agrees on
  // the four predicates it has, except for the unspecified zero.
  assert_true(Addr::parse("::ffff:10.0.0.1").is_private())
  assert_true(Addr::parse("::ffff:127.0.0.1").is_loopback())
  assert_true(Addr::parse("::ffff:224.0.0.1").is_multicast())
  assert_true(Addr::parse("::ffff:169.254.1.1").is_link_local())
  assert_true(Addr::parse("::ffff:240.0.0.1").is_reserved())
  assert_true(Addr::parse("::ffff:0.0.0.0").is_unspecified())
  assert_true(!Addr::parse("::ffff:8.8.8.8").is_private())
  // The zone does not change what the bits are.
  assert_true(Addr::parse("fe80::1%eth0").is_link_local())
}
