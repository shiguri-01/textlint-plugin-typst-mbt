///|
fn @syntax.SyntaxKind::is_space(self : @syntax.SyntaxKind) -> Bool {
  self is (SpaceNoNewline | SpaceWithNewline)
}

///|
fn @syntax.SyntaxKind::is_stmt_expr(self : @syntax.SyntaxKind) -> Bool {
  self
  is (LetBinding
  | SetRule
  | ShowRule
  | ModuleImport
  | ModuleInclude
  | CodeBlock)
}

///|
fn @syntax.SyntaxKind::is_control_expr(self : @syntax.SyntaxKind) -> Bool {
  self is (Conditional | ForLoop | WhileLoop | Contextual)
}

///|
/// A Typst CST node paired with exact UTF-16 code unit [start, end) offsets.
priv struct SpannedNode {
  node : @syntax.SyntaxNode
  start : Int32
  end : Int32
  children : Array[SpannedNode]
}

///|
fn SpannedNode::from_cst(root : @syntax.SyntaxNode) -> Self {
  let mut cursor : Int32 = 0
  fn go(node : @syntax.SyntaxNode) -> SpannedNode {
    let start = cursor
    if node.is_inner() {
      let children = [ for child in node.children() => go(child) ]
      { node, start, end: cursor, children, }
    } else {
      cursor += node.full_text().length()
      { node, start, end: cursor, children: [], }
    }
  }

  go(root)
}

///|
fn SpannedNode::kind(self : Self) -> @syntax.SyntaxKind {
  self.node.kind()
}

///|
fn SpannedNode::is_raw_block(self : Self) -> Bool {
  (@ast.Raw::from_untyped(self.node) : @ast.Raw?).map_or(false, fn(raw) {
    raw.block()
  })
}

///|
fn SpannedNode::is_display_equation(self : Self) -> Bool {
  guard self.kind() is Equation else { false }
  guard self.children.length() >= 3 else { false }
  // Typst display equation has space right after opening `$` and before closing `$`.
  guard self.children is [_, first, ..] && self.children is [.., last, _] else {
    false
  }
  first.kind().is_space() && last.kind().is_space()
}

///|
fn SpannedNode::raw_value_and_lang(self : Self) -> (String, String?) {
  let lang = match (@ast.Raw::from_untyped(self.node) : @ast.Raw?) {
    Some(raw) => raw.lang().map(fn(l) { l.get() })
    None => None
  }
  let buf = StringBuilder()
  let mut first = true
  for child in self.children {
    if child.kind() is Text {
      if !first {
        buf.write_char('\n')
      }
      buf.write_string(child.node.leaf_text())
      first = false
    }
  }
  (buf.to_string(), lang)
}

///|
fn SpannedNode::equation_value(self : Self) -> String {
  let buf = StringBuilder()
  for child in self.children {
    if !(child.kind() is Dollar) {
      buf.write_string(child.node.full_text())
    }
  }
  buf.to_string().trim().to_owned()
}

///|
fn SpannedNode::comment_value(self : Self) -> String {
  match self.kind() {
    LineComment =>
      (@ast.LineComment::from_untyped(self.node) : @ast.LineComment?).map_or_else(
        fn() { self.node.leaf_text() },
        fn(c) { c.text() },
      )
    BlockComment =>
      (@ast.BlockComment::from_untyped(self.node) : @ast.BlockComment?).map_or_else(
        fn() { self.node.leaf_text() },
        fn(c) { c.text() },
      )
    _ => self.node.full_text()
  }
}

///|
fn SpannedNode::func_callee_name(self : Self) -> String? {
  for child in self.children {
    match child.kind() {
      Ident => break Some(child.node.leaf_text())
      FieldAccess => break Some(child.node.full_text())
      _ => ()
    }
  } nobreak {
    None
  }
}

///|
fn SpannedNode::func_args(self : Self) -> Self? {
  for child in self.children {
    if child.kind() is Args {
      break Some(child)
    }
  } nobreak {
    None
  }
}

///|
fn SpannedNode::str_literal(self : Self) -> String? {
  guard self.kind() is Str else { None }
  Some(@syntax.unescape_str_literal(self.node.leaf_text()))
}

///|
fn SpannedNode::int_literal(self : Self) -> Int32? {
  guard self.kind() is Int else { None }
  let text = self.node.leaf_text()
  let mut acc : Int32 = 0
  let mut has_digit = false
  for c in text {
    match c {
      '0'..<='9' => {
        acc = acc * 10 + (c.to_int() - '0'.to_int())
        has_digit = true
      }
      _ => return None
    }
  }
  if has_digit {
    Some(acc)
  } else {
    None
  }
}

///|
fn SpannedNode::bool_literal(self : Self) -> Bool? {
  guard self.kind() is Bool else { None }
  match self.node.leaf_text() {
    "true" => Some(true)
    "false" => Some(false)
    _ => None
  }
}

///|
fn SpannedNode::named_entry(self : Self) -> (String, Self)? {
  guard self.kind() is Named else { None }
  let mut key : String? = None
  let mut val : SpannedNode? = None
  for nc in self.children {
    let k = nc.kind()
    if key is None && k is Ident {
      key = Some(nc.node.leaf_text())
    } else if key is Some(_) && !k.is_trivia() && !(k is Colon) {
      val = Some(nc)
    }
  }
  match (key, val) {
    (Some(k), Some(v)) => Some((k, v))
    _ => None
  }
}

///|
fn SpannedNode::named_arg(self : Self, name : String) -> Self? {
  for child in self.children {
    if child.named_entry() is Some((k, v)) && k == name {
      break Some(v)
    }
  } nobreak {
    None
  }
}

///|
/// Return footnote body argument expressions that contain a ContentBlock,
/// excluding non-body named arguments such as `numbering` and label references.
fn SpannedNode::footnote_body_args(self : Self) -> Array[Self] {
  guard self.func_args() is Some(args) else { [] }
  let out : Array[SpannedNode] = []
  for child in args.children {
    if child.kind().is_positional_arg() {
      if child.has_content_block() {
        out.push(child)
      }
    } else if child.named_entry() is Some(("body", val)) &&
      val.has_content_block() {
      out.push(val)
    }
  }
  out
}

///|
fn @syntax.SyntaxKind::is_positional_arg(self : @syntax.SyntaxKind) -> Bool {
  !self.is_trivia() &&
  !(self is (LeftParen | RightParen | Comma | Named | Spread))
}

///|
fn SpannedNode::positional_args(self : Self) -> Array[Self] {
  [
    for child in self.children if child.kind().is_positional_arg() => child
  ]
}

///|
/// Collect all ContentBlock nodes inside a FuncCall's Args in source order.
fn SpannedNode::content_blocks(self : Self) -> Array[Self] {
  let out : Array[SpannedNode] = []
  for child in self.children {
    match child.kind() {
      ContentBlock => out.push(child)
      Named =>
        for nc in child.children {
          if nc.kind() is ContentBlock {
            out.push(nc)
          }
        }
      _ => ()
    }
  }
  out
}

///|
fn SpannedNode::markup_child(self : Self) -> Self? {
  for child in self.children {
    if child.kind() is Markup {
      break Some(child)
    }
  } nobreak {
    None
  }
}

///|
fn SpannedNode::has_content_block(self : Self) -> Bool {
  if self.kind() is ContentBlock {
    return true
  }
  for child in self.children {
    if child.has_content_block() {
      break true
    }
  } nobreak {
    false
  }
}

///|
fn SpannedNode::is_raw_func_block(self : Self) -> Bool {
  guard self.func_args() is Some(args) else { false }
  guard args.named_arg("block") is Some(b) else { false }
  b.bool_literal().unwrap_or(false)
}

///|
priv struct Converter {
  source : String
  lines : LineIndex
}

///|
fn Converter::new(source : String) -> Self {
  { source, lines: LineIndex::new(source), }
}

///|
fn Converter::slice(self : Self, start : Int32, end : Int32) -> String {
  self.source.unsafe_substring(start~, end~)
}

///|
fn Converter::make_node(
  self : Self,
  kind : TxtNodeKind,
  start : Int32,
  end : Int32,
) -> TxtNode {
  {
    kind,
    raw: self.slice(start, end),
    range_start: start,
    range_end: end,
    loc: self.lines.location_of(start, end),
  }
}

///|
/// Parsed unit in a Markup child list (pairs a `#` with its following expression).
priv enum MarkupItem {
  Single(SpannedNode)
  Hashed(hash~ : SpannedNode, expr~ : SpannedNode, end~ : Int32)
}

///|
fn MarkupItem::start(self : Self) -> Int32 {
  match self {
    Single(n) => n.start
    Hashed(hash~, ..) => hash.start
  }
}

///|
fn MarkupItem::end(self : Self) -> Int32 {
  match self {
    Single(n) => n.end
    Hashed(end~, ..) => end
  }
}

///|
fn MarkupItem::is_space(self : Self) -> Bool {
  self is Single(n) && n.kind().is_space()
}

///|
fn group_markup_items(nodes : Array[SpannedNode]) -> Array[MarkupItem] {
  let items : Array[MarkupItem] = []
  let len = nodes.length()
  let mut i = 0
  while i < len {
    let cur = nodes[i]
    if cur.kind() is Hash && i + 1 < len {
      let expr = nodes[i + 1]
      let mut end = expr.end
      let mut next_i = i + 2
      if next_i < len && nodes[next_i].kind() is Semicolon {
        end = nodes[next_i].end
        next_i += 1
      }
      items.push(Hashed(hash=cur, expr~, end~))
      i = next_i
    } else {
      items.push(Single(cur))
      i += 1
    }
  }
  items
}

///|
fn is_block_func_name(name : String) -> Bool {
  name
  is ("heading"
  | "quote"
  | "line"
  | "table"
  | "figure"
  | "block"
  | "align"
  | "pad"
  | "rect"
  | "grid"
  | "columns"
  | "stack"
  | "place"
  | "pagebreak"
  | "parbreak")
}

///|
fn is_inline_only_func_name(name : String) -> Bool {
  name
  is ("strong"
  | "emph"
  | "strike"
  | "underline"
  | "overline"
  | "highlight"
  | "smallcaps"
  | "sub"
  | "super"
  | "link"
  | "image"
  | "text"
  | "cite"
  | "ref"
  | "h"
  | "box")
}

///|
fn is_only_whitespace_items(items : Array[MarkupItem]) -> Bool {
  for item in items {
    if !item.is_space() {
      break false
    }
  } nobreak {
    true
  }
}

///|
fn ends_with_newline_item(items : Array[MarkupItem]) -> Bool {
  items is [.., Single(n)] && n.kind() is SpaceWithNewline
}

///|
fn is_followed_by_same_line_inline(
  items : Array[MarkupItem],
  idx : Int32,
) -> Bool {
  for item in items[idx + 1:] {
    match item {
      Single(n) =>
        match n.kind() {
          SpaceNoNewline => ()
          SpaceWithNewline | Parbreak | LineComment | BlockComment =>
            break false
          _ => break true
        }
      Hashed(..) => break true
    }
  } nobreak {
    false
  }
}

///|
/// Convert a Typst `Markup` node's children into block-level TxtAST nodes.
fn Converter::convert_markup_blocks(
  self : Self,
  nodes : Array[SpannedNode],
) -> Array[TxtNode] {
  let items = group_markup_items(nodes)
  let blocks : Array[TxtNode] = []
  let inline_buf : Array[MarkupItem] = []

  fn flush_paragraph() -> Unit {
    if !inline_buf.is_empty() {
      if self.build_paragraph(inline_buf) is Some(p) {
        blocks.push(p)
      }
      inline_buf.clear()
    }
  }

  let len = items.length()
  let mut i = 0
  while i < len {
    let item = items[i]
    match item {
      Single(node) =>
        match node.kind() {
          Parbreak | Shebang => {
            flush_paragraph()
            i += 1
          }
          Heading => {
            flush_paragraph()
            blocks.push(self.convert_heading(node))
            i += 1
          }
          ListItem | EnumItem | TermItem as item_kind => {
            flush_paragraph()
            let (list_node, next_i) = self.consume_list(items, i, item_kind)
            blocks.push(list_node)
            i = next_i
          }
          Raw if node.is_raw_block() => {
            flush_paragraph()
            let (value, lang) = node.raw_value_and_lang()
            blocks.push(
              self.make_node(CodeBlock(value~, lang~), node.start, node.end),
            )
            i += 1
          }
          Equation if node.is_display_equation() &&
            is_only_whitespace_items(inline_buf) => {
            flush_paragraph()
            let value = node.equation_value()
            blocks.push(
              self.make_node(
                CodeBlock(value~, lang=Some("math")),
                node.start,
                node.end,
              ),
            )
            i += 1
          }
          LineComment | BlockComment if is_only_whitespace_items(inline_buf) ||
            ends_with_newline_item(inline_buf) => {
            flush_paragraph()
            let value = node.comment_value()
            blocks.push(self.make_node(Comment(value~), node.start, node.end))
            i += 1
          }
          _ => {
            inline_buf.push(item)
            i += 1
          }
        }
      Hashed(hash~, expr~, end~) => {
        let ek = expr.kind()
        if ek.is_stmt_expr() && is_only_whitespace_items(inline_buf) {
          inline_buf.clear()
          let value = self.slice(hash.start, end)
          blocks.push(
            self.make_node(
              CodeBlock(value~, lang=Some("typst")),
              hash.start,
              end,
            ),
          )
          i += 1
        } else if ek is ContentBlock && is_only_whitespace_items(inline_buf) {
          inline_buf.clear()
          if expr.markup_child() is Some(markup) {
            blocks.append(self.convert_markup_blocks(markup.children))
          }
          i += 1
        } else if ek.is_control_expr() &&
          is_only_whitespace_items(inline_buf) &&
          !is_followed_by_same_line_inline(items, i) {
          inline_buf.clear()
          if expr.has_content_block() {
            self.extract_blocks_from_expr(expr, blocks)
          } else {
            let value = self.slice(hash.start, end)
            blocks.push(
              self.make_node(
                CodeBlock(value~, lang=Some("typst")),
                hash.start,
                end,
              ),
            )
          }
          i += 1
        } else if ek is FuncCall && expr.func_callee_name() is Some("footnote") {
          let body_args = expr.footnote_body_args()
          if body_args.is_empty() {
            inline_buf.push(item)
          } else {
            // Footnote prose is independent of the host sentence; emit its body as
            // separate block(s) so host and footnote Paragraphs keep contiguous ranges.
            // Mid-sentence footnotes intentionally split the surrounding Paragraph
            // to satisfy TxtAST's single contiguous range invariant.
            flush_paragraph()
            for body_arg in body_args {
              self.extract_blocks_from_expr(body_arg, blocks)
            }
          }
          i += 1
        } else if ek is FuncCall && is_only_whitespace_items(inline_buf) {
          match expr.func_callee_name() {
            Some("raw") if expr.is_raw_func_block() => {
              inline_buf.clear()
              blocks.append(
                self.convert_block_func_call("raw", expr, hash.start, end),
              )
              i += 1
            }
            Some(name) if is_block_func_name(name) => {
              inline_buf.clear()
              blocks.append(
                self.convert_block_func_call(name, expr, hash.start, end),
              )
              i += 1
            }
            Some(name) if !is_inline_only_func_name(name) &&
              !is_followed_by_same_line_inline(items, i) &&
              expr.has_content_block() => {
              inline_buf.clear()
              self.extract_blocks_from_expr(expr, blocks)
              i += 1
            }
            _ => {
              inline_buf.push(item)
              i += 1
            }
          }
        } else {
          inline_buf.push(item)
          i += 1
        }
      }
    }
  }
  flush_paragraph()
  blocks
}

///|
fn Converter::convert_heading(self : Self, heading : SpannedNode) -> TxtNode {
  let raw_depth = (@ast.Heading::from_untyped(heading.node) : @ast.Heading?).map_or(
    1,
    fn(h) { h.depth() },
  )
  let depth = raw_depth.clamp(min=1, max=6)
  let children = match heading.markup_child() {
    Some(markup) => self.convert_inline_nodes(markup.children)
    None => []
  }
  self.make_node(Header(depth~, children~), heading.start, heading.end)
}

///|
fn Converter::consume_list(
  self : Self,
  items : Array[MarkupItem],
  start_idx : Int32,
  item_kind : @syntax.SyntaxKind,
) -> (TxtNode, Int32) {
  let list_items : Array[TxtNode] = []
  let mut spread = false
  let mut i = start_idx
  let mut last_item_end = items[start_idx].end()
  let mut first_enum_start : Int32? = None
  let len = items.length()
  while i < len {
    guard items[i] is Single(node) && node.kind() == item_kind else { break }
    if item_kind is EnumItem && list_items.is_empty() {
      let start_num = match
        (@ast.EnumItem::from_untyped(node.node) : @ast.EnumItem?) {
        Some(ei) => ei.number().map_or(1, fn(n) { n.to_int() })
        None => 1
      }
      first_enum_start = Some(start_num)
    }
    list_items.push(self.convert_list_item(node, item_kind))
    last_item_end = node.end
    i += 1
    // Look ahead over spaces/parbreaks to see if another item of the same kind follows.
    let mut j = i
    let mut saw_parbreak = false
    while j < len {
      match items[j] {
        Single(s) if s.kind().is_space() => j += 1
        Single(s) if s.kind() is Parbreak => {
          saw_parbreak = true
          j += 1
        }
        _ => break
      }
    }
    if j < len && items[j] is Single(next_node) && next_node.kind() == item_kind {
      if saw_parbreak {
        spread = true
      }
      i = j
    } else {
      break
    }
  }
  let ordered = item_kind is EnumItem
  let list_start = items[start_idx].start()
  let list_node = self.make_node(
    List(ordered~, start=first_enum_start, spread~, children=list_items),
    list_start,
    last_item_end,
  )
  (list_node, i)
}

///|
fn Converter::convert_list_item(
  self : Self,
  node : SpannedNode,
  item_kind : @syntax.SyntaxKind,
) -> TxtNode {
  let children : Array[TxtNode] = []
  match item_kind {
    TermItem =>
      // TermItem has two Markup children: term and description.
      for child in node.children {
        if child.kind() is Markup {
          children.append(self.convert_markup_blocks(child.children))
        }
      }
    _ =>
      if node.markup_child() is Some(markup) {
        children.append(self.convert_markup_blocks(markup.children))
      }
  }
  let spread = children.length() > 1
  self.make_node(ListItem(spread~, children~), node.start, node.end)
}

///|
fn Converter::convert_block_func_call(
  self : Self,
  name : String,
  func_call : SpannedNode,
  start : Int32,
  end : Int32,
) -> Array[TxtNode] {
  match name {
    "line" => [self.make_node(HorizontalRule, start, end)]
    "pagebreak" | "parbreak" => []
    "heading" => {
      let mut depth = 1
      let mut body_children : Array[TxtNode] = []
      if func_call.func_args() is Some(args) {
        if args.named_arg("level") is Some(lvl_node) &&
          lvl_node.int_literal() is Some(n) {
          depth = n.clamp(min=1, max=6)
        }
        if args.content_blocks() is [first_cb, ..] &&
          first_cb.markup_child() is Some(markup) {
          body_children = self.convert_inline_nodes(markup.children)
        }
      }
      [self.make_node(Header(depth~, children=body_children), start, end)]
    }
    "quote" => {
      let body_blocks : Array[TxtNode] = []
      if func_call.func_args() is Some(args) {
        for cb in args.content_blocks() {
          if cb.markup_child() is Some(markup) {
            body_blocks.append(self.convert_markup_blocks(markup.children))
          }
        }
      }
      [self.make_node(BlockQuote(body_blocks), start, end)]
    }
    "raw" => {
      let mut value = ""
      let mut lang : String? = None
      if func_call.func_args() is Some(args) {
        if args.positional_args() is [first_arg, ..] &&
          first_arg.str_literal() is Some(s) {
          value = s
        }
        if args.named_arg("lang") is Some(lang_node) {
          lang = lang_node.str_literal()
        }
      }
      [self.make_node(CodeBlock(value~, lang~), start, end)]
    }
    "table" => {
      guard func_call.func_args() is Some(args) else { [] }
      let mut col_count = 1
      if args.named_arg("columns") is Some(cols_node) {
        match cols_node.int_literal() {
          Some(n) if n > 0 => col_count = n
          _ =>
            if cols_node.kind() is Array {
              let count = cols_node.positional_args().length()
              if count > 0 {
                col_count = count
              }
            }
        }
      }
      let cells : Array[TxtNode] = []
      self.collect_table_cells(args, cells)
      guard !cells.is_empty() else { [] }
      let rows : Array[TxtNode] = []
      let mut idx = 0
      while idx < cells.length() {
        let row_cells : Array[TxtNode] = []
        let row_start = cells[idx].range_start
        let mut row_end = cells[idx].range_end
        let mut c = 0
        while c < col_count && idx < cells.length() {
          let cell = cells[idx]
          row_cells.push(cell)
          row_end = cell.range_end
          idx += 1
          c += 1
        }
        rows.push(self.make_node(TableRow(row_cells), row_start, row_end))
      }
      [self.make_node(Table(rows), start, end)]
    }
    _ => {
      // Container functions (figure, block, align, pad, rect, grid, columns, etc.):
      // Recursively extract blocks from arguments in source order.
      let out : Array[TxtNode] = []
      if func_call.func_args() is Some(args) {
        self.extract_blocks_from_expr(args, out)
      }
      out
    }
  }
}

///|
fn Converter::collect_table_cells(
  self : Self,
  args : SpannedNode,
  cells : Array[TxtNode],
) -> Unit {
  for arg in args.positional_args() {
    match arg.kind() {
      ContentBlock => {
        let cell_children = match arg.markup_child() {
          Some(markup) => self.convert_inline_nodes(markup.children)
          None => []
        }
        cells.push(self.make_node(TableCell(cell_children), arg.start, arg.end))
      }
      FuncCall =>
        match arg.func_callee_name() {
          Some("table.header") | Some("table.footer") =>
            if arg.func_args() is Some(sub_args) {
              self.collect_table_cells(sub_args, cells)
            }
          Some("table.cell") =>
            if arg.func_args() is Some(sub_args) {
              for cb in sub_args.content_blocks() {
                let cell_children = match cb.markup_child() {
                  Some(markup) => self.convert_inline_nodes(markup.children)
                  None => []
                }
                cells.push(
                  self.make_node(TableCell(cell_children), cb.start, cb.end),
                )
              }
            }
          _ => ()
        }
      _ => ()
    }
  }
}

///|
/// Recursively extract block-level TxtAST nodes from arbitrary Typst expressions
/// (ContentBlock, nested FuncCall, control flow, arrays, named args) in source order.
fn Converter::extract_blocks_from_expr(
  self : Self,
  expr : SpannedNode,
  out : Array[TxtNode],
) -> Unit {
  match expr.kind() {
    ContentBlock =>
      if expr.markup_child() is Some(markup) {
        out.append(self.convert_markup_blocks(markup.children))
      }
    FuncCall =>
      match expr.func_callee_name() {
        Some("raw") if expr.is_raw_func_block() =>
          out.append(
            self.convert_block_func_call("raw", expr, expr.start, expr.end),
          )
        Some(name) if is_block_func_name(name) =>
          out.append(
            self.convert_block_func_call(name, expr, expr.start, expr.end),
          )
        Some("image") => {
          let img = self.convert_image_func(expr, expr.start, expr.end)
          out.push(self.make_node(Paragraph([img]), expr.start, expr.end))
        }
        Some("footnote") =>
          for body_arg in expr.footnote_body_args() {
            self.extract_blocks_from_expr(body_arg, out)
          }
        _ =>
          if expr.func_args() is Some(args) {
            self.extract_blocks_from_expr(args, out)
          }
      }
    LetBinding | SetRule | ShowRule | ModuleImport | ModuleInclude => ()
    _ =>
      for child in expr.children {
        self.extract_blocks_from_expr(child, out)
      }
  }
}

///|
fn Converter::build_paragraph(
  self : Self,
  items : Array[MarkupItem],
) -> TxtNode? {
  let children = self.convert_inline_items(items)
  guard children is [first, ..] && children is [.., last] else { None }
  Some(self.make_node(Paragraph(children), first.range_start, last.range_end))
}

///|
fn Converter::convert_inline_nodes(
  self : Self,
  nodes : Array[SpannedNode],
) -> Array[TxtNode] {
  self.convert_inline_items(group_markup_items(nodes))
}

///|
/// Convert a slice of MarkupItems into inline TxtAST nodes,
/// trimming leading/trailing spaces and merging adjacent plain text into Str nodes.
fn Converter::convert_inline_items(
  self : Self,
  items : Array[MarkupItem],
) -> Array[TxtNode] {
  // Trim leading and trailing pure whitespace items.
  let mut lo = 0
  let mut hi = items.length()
  while lo < hi && items[lo].is_space() {
    lo += 1
  }
  while hi > lo && items[hi - 1].is_space() {
    hi -= 1
  }
  let out : Array[TxtNode] = []
  let mut str_start : Int32? = None
  let mut str_end : Int32 = 0
  let str_buf = StringBuilder()

  fn flush_str() -> Unit {
    if str_start is Some(s) {
      out.push(self.make_node(Str(value=str_buf.to_string()), s, str_end))
      str_start = None
      str_buf.reset()
    }
  }

  fn push_str_piece(start : Int32, end : Int32, piece : String) -> Unit {
    if str_start is Some(_) && start == str_end {
      str_buf.write_string(piece)
      str_end = end
    } else {
      flush_str()
      str_start = Some(start)
      str_end = end
      str_buf.write_string(piece)
    }
  }

  for item in items[lo:hi] {
    match item {
      Single(node) =>
        match node.kind() {
          Text | SpaceNoNewline | SpaceWithNewline | SmartQuote =>
            push_str_piece(
              node.start,
              node.end,
              self.slice(node.start, node.end),
            )
          Escape => {
            flush_str()
            let ch = (@ast.Escape::from_untyped(node.node) : @ast.Escape?).map_or_else(
              fn() { self.slice(node.start, node.end) },
              fn(esc) { esc.get().to_string() },
            )
            out.push(self.make_node(Str(value=ch), node.start, node.end))
          }
          Shorthand => {
            flush_str()
            let ch = (@ast.Shorthand::from_untyped(node.node) : @ast.Shorthand?).map_or_else(
              fn() { self.slice(node.start, node.end) },
              fn(sh) { sh.get().to_string() },
            )
            out.push(self.make_node(Str(value=ch), node.start, node.end))
          }
          Linebreak => {
            flush_str()
            out.push(self.make_node(Break, node.start, node.end))
          }
          Strong => {
            flush_str()
            let children = match node.markup_child() {
              Some(markup) => self.convert_inline_nodes(markup.children)
              None => []
            }
            out.push(self.make_node(Strong(children), node.start, node.end))
          }
          Emph => {
            flush_str()
            let children = match node.markup_child() {
              Some(markup) => self.convert_inline_nodes(markup.children)
              None => []
            }
            out.push(self.make_node(Emphasis(children), node.start, node.end))
          }
          Link => {
            flush_str()
            let url = self.slice(node.start, node.end)
            let str_child = self.make_node(Str(value=url), node.start, node.end)
            out.push(
              self.make_node(
                Link(url~, title=None, children=[str_child]),
                node.start,
                node.end,
              ),
            )
          }
          Raw => {
            flush_str()
            let (value, _) = node.raw_value_and_lang()
            out.push(self.make_node(Code(value~), node.start, node.end))
          }
          Equation => {
            flush_str()
            let value = node.equation_value()
            out.push(self.make_node(Code(value~), node.start, node.end))
          }
          LineComment | BlockComment => {
            flush_str()
            let value = node.comment_value()
            out.push(self.make_node(Comment(value~), node.start, node.end))
          }
          Ref => {
            flush_str()
            let mut supplement_markup : SpannedNode? = None
            for child in node.children {
              if child.kind() is ContentBlock {
                supplement_markup = child.markup_child()
              }
            }
            match supplement_markup {
              Some(markup) => {
                let target = (@ast.Ref::from_untyped(node.node) : @ast.Ref?).map_or_else(
                  fn() { self.slice(node.start, node.end) },
                  fn(r) { "@" + r.target() },
                )
                let children = self.convert_inline_nodes(markup.children)
                out.push(
                  self.make_node(
                    Link(url=target, title=None, children~),
                    node.start,
                    node.end,
                  ),
                )
              }
              None => {
                let value = self.slice(node.start, node.end)
                out.push(self.make_node(Code(value~), node.start, node.end))
              }
            }
          }
          Label => {
            flush_str()
            let value = self.slice(node.start, node.end)
            out.push(self.make_node(Code(value~), node.start, node.end))
          }
          Parbreak => flush_str()
          _ => {
            let raw = self.slice(node.start, node.end)
            if !raw.is_empty() {
              push_str_piece(node.start, node.end, raw)
            }
          }
        }
      Hashed(hash~, expr~, end~) => {
        flush_str()
        out.append(self.convert_inline_hashed(hash, expr, end))
      }
    }
  }
  flush_str()
  out
}

///|
fn Converter::convert_inline_hashed(
  self : Self,
  hash : SpannedNode,
  expr : SpannedNode,
  end : Int32,
) -> Array[TxtNode] {
  let start = hash.start
  match expr.kind() {
    ContentBlock =>
      match expr.markup_child() {
        Some(markup) => self.convert_inline_nodes(markup.children)
        None => []
      }
    FuncCall =>
      match expr.func_callee_name() {
        Some("strong") => {
          let children = self.extract_first_content_inlines(expr)
          [self.make_node(Strong(children), start, end)]
        }
        Some("emph") => {
          let children = self.extract_first_content_inlines(expr)
          [self.make_node(Emphasis(children), start, end)]
        }
        Some("strike") => {
          let children = self.extract_first_content_inlines(expr)
          [self.make_node(Delete(children), start, end)]
        }
        Some("link") => {
          let mut url = ""
          let mut children : Array[TxtNode] = []
          if expr.func_args() is Some(args) {
            let pos = args.positional_args()
            if pos is [first_arg, ..] && first_arg.str_literal() is Some(s) {
              url = s
            }
            if args.content_blocks() is [first_cb, ..] &&
              first_cb.markup_child() is Some(markup) {
              children = self.convert_inline_nodes(markup.children)
            } else if pos is [str_node, ..] &&
              str_node.kind() is Str &&
              str_node.end - str_node.start >= 2 {
              // `#link("https://...")` without body: use inner string range if non-empty.
              children = [
                self.make_node(
                  Str(value=url),
                  str_node.start + 1,
                  str_node.end - 1,
                ),
              ]
            }
          }
          [self.make_node(Link(url~, title=None, children~), start, end)]
        }
        Some("image") => [self.convert_image_func(expr, start, end)]
        Some("raw") => {
          let value = match expr.func_args() {
            Some(args) if args.positional_args() is [first_arg, ..] =>
              first_arg.str_literal().unwrap_or("")
            _ => ""
          }
          [self.make_node(Code(value~), start, end)]
        }
        Some("footnote") => {
          let body_args = expr.footnote_body_args()
          if body_args.is_empty() {
            [self.make_node(Code(value=self.slice(start, end)), start, end)]
          } else {
            let out : Array[TxtNode] = []
            for body_arg in body_args {
              self.extract_inlines_from_expr(body_arg, out)
            }
            out
          }
        }
        _ =>
          // Generic inline function call: recursively expose prose inside any ContentBlock arguments;
          // otherwise treat the expression as inline Code so rules don't false-positive on Typst code.
          if expr.has_content_block() {
            let out : Array[TxtNode] = []
            if expr.func_args() is Some(args) {
              self.extract_inlines_from_expr(args, out)
            }
            out
          } else {
            [self.make_node(Code(value=self.slice(start, end)), start, end)]
          }
      }
    kind if kind.is_control_expr() =>
      if expr.has_content_block() {
        let out : Array[TxtNode] = []
        self.extract_inlines_from_expr(expr, out)
        out
      } else {
        [self.make_node(Code(value=self.slice(start, end)), start, end)]
      }
    _ => [self.make_node(Code(value=self.slice(start, end)), start, end)]
  }
}

///|
fn Converter::convert_image_func(
  self : Self,
  expr : SpannedNode,
  start : Int32,
  end : Int32,
) -> TxtNode {
  let mut url = ""
  let mut alt : String? = None
  if expr.func_args() is Some(args) {
    if args.positional_args() is [first_arg, ..] &&
      first_arg.str_literal() is Some(s) {
      url = s
    }
    if args.named_arg("alt") is Some(alt_node) {
      alt = alt_node.str_literal()
    }
  }
  self.make_node(Image(url~, alt~, title=None), start, end)
}

///|
/// Recursively extract inline TxtAST nodes from expressions containing ContentBlocks in source order.
fn Converter::extract_inlines_from_expr(
  self : Self,
  expr : SpannedNode,
  out : Array[TxtNode],
) -> Unit {
  match expr.kind() {
    ContentBlock =>
      if expr.markup_child() is Some(markup) {
        out.append(self.convert_inline_nodes(markup.children))
      }
    FuncCall =>
      match expr.func_callee_name() {
        Some("strong") => {
          let children = self.extract_first_content_inlines(expr)
          out.push(self.make_node(Strong(children), expr.start, expr.end))
        }
        Some("emph") => {
          let children = self.extract_first_content_inlines(expr)
          out.push(self.make_node(Emphasis(children), expr.start, expr.end))
        }
        Some("strike") => {
          let children = self.extract_first_content_inlines(expr)
          out.push(self.make_node(Delete(children), expr.start, expr.end))
        }
        Some("image") =>
          out.push(self.convert_image_func(expr, expr.start, expr.end))
        Some("footnote") =>
          for body_arg in expr.footnote_body_args() {
            self.extract_inlines_from_expr(body_arg, out)
          }
        _ =>
          if expr.func_args() is Some(args) {
            self.extract_inlines_from_expr(args, out)
          }
      }
    LetBinding | SetRule | ShowRule | ModuleImport | ModuleInclude => ()
    _ =>
      for child in expr.children {
        self.extract_inlines_from_expr(child, out)
      }
  }
}

///|
fn Converter::extract_first_content_inlines(
  self : Self,
  func_call : SpannedNode,
) -> Array[TxtNode] {
  guard func_call.func_args() is Some(args) else { [] }
  guard args.content_blocks() is [first_cb, ..] else { [] }
  guard first_cb.markup_child() is Some(markup) else { [] }
  self.convert_inline_nodes(markup.children)
}

///|
/// Parse a Typst source document into a textlint TxtAST `Document` node.
pub fn parse_typst_to_txt_ast(source : String) -> TxtNode {
  let spanned_root = SpannedNode::from_cst(@syntax.parse(source))
  let conv = Converter::new(source)
  let children = conv.convert_markup_blocks(spanned_root.children)
  conv.make_node(Document(children), 0, source.length())
}
