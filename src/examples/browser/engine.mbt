// The engine behind the two interactives on the site. Each export takes text from
// a form and answers with JSON; every decision in the answer comes from the
// library, built to JavaScript from this package.

///|
/// Everything the bit explorer shows about one address: whether it can be read at
/// all, its canonical text, its family and width, its bits one by one, its
/// classification, and what a block around it would be.
///
/// ```json
/// {"ok":true,"text":"192.0.2.1","family":"v4","bits":32,"binary":"...",
///  "exploded":"...","bytes":"01020304","reverse":"...","flags":[...]}
/// ```
pub fn probe(text : String) -> String {
  match read_addr(text) {
    None => "{\"ok\":false,\"error\":" + quote("not an address") + "}"
    Some(addr) => {
      let flags : Array[String] = []
      for
        row in [
          ("loopback", addr.is_loopback()),
          ("unspecified", addr.is_unspecified()),
          ("multicast", addr.is_multicast()),
          ("link local", addr.is_link_local()),
          ("site local", addr.is_site_local()),
          ("private", addr.is_private()),
          ("global", addr.is_global()),
          ("reserved", addr.is_reserved()),
        ] {
        if row.1 {
          flags.push(quote(row.0))
        }
      }
      let mut body = "{\"ok\":true"
      body = body + ",\"text\":" + quote(addr.to_string())
      body = body +
        ",\"family\":" +
        quote(if addr.is_v4() { "v4" } else { "v6" })
      body = body + ",\"bits\":" + addr.bits().to_string()
      body = body + ",\"binary\":" + quote(binary_of(addr.encode()))
      body = body + ",\"exploded\":" + quote(addr.exploded())
      body = body + ",\"bytes\":" + quote(hex_of(addr.encode(), true))
      body = body + ",\"reverse\":" + quote(addr.reverse_pointer())
      body = body + ",\"flags\":[" + join(flags) + "]"
      body + "}"
    }
  }
}

///|
/// The block `text` names, cut into blocks `bits` long, as a JSON array of text.
pub fn split(text : String, bits : Int32) -> String {
  match read_prefix(text) {
    None => error_json("that is not a block")
    Some(prefix) => {
      let parts : Array[String] = []
      let mut count = 0
      try {
        for part in prefix.subnets(bits~) {
          if count < 64 {
            parts.push(quote(part.to_string()))
          }
          count = count + 1
        }
      } catch {
        _ => return error_json("that length is outside the block")
      }
      "{\"ok\":true,\"count\":" +
      count.to_string() +
      ",\"parts\":[" +
      join(parts) +
      "]}"
    }
  }
}

///|
/// The fewest blocks holding every address from one to the other.
pub fn range(first : String, last : String) -> String {
  match (read_addr(first), read_addr(last)) {
    (Some(from), Some(to)) => {
      let parts : Array[String] = []
      try {
        for block in @moonip.summarize(from, to) {
          parts.push(quote(block.to_string()))
        }
      } catch {
        _ => return error_json("the range runs backwards")
      }
      "{\"ok\":true,\"parts\":[" + join(parts) + "]}"
    }
    _ => error_json("both ends have to be addresses")
  }
}

///|
/// The fewest blocks holding the same addresses as the ones given, separated by
/// commas.
pub fn merge(text : String) -> String {
  let blocks : Array[@moonip.Prefix] = []
  for piece in text.split(",") {
    let trimmed = piece.to_owned()
    let cleaned = trim(trimmed)
    if cleaned.length() == 0 {
      continue
    }
    match read_prefix(cleaned) {
      None => return error_json("not a block: " + cleaned)
      Some(prefix) => blocks.push(prefix)
    }
  }
  let merged = @moonip.collapse(blocks[:])
  let parts : Array[String] = []
  for block in merged {
    parts.push(quote(block.to_string()))
  }
  "{\"ok\":true,\"parts\":[" + join(parts) + "]}"
}

///|
fn error_json(message : String) -> String {
  "{\"ok\":false,\"error\":" + quote(message) + "}"
}

///|
fn read_addr(text : String) -> @moonip.Addr? {
  Some(@moonip.Addr::parse(text)) catch {
    _ => None
  }
}

///|
fn read_prefix(text : String) -> @moonip.Prefix? {
  Some(@moonip.Prefix::parse(text, strict=false)) catch {
    _ => None
  }
}

///|
fn trim(text : String) -> String {
  let n = text.length()
  let mut start = 0
  while start < n {
    let c = text.get_char(start).unwrap()
    if c == ' ' || c == '\t' || c == '\n' {
      start = start + 1
    } else {
      break
    }
  }
  let mut end = n
  while end > start {
    let c = text.get_char(end - 1).unwrap()
    if c == ' ' || c == '\t' || c == '\n' {
      end = end - 1
    } else {
      break
    }
  }
  let mut out = ""
  let mut i = start
  while i < end {
    out = out + text.get_char(i).unwrap().to_string()
    i = i + 1
  }
  out
}

///|
fn binary_of(bytes : Bytes) -> String {
  let mut out = ""
  for i = 0; i < bytes.length(); i = i + 1 {
    let value = bytes.at(i).to_int()
    let mut bit = 7
    while bit >= 0 {
      out = out + (if ((value >> bit) & 1) == 1 { "1" } else { "0" })
      bit = bit - 1
    }
  }
  out
}

///|
fn hex_of(bytes : Bytes, spaced : Bool) -> String {
  let digits = "0123456789abcdef"
  let mut out = ""
  for i = 0; i < bytes.length(); i = i + 1 {
    let value = bytes.at(i).to_int()
    if spaced && i > 0 {
      out = out + " "
    }
    out = out
    let high = digits.get_char(value >> 4).unwrap().to_string()
    let low = digits.get_char(value & 0xF).unwrap().to_string()
    out = out + high + low
  }
  out
}

///|
fn join(items : Array[String]) -> String {
  let mut out = ""
  let mut first = true
  for item in items {
    if !first {
      out = out + ","
    }
    first = false
    out = out + item
  }
  out
}

///|
fn quote(text : String) -> String {
  let escaped = texts_escape(text)
  "\"" + escaped + "\""
}

///|
fn texts_escape(text : String) -> String {
  let mut out = ""
  let mut i = 0
  while i < text.length() {
    let c = text.get_char(i).unwrap()
    if c == '"' {
      out = out + "\\\""
    } else if c == '\\' {
      out = out + "\\\\"
    } else if c == '\n' {
      out = out + "\\n"
    } else {
      out = out + c.to_string()
    }
    i = i + 1
  }
  out
}
