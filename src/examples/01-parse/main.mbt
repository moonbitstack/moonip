///|
/// What one address is, in the order the questions are usually asked: can it be
/// written, what does its canonical text look like, which family is it, where does
/// it route, and is it reachable.
///
///     moon run src/examples/01-parse --target native
#coverage.skip
fn main {
  let samples = [
    "192.0.2.1", "10.1.2.3", "100.64.0.1", "8.8.8.8", "::ffff:192.0.2.1", "2001:db8::1",
    "fe80::1%eth0", "2001:4860:4860::8888", "not an address", "1.2.3.256",
  ]
  println(
    "address              family bits  private global  loopback  reserved  text",
  )
  for text in samples {
    match try_parse(text) {
      None => println(pad(text, 20) + "  refused")
      Some(addr) =>
        println(
          pad(text, 20) +
          "  " +
          pad(if addr.is_v4() { "v4" } else { "v6" }, 5) +
          pad(addr.bits().to_string(), 5) +
          pad(yes(addr.is_private()), 8) +
          pad(yes(addr.is_global()), 7) +
          pad(yes(addr.is_loopback()), 10) +
          pad(yes(addr.is_reserved()), 9) +
          "  " +
          addr.to_string(),
        )
    }
  }
  println("")
  println("One address, five ways to look at it:")
  let plain = try_parse("2002:c000:0204::1").unwrap()
  println("  canonical  " + plain.to_string())
  println("  exploded   " + plain.exploded())
  println("  bytes      " + hex(plain.encode()))
  println("  reverse    " + plain.reverse_pointer())
  println("  its 6to4  " + plain.sixtofour().unwrap().to_string())
}

///|
fn try_parse(text : String) -> @moonip.Addr? {
  Some(@moonip.Addr::parse(text)) catch {
    _ => None
  }
}

///|
fn yes(value : Bool) -> String {
  if value {
    "yes"
  } else {
    "-"
  }
}

///|
fn pad(text : String, width : Int32) -> String {
  let mut out = text
  while out.length() < width {
    out = out + " "
  }
  out
}

///|
fn hex(bytes : Bytes) -> String {
  let digits = "0123456789abcdef"
  let mut out = ""
  for i = 0; i < bytes.length(); i = i + 1 {
    let value = bytes.at(i).to_int()
    let high = digits.get_char(value >> 4).unwrap().to_string()
    let low = digits.get_char(value & 0xF).unwrap().to_string()
    out = out + high + low + (if i + 1 < bytes.length() { ":" } else { "" })
  }
  out
}
