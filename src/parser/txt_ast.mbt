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
pub fn TxtNode::type_name(self : TxtNode) -> String {
  match self.kind {
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
fn TxtPosition::to_json_value(self : TxtPosition) -> Json {
  let obj : Map[String, Json] = Map([])
  obj["line"] = Json::number(self.line.to_double())
  obj["column"] = Json::number(self.column.to_double())
  Json::object(obj)
}

///|
fn TxtLocation::to_json_value(self : TxtLocation) -> Json {
  let obj : Map[String, Json] = Map([])
  obj["start"] = self.start.to_json_value()
  obj["end"] = self.end.to_json_value()
  Json::object(obj)
}

///|
fn children_to_json(children : Array[TxtNode]) -> Json {
  let arr : Array[Json] = Array(capacity=children.length())
  for child in children {
    arr.push(child.to_json())
  }
  Json::array(arr)
}

///|
/// Serialize this TxtNode tree into a Json value matching `@textlint/ast-node-types`.
pub fn TxtNode::to_json(self : TxtNode) -> Json {
  let obj : Map[String, Json] = Map([])
  obj["type"] = Json::string(self.type_name())
  match self.kind {
    Document(children)
    | Paragraph(children)
    | BlockQuote(children)
    | Table(children)
    | TableRow(children)
    | TableCell(children)
    | Emphasis(children)
    | Strong(children)
    | Delete(children) => obj["children"] = children_to_json(children)
    Header(depth~, children~) => {
      obj["depth"] = Json::number(depth.to_double())
      obj["children"] = children_to_json(children)
    }
    List(ordered~, start~, spread~, children~) => {
      obj["ordered"] = Json::boolean(ordered)
      match start {
        Some(n) => obj["start"] = Json::number(n.to_double())
        None => obj["start"] = Json::null()
      }
      obj["spread"] = Json::boolean(spread)
      obj["children"] = children_to_json(children)
    }
    ListItem(spread~, children~) => {
      obj["spread"] = Json::boolean(spread)
      obj["children"] = children_to_json(children)
    }
    CodeBlock(value~, lang~) => {
      obj["value"] = Json::string(value)
      match lang {
        Some(l) => obj["lang"] = Json::string(l)
        None => obj["lang"] = Json::null()
      }
    }
    HorizontalRule | Break => ()
    Comment(value~) | Str(value~) | Code(value~) =>
      obj["value"] = Json::string(value)
    Link(url~, title~, children~) => {
      obj["url"] = Json::string(url)
      match title {
        Some(t) => obj["title"] = Json::string(t)
        None => obj["title"] = Json::null()
      }
      obj["children"] = children_to_json(children)
    }
    Image(url~, alt~, title~) => {
      obj["url"] = Json::string(url)
      match alt {
        Some(a) => obj["alt"] = Json::string(a)
        None => obj["alt"] = Json::null()
      }
      match title {
        Some(t) => obj["title"] = Json::string(t)
        None => obj["title"] = Json::null()
      }
    }
  }
  obj["raw"] = Json::string(self.raw)
  obj["range"] = Json::array([
    Json::number(self.range_start.to_double()),
    Json::number(self.range_end.to_double()),
  ])
  obj["loc"] = self.loc.to_json_value()
  Json::object(obj)
}
