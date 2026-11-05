///|
/// Why a text form, a byte string or an argument pair was refused.
///
/// Every call that can refuse reports one of these rather than a boolean, so the
/// caller can tell a typo from a number that was merely too large.
pub(all) suberror Refused {
  /// The input stopped making sense at character `at`, counted from 0.
  Malformed(at~ : Int32)
  /// A number did not fit: `got` was more than `limit`.
  OutOfRange(limit~ : Int32, got~ : Int32)
  /// A byte string was the wrong size: `got` bytes where exactly `want` are needed.
  Length(want~ : Int32, got~ : Int32)
  /// A prefix was written with bits set below its mask while `strict` forbade it.
  HostBits
  /// The two arguments were of different families, IPv4 against IPv6.
  Family
  /// A range ended before it began.
  Reversed
}

///|
pub impl Show for Refused with fn to_string(self) {
  match self {
    Malformed(at~) => "malformed at " + at.to_string()
    OutOfRange(limit~, got~) =>
      got.to_string() + " out of range, at most " + limit.to_string()
    Length(want~, got~) =>
      got.to_string() + " bytes, want exactly " + want.to_string()
    HostBits => "host bits set below the prefix mask"
    Family => "IPv4 and IPv6 do not mix here"
    Reversed => "the range ends before it starts"
  }
}

///|
pub extend Refused with Show::{to_string, output}
