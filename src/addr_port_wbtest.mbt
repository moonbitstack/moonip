// An address with a port, which is how a conversation names its two ends.

///|
fn parse_endpoint(text : String) -> AddrPort? {
  Some(AddrPort::parse(text)) catch {
    _ => None
  }
}

///|
test "address and port: every case agrees with net/netip" {
  for row in addrport_cases() {
    let (text, accepted, expected) = row
    match parse_endpoint(text) {
      Some(endpoint) => {
        assert_true(
          accepted,
          msg="accepted {" + text + "} where net/netip refused",
        )
        assert_eq(endpoint.to_string(), expected, msg="text {" + text + "}")
      }
      None => assert_true(!accepted, msg="refused {" + text + "}")
    }
  }
}

///|
test "address and port: brackets are what makes the last colon the port" {
  let v4 = AddrPort::parse("192.0.2.1:8080")
  assert_eq(v4.addr().to_string(), "192.0.2.1")
  assert_eq(v4.port(), 8080)
  let v6 = AddrPort::parse("[2001:db8::1]:443")
  assert_eq(v6.addr().to_string(), "2001:db8::1")
  assert_eq(v6.port(), 443)
  // Without brackets an IPv6 address cannot be told from the port.
  assert_true(parse_endpoint("2001:db8::1:443") is None)
  // Brackets are only for IPv6.
  assert_true(parse_endpoint("[192.0.2.1]:80") is None)
  // A zone is part of the address, so it goes inside the brackets.
  assert_eq(
    AddrPort::parse("[fe80::1%eth0]:546").to_string(),
    "[fe80::1%eth0]:546",
  )
}

///|
test "address and port: the port is a number in 0 to 65535" {
  assert_eq(
    AddrPort::new(Addr::parse("192.0.2.1"), 0).to_string(),
    "192.0.2.1:0",
  )
  assert_eq(
    AddrPort::new(Addr::parse("192.0.2.1"), 65535).to_string(),
    "192.0.2.1:65535",
  )
  try {
    let _ = AddrPort::new(Addr::parse("192.0.2.1"), 65536)
    assert_true(false, msg="port 65536 was accepted")
  } catch {
    Refused::OutOfRange(limit~, got~) => {
      assert_eq(limit, 65535)
      assert_eq(got, 65536)
    }
    _ => assert_true(false, msg="wrong refusal for port 65536")
  }
  try {
    let _ = AddrPort::parse("192.0.2.1:65536")
    assert_true(false, msg="port 65536 was accepted")
  } catch {
    Refused::OutOfRange(limit~, got~) => {
      assert_eq(limit, 65535)
      assert_eq(got, 65536)
    }
    _ => assert_true(false, msg="wrong refusal for port 65536")
  }
  // The port is decimal digits, nothing else.
  assert_true(parse_endpoint("192.0.2.1:+80") is None)
  assert_true(parse_endpoint("192.0.2.1:-1") is None)
  assert_true(parse_endpoint("192.0.2.1: 80") is None)
  assert_true(parse_endpoint("192.0.2.1:") is None)
}

///|
test "address and port: values can key a map and sort by host then port" {
  let seen : Map[AddrPort, String] = Map([])
  seen[AddrPort::parse("192.0.2.1:80")] = "http"
  seen[AddrPort::parse("192.0.2.1:443")] = "https"
  assert_eq(seen.length(), 2)
  assert_eq(seen.get(AddrPort::parse("192.0.2.1:443")), Some("https"))
  let ports = [
    AddrPort::parse("192.0.2.2:1"),
    AddrPort::parse("192.0.2.1:443"),
    AddrPort::parse("192.0.2.1:80"),
  ]
  ports.sort()
  assert_eq(ports[0].to_string(), "192.0.2.1:80")
  assert_eq(ports[1].to_string(), "192.0.2.1:443")
  assert_eq(ports[2].to_string(), "192.0.2.2:1")
}
