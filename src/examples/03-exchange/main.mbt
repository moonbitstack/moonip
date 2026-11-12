///|
/// Write out what the library makes of each address or block it is given, in the
/// forms another implementation can read back: canonical text, the encoded bytes,
/// and for a block its two masks and its broadcast address.
///
///     moon run src/examples/03-exchange --target native -- 192.0.2.1 2001:db8::/32
///
/// A row starts with `a` for an address or `p` for a block, then the text that was
/// given, then what the library made of it, tab-separated:
///
///     a  <input>  <text>  <hex of the 4 or 16 bytes>
///     p  <input>  <text>  <netmask>  <hostmask>  <broadcast, or - when there is none>
///
/// The input is echoed so a caller can line the answer up with its own list.
/// Anything the parser refuses is reported on a line of its own, so a caller that
/// feeds it a corpus sees which rows never got as far as an answer.
#coverage.skip
fn main {
  let args = @env.args()
  // The runtime puts the program itself first.
  let inputs = if args.length() > 1 { args[1:] } else { demo() }
  for text in inputs {
    match text.find("/") {
      Some(_) =>
        match prefix_of(text) {
          Some(block) => write_block(text, block)
          None => println("# refused " + text)
        }
      None =>
        match addr_of(text) {
          Some(addr) => write_addr(text, addr)
          None => println("# refused " + text)
        }
    }
  }
}

///|
fn demo() -> Array[String] {
  [
    "192.0.2.1", "2001:db8::1", "::ffff:192.0.2.1", "fe80::1%eth0", "2001:db8::/32",
    "192.0.2.0/24",
  ]
}

///|
fn addr_of(text : String) -> @moonip.Addr? {
  Some(@moonip.Addr::parse(text)) catch {
    _ => None
  }
}

///|
fn prefix_of(text : String) -> @moonip.Prefix? {
  Some(@moonip.Prefix::parse(text, strict=false)) catch {
    _ => None
  }
}

///|
fn write_addr(given : String, addr : @moonip.Addr) -> Unit {
  println("a\t" + given + "\t" + addr.to_string() + "\t" + hex(addr.encode()))
}

///|
fn write_block(given : String, prefix : @moonip.Prefix) -> Unit {
  let block = prefix.masked()
  let broadcast = match block.broadcast() {
    Some(addr) => addr.to_string()
    None => "-"
  }
  println(
    "p\t" +
    given +
    "\t" +
    block.to_string() +
    "\t" +
    block.netmask().to_string() +
    "\t" +
    block.hostmask().to_string() +
    "\t" +
    broadcast,
  )
}

///|
fn hex(bytes : Bytes) -> String {
  let digits = "0123456789abcdef"
  let mut out = ""
  for byte in bytes {
    out = out +
      digits.get_char((byte.to_int() >> 4) & 0xF).unwrap().to_string() +
      digits.get_char(byte.to_int() & 0xF).unwrap().to_string()
  }
  out
}
