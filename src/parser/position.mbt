///|
/// A 1-based line and 0-based UTF-16 column position compatible with TxtAST.
#derive(Eq, Debug)
pub(all) struct TxtPosition {
  line : Int32
  column : Int32
}

///|
/// A start/end source location compatible with TxtAST.
#derive(Eq, Debug)
pub(all) struct TxtLocation {
  start : TxtPosition
  end : TxtPosition
}

///|
/// Line start offset table in UTF-16 code units.
/// Matches `@textlint/ast-tester` line ending rules (LF, CR, CRLF).
pub struct LineIndex {
  priv starts : Array[Int32]
}

///|
/// Build a line index from source text using LF, CR, and CRLF boundaries.
pub fn LineIndex::new(text : String) -> LineIndex {
  let starts : Array[Int32] = [0]
  let len = text.length()
  let mut i = 0
  while i < len {
    let c = text.code_unit_at(i).to_int()
    if c == 10 {
      starts.push(i + 1)
      i += 1
    } else if c == 13 {
      if i + 1 < len && text.code_unit_at(i + 1).to_int() == 10 {
        i += 2
      } else {
        i += 1
      }
      starts.push(i)
    } else {
      i += 1
    }
  }
  { starts, }
}

///|
/// Convert a 0-based UTF-16 code unit offset into a TxtPosition.
pub fn LineIndex::position_of(self : LineIndex, offset : Int32) -> TxtPosition {
  let mut lo = 0
  let mut hi = self.starts.length() - 1
  while lo < hi {
    let mid = (lo + hi + 1) >> 1
    if self.starts[mid] <= offset {
      lo = mid
    } else {
      hi = mid - 1
    }
  }
  { line: lo + 1, column: offset - self.starts[lo], }
}

///|
/// Convert a UTF-16 offset range [start, end) into a TxtLocation.
pub fn LineIndex::location_of(
  self : LineIndex,
  start : Int32,
  end : Int32,
) -> TxtLocation {
  { start: self.position_of(start), end: self.position_of(end), }
}
