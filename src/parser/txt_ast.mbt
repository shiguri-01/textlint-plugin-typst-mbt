///|
/// Specific variant and payload of a textlint TxtAST node.
#derive(Eq, Debug)
pub(all) enum TxtNodeKind {
  Document(Array[TxtNode])
  Paragraph(Array[TxtNode])
  Header(depth~ : Int32, children~ : Array[TxtNode])
  BlockQuote(Array[TxtNode])
  List(
    ordered~ : Bool,
    start~ : Int32?,
    spread~ : Bool,
    children~ : Array[TxtNode],
  )
  ListItem(spread~ : Bool, children~ : Array[TxtNode])
  Table(Array[TxtNode])
  TableRow(Array[TxtNode])
  TableCell(Array[TxtNode])
  CodeBlock(value~ : String, lang~ : String?)
  HorizontalRule
  Comment(value~ : String)
  Str(value~ : String)
  Break
  Emphasis(Array[TxtNode])
  Strong(Array[TxtNode])
  Delete(Array[TxtNode])
  Code(value~ : String)
  Link(url~ : String, title~ : String?, children~ : Array[TxtNode])
  Image(url~ : String, alt~ : String?, title~ : String?)
}

///|
/// Return the TxtAST node type name for this kind.
pub fn TxtNodeKind::type_name(self : Self) -> String {
  match self {
    Document(_) => "Document"
    Paragraph(_) => "Paragraph"
    Header(..) => "Header"
    BlockQuote(_) => "BlockQuote"
    List(..) => "List"
    ListItem(..) => "ListItem"
    Table(_) => "Table"
    TableRow(_) => "TableRow"
    TableCell(_) => "TableCell"
    CodeBlock(..) => "CodeBlock"
    HorizontalRule => "HorizontalRule"
    Comment(..) => "Comment"
    Str(..) => "Str"
    Break => "Break"
    Emphasis(_) => "Emphasis"
    Strong(_) => "Strong"
    Delete(_) => "Delete"
    Code(..) => "Code"
    Link(..) => "Link"
    Image(..) => "Image"
  }
}

///|
/// A textlint TxtAST node with exact UTF-16 range, location, and raw slice.
#derive(Eq, Debug)
pub(all) struct TxtNode {
  kind : TxtNodeKind
  raw : String
  range_start : Int32
  range_end : Int32
  loc : TxtLocation
}

///|
/// Return the TxtAST node type name.
pub fn TxtNode::type_name(self : Self) -> String {
  self.kind.type_name()
}

///|
fn[T : ToJson] opt_to_json(opt : T?) -> Json {
  match opt {
    Some(v) => ToJson::to_json(v)
    None => Json::null()
  }
}

///|
/// Serialize this TxtNode tree into a Json value matching `@textlint/ast-node-types`.
pub impl ToJson for TxtNode with fn to_json(self) {
  let obj : Map[String, Json] = { "type": ToJson::to_json(self.type_name()) }
  match self.kind {
    Document(children)
    | Paragraph(children)
    | BlockQuote(children)
    | Table(children)
    | TableRow(children)
    | TableCell(children)
    | Emphasis(children)
    | Strong(children)
    | Delete(children) => obj["children"] = ToJson::to_json(children)
    Header(depth~, children~) => {
      obj["depth"] = ToJson::to_json(depth)
      obj["children"] = ToJson::to_json(children)
    }
    List(ordered~, start~, spread~, children~) => {
      obj["ordered"] = ToJson::to_json(ordered)
      obj["start"] = opt_to_json(start)
      obj["spread"] = ToJson::to_json(spread)
      obj["children"] = ToJson::to_json(children)
    }
    ListItem(spread~, children~) => {
      obj["spread"] = ToJson::to_json(spread)
      obj["children"] = ToJson::to_json(children)
    }
    CodeBlock(value~, lang~) => {
      obj["value"] = ToJson::to_json(value)
      obj["lang"] = opt_to_json(lang)
    }
    HorizontalRule | Break => ()
    Comment(value~) | Str(value~) | Code(value~) =>
      obj["value"] = ToJson::to_json(value)
    Link(url~, title~, children~) => {
      obj["url"] = ToJson::to_json(url)
      obj["title"] = opt_to_json(title)
      obj["children"] = ToJson::to_json(children)
    }
    Image(url~, alt~, title~) => {
      obj["url"] = ToJson::to_json(url)
      obj["alt"] = opt_to_json(alt)
      obj["title"] = opt_to_json(title)
    }
  }
  obj["raw"] = ToJson::to_json(self.raw)
  obj["range"] = ToJson::to_json([self.range_start, self.range_end])
  obj["loc"] = self.loc.to_json()
  Json::object(obj)
}

///|
pub extend TxtNode with ToJson::{to_json}
