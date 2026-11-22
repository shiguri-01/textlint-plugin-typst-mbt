///|
/// Opaque JavaScript value returned directly to JS callers without JSON serialization.
#external
pub type JsValue

///|
extern "js" fn js_null() -> JsValue =
  #| () => null

///|
extern "js" fn js_string(s : String) -> JsValue =
  #| (s) => s

///|
extern "js" fn js_int(n : Int32) -> JsValue =
  #| (n) => n

///|
extern "js" fn js_empty_array() -> JsValue =
  #| () => []

///|
extern "js" fn js_array_push(arr : JsValue, item : JsValue) -> Unit =
  #| (arr, item) => { arr.push(item); }

///|
extern "js" fn js_make_loc(
  start_line : Int32,
  start_col : Int32,
  end_line : Int32,
  end_col : Int32,
) -> JsValue =
  #| (sl, sc, el, ec) => ({ start: { line: sl, column: sc }, end: { line: el, column: ec } })

///|
extern "js" fn js_make_parent_node(
  type_name : String,
  children : JsValue,
  raw : String,
  range_start : Int32,
  range_end : Int32,
  loc : JsValue,
) -> JsValue =
  #| (type, children, raw, rs, re, loc) => ({ type, children, raw, range: [rs, re], loc })

///|
extern "js" fn js_make_header_node(
  depth : Int32,
  children : JsValue,
  raw : String,
  range_start : Int32,
  range_end : Int32,
  loc : JsValue,
) -> JsValue =
  #| (depth, children, raw, rs, re, loc) => ({ type: "Header", depth, children, raw, range: [rs, re], loc })

///|
extern "js" fn js_make_list_node(
  ordered : Bool,
  start : JsValue,
  spread : Bool,
  children : JsValue,
  raw : String,
  range_start : Int32,
  range_end : Int32,
  loc : JsValue,
) -> JsValue =
  #| (ordered, start, spread, children, raw, rs, re, loc) => ({ type: "List", ordered, start, spread, children, raw, range: [rs, re], loc })

///|
extern "js" fn js_make_list_item_node(
  spread : Bool,
  children : JsValue,
  raw : String,
  range_start : Int32,
  range_end : Int32,
  loc : JsValue,
) -> JsValue =
  #| (spread, children, raw, rs, re, loc) => ({ type: "ListItem", spread, children, raw, range: [rs, re], loc })

///|
extern "js" fn js_make_code_block_node(
  value : String,
  lang : JsValue,
  raw : String,
  range_start : Int32,
  range_end : Int32,
  loc : JsValue,
) -> JsValue =
  #| (value, lang, raw, rs, re, loc) => ({ type: "CodeBlock", value, lang, raw, range: [rs, re], loc })

///|
extern "js" fn js_make_text_node(
  type_name : String,
  value : String,
  raw : String,
  range_start : Int32,
  range_end : Int32,
  loc : JsValue,
) -> JsValue =
  #| (type, value, raw, rs, re, loc) => ({ type, value, raw, range: [rs, re], loc })

///|
extern "js" fn js_make_leaf_node(
  type_name : String,
  raw : String,
  range_start : Int32,
  range_end : Int32,
  loc : JsValue,
) -> JsValue =
  #| (type, raw, rs, re, loc) => ({ type, raw, range: [rs, re], loc })

///|
extern "js" fn js_make_link_node(
  url : String,
  title : JsValue,
  children : JsValue,
  raw : String,
  range_start : Int32,
  range_end : Int32,
  loc : JsValue,
) -> JsValue =
  #| (url, title, children, raw, rs, re, loc) => ({ type: "Link", url, title, children, raw, range: [rs, re], loc })

///|
extern "js" fn js_make_image_node(
  url : String,
  alt : JsValue,
  title : JsValue,
  raw : String,
  range_start : Int32,
  range_end : Int32,
  loc : JsValue,
) -> JsValue =
  #| (url, alt, title, raw, rs, re, loc) => ({ type: "Image", url, alt, title, raw, range: [rs, re], loc })

///|
fn TxtLocation::to_js(self : Self) -> JsValue {
  js_make_loc(
    self.start.line,
    self.start.column,
    self.end.line,
    self.end.column,
  )
}

///|
fn children_to_js(children : Array[TxtNode]) -> JsValue {
  let arr = js_empty_array()
  for child in children {
    js_array_push(arr, child.to_js())
  }
  arr
}

///|
/// Convert a TxtNode tree directly into native JS objects matching `@textlint/ast-node-types`.
pub fn TxtNode::to_js(self : Self) -> JsValue {
  let loc = self.loc.to_js()
  match self.kind {
    Document(children)
    | Paragraph(children)
    | BlockQuote(children)
    | Table(children)
    | TableRow(children)
    | TableCell(children)
    | Emphasis(children)
    | Strong(children)
    | Delete(children) =>
      js_make_parent_node(
        self.type_name(),
        children_to_js(children),
        self.raw,
        self.range_start,
        self.range_end,
        loc,
      )
    Header(depth~, children~) =>
      js_make_header_node(
        depth,
        children_to_js(children),
        self.raw,
        self.range_start,
        self.range_end,
        loc,
      )
    List(ordered~, start~, spread~, children~) =>
      js_make_list_node(
        ordered,
        start.map_or(js_null(), js_int),
        spread,
        children_to_js(children),
        self.raw,
        self.range_start,
        self.range_end,
        loc,
      )
    ListItem(spread~, children~) =>
      js_make_list_item_node(
        spread,
        children_to_js(children),
        self.raw,
        self.range_start,
        self.range_end,
        loc,
      )
    CodeBlock(value~, lang~) =>
      js_make_code_block_node(
        value,
        lang.map_or(js_null(), js_string),
        self.raw,
        self.range_start,
        self.range_end,
        loc,
      )
    HorizontalRule | Break =>
      js_make_leaf_node(
        self.type_name(),
        self.raw,
        self.range_start,
        self.range_end,
        loc,
      )
    Comment(value~) | Str(value~) | Code(value~) =>
      js_make_text_node(
        self.type_name(),
        value,
        self.raw,
        self.range_start,
        self.range_end,
        loc,
      )
    Link(url~, title~, children~) =>
      js_make_link_node(
        url,
        title.map_or(js_null(), js_string),
        children_to_js(children),
        self.raw,
        self.range_start,
        self.range_end,
        loc,
      )
    Image(url~, alt~, title~) =>
      js_make_image_node(
        url,
        alt.map_or(js_null(), js_string),
        title.map_or(js_null(), js_string),
        self.raw,
        self.range_start,
        self.range_end,
        loc,
      )
  }
}

///|
/// Parse Typst source text directly into a native JS TxtAST object (no JSON serialization).
pub fn parse_to_txt_ast(text : String) -> JsValue {
  parse_typst_to_txt_ast(text).to_js()
}
