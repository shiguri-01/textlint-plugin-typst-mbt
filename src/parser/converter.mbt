///|
/// A Typst CST node paired with exact UTF-16 code unit [start, end) offsets.
priv struct SpannedNode {
  node : @syntax.SyntaxNode
  start : Int32
  end : Int32
  children : Array[SpannedNode]
}

///|
fn build_spanned_tree(
  node : @syntax.SyntaxNode,
  cursor : Ref[Int32],
) -> SpannedNode {
  let start = cursor.val
  if node.is_inner() {
    let raw_children = node.children()
    let children : Array[SpannedNode] = Array(capacity=raw_children.length())
    for child in raw_children {
      children.push(build_spanned_tree(child, cursor))
    }
    { node, start, end: cursor.val, children, }
  } else {
    let len = node.full_text().length()
    cursor.val = start + len
    { node, start, end: cursor.val, children: [], }
  }
}

///|
priv struct Converter {
  source : String
  lines : LineIndex
}

///|
fn Converter::new(source : String) -> Converter {
  { source, lines: LineIndex::new(source), }
}

///|
fn Converter::slice(self : Converter, start : Int32, end : Int32) -> String {
  self.source.unsafe_substring(start~, end~)
}

///|
fn Converter::make_node(
  self : Converter,
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
fn MarkupItem::start(self : MarkupItem) -> Int32 {
  match self {
    Single(n) => n.start
    Hashed(hash~, ..) => hash.start
  }
}

///|
fn MarkupItem::end(self : MarkupItem) -> Int32 {
  match self {
    Single(n) => n.end
    Hashed(end~, ..) => end
  }
}

///|
fn group_markup_items(nodes : Array[SpannedNode]) -> Array[MarkupItem] {
  let items : Array[MarkupItem] = []
  let len = nodes.length()
  let mut i = 0
  while i < len {
    let cur = nodes[i]
    if cur.node.kind() is Hash && i + 1 < len {
      let expr = nodes[i + 1]
      let mut end = expr.end
      let mut next_i = i + 2
      if next_i < len && nodes[next_i].node.kind() is Semicolon {
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
fn is_space_kind(kind : @syntax.SyntaxKind) -> Bool {
  kind is (SpaceNoNewline | SpaceWithNewline)
}

///|
fn is_raw_block(node : @syntax.SyntaxNode) -> Bool {
  match (@ast.Raw::from_untyped(node) : @ast.Raw?) {
    Some(raw) => raw.block()
    None => false
  }
}

///|
fn is_display_equation(node : SpannedNode) -> Bool {
  if !(node.node.kind() is Equation) {
    return false
  }
  let children = node.children
  if children.length() < 3 {
    return false
  }
  // Typst display equation has space right after opening `$` and before closing `$`.
  is_space_kind(children[1].node.kind()) &&
  is_space_kind(children[children.length() - 2].node.kind())
}

///|
fn extract_raw_value_and_lang(node : SpannedNode) -> (String, String?) {
  let lang : String? = match (@ast.Raw::from_untyped(node.node) : @ast.Raw?) {
    Some(raw) => raw.lang().map(fn(l) { l.get() })
    None => None
  }
  let buf = StringBuilder()
  let mut first = true
  for child in node.children {
    match child.node.kind() {
      Text => {
        if !first {
          buf.write_char('\n')
        }
        buf.write_string(child.node.leaf_text())
        first = false
      }
      _ => ()
    }
  }
  (buf.to_string(), lang)
}

///|
fn extract_equation_value(node : SpannedNode) -> String {
  let buf = StringBuilder()
  for child in node.children {
    if !(child.node.kind() is Dollar) {
      buf.write_string(child.node.full_text())
    }
  }
  buf.to_string().trim().to_owned()
}

///|
fn extract_comment_value(node : SpannedNode) -> String {
  match node.node.kind() {
    LineComment =>
      match (@ast.LineComment::from_untyped(node.node) : @ast.LineComment?) {
        Some(c) => c.text()
        None => node.node.leaf_text()
      }
    BlockComment =>
      match (@ast.BlockComment::from_untyped(node.node) : @ast.BlockComment?) {
        Some(c) => c.text()
        None => node.node.leaf_text()
      }
    _ => node.node.full_text()
  }
}

///|
fn extract_func_callee_name(func_call : SpannedNode) -> String? {
  for child in func_call.children {
    match child.node.kind() {
      Ident => return Some(child.node.leaf_text())
      FieldAccess => return Some(child.node.full_text())
      _ => ()
    }
  }
  None
}

///|
fn find_func_args(func_call : SpannedNode) -> SpannedNode? {
  for child in func_call.children {
    if child.node.kind() is Args {
      return Some(child)
    }
  }
  None
}

///|
fn extract_str_literal(node : SpannedNode) -> String? {
  if node.node.kind() is Str {
    Some(@syntax.unescape_str_literal(node.node.leaf_text()))
  } else {
    None
  }
}

///|
fn extract_int_literal(node : SpannedNode) -> Int32? {
  if !(node.node.kind() is Int) {
    return None
  }
  let text = node.node.leaf_text()
  let mut acc = 0
  let mut has_digit = false
  for i = 0; i < text.length(); i = i + 1 {
    let c = text.code_unit_at(i).to_int()
    if c >= '0' && c <= '9' {
      acc = acc * 10 + (c - '0')
      has_digit = true
    } else {
      return None
    }
  }
  if has_digit {
    Some(acc)
  } else {
    None
  }
}

///|
fn extract_named_arg(args : SpannedNode, name : String) -> SpannedNode? {
  for child in args.children {
    if child.node.kind() is Named {
      let mut key_matches = false
      let mut last_expr : SpannedNode? = None
      for nc in child.children {
        let k = nc.node.kind()
        if !key_matches && k is Ident {
          if nc.node.leaf_text() == name {
            key_matches = true
          } else {
            break
          }
        } else if key_matches && !k.is_trivia() && !(k is Colon) {
          last_expr = Some(nc)
        }
      }
      if key_matches {
        return last_expr
      }
    }
  }
  None
}

///|
fn extract_positional_args(args : SpannedNode) -> Array[SpannedNode] {
  let out : Array[SpannedNode] = []
  for child in args.children {
    let k = child.node.kind()
    if !k.is_trivia() &&
      !(k is LeftParen) &&
      !(k is RightParen) &&
      !(k is Comma) &&
      !(k is Named) &&
      !(k is Spread) {
      out.push(child)
    }
  }
  out
}

///|
/// Collect all ContentBlock nodes inside a FuncCall's Args in source order.
fn collect_content_blocks(args : SpannedNode) -> Array[SpannedNode] {
  let out : Array[SpannedNode] = []
  for child in args.children {
    match child.node.kind() {
      ContentBlock => out.push(child)
      Named =>
        for nc in child.children {
          if nc.node.kind() is ContentBlock {
            out.push(nc)
          }
        }
      _ => ()
    }
  }
  out
}

///|
fn find_markup_child(node : SpannedNode) -> SpannedNode? {
  for child in node.children {
    if child.node.kind() is Markup {
      return Some(child)
    }
  }
  None
}

///|
fn is_block_func_name(name : String) -> Bool {
  match name {
    "heading"
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
    | "pagebreak"
    | "parbreak" => true
    _ => false
  }
}

///|
fn is_stmt_expr_kind(kind : @syntax.SyntaxKind) -> Bool {
  kind
  is (LetBinding
  | SetRule
  | ShowRule
  | ModuleImport
  | ModuleInclude
  | CodeBlock)
}

///|
/// Convert a Typst `Markup` node's children into block-level TxtAST nodes.
fn Converter::convert_markup_blocks(
  self : Converter,
  nodes : Array[SpannedNode],
) -> Array[TxtNode] {
  let items = group_markup_items(nodes)
  let blocks : Array[TxtNode] = []
  let inline_buf : Array[MarkupItem] = []

  fn flush_paragraph() -> Unit {
    if !inline_buf.is_empty() {
      match self.build_paragraph(inline_buf) {
        Some(p) => blocks.push(p)
        None => ()
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
        match node.node.kind() {
          Parbreak => {
            flush_paragraph()
            i += 1
          }
          Heading => {
            flush_paragraph()
            blocks.push(self.convert_heading(node))
            i += 1
          }
          ListItem => {
            flush_paragraph()
            let (list_node, next_i) = self.consume_list(items, i, ListItem)
            blocks.push(list_node)
            i = next_i
          }
          EnumItem => {
            flush_paragraph()
            let (list_node, next_i) = self.consume_list(items, i, EnumItem)
            blocks.push(list_node)
            i = next_i
          }
          TermItem => {
            flush_paragraph()
            let (list_node, next_i) = self.consume_list(items, i, TermItem)
            blocks.push(list_node)
            i = next_i
          }
          Raw if is_raw_block(node.node) => {
            flush_paragraph()
            let (value, lang) = extract_raw_value_and_lang(node)
            blocks.push(
              self.make_node(CodeBlock(value~, lang~), node.start, node.end),
            )
            i += 1
          }
          Equation if is_display_equation(node) &&
            is_only_whitespace_items(inline_buf) => {
            flush_paragraph()
            let value = extract_equation_value(node)
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
            let value = extract_comment_value(node)
            blocks.push(self.make_node(Comment(value~), node.start, node.end))
            i += 1
          }
          Shebang => {
            flush_paragraph()
            i += 1
          }
          _ => {
            inline_buf.push(item)
            i += 1
          }
        }
      Hashed(hash~, expr~, end~) => {
        let ek = expr.node.kind()
        if is_stmt_expr_kind(ek) && is_only_whitespace_items(inline_buf) {
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
          match find_markup_child(expr) {
            Some(markup) =>
              for b in self.convert_markup_blocks(markup.children) {
                blocks.push(b)
              }
            None => ()
          }
          i += 1
        } else if ek is FuncCall && is_only_whitespace_items(inline_buf) {
          match extract_func_callee_name(expr) {
            Some(name) if is_block_func_name(name) => {
              inline_buf.clear()
              for b in self.convert_block_func_call(name, expr, hash.start, end) {
                blocks.push(b)
              }
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
fn is_only_whitespace_items(items : Array[MarkupItem]) -> Bool {
  for item in items {
    match item {
      Single(n) if is_space_kind(n.node.kind()) => ()
      _ => return false
    }
  }
  true
}

///|
fn ends_with_newline_item(items : Array[MarkupItem]) -> Bool {
  if items.is_empty() {
    return false
  }
  match items[items.length() - 1] {
    Single(n) => n.node.kind() is SpaceWithNewline
    _ => false
  }
}

///|
fn Converter::convert_heading(
  self : Converter,
  heading : SpannedNode,
) -> TxtNode {
  let raw_depth = match
    (@ast.Heading::from_untyped(heading.node) : @ast.Heading?) {
    Some(h) => h.depth()
    None => 1
  }
  let depth = if raw_depth < 1 {
    1
  } else if raw_depth > 6 {
    6
  } else {
    raw_depth
  }
  let children = match find_markup_child(heading) {
    Some(markup) => self.convert_inline_nodes(markup.children)
    None => []
  }
  self.make_node(Header(depth~, children~), heading.start, heading.end)
}

///|
fn Converter::consume_list(
  self : Converter,
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
    match items[i] {
      Single(node) if node.node.kind() == item_kind => {
        if item_kind is EnumItem && list_items.is_empty() {
          match (@ast.EnumItem::from_untyped(node.node) : @ast.EnumItem?) {
            Some(ei) =>
              first_enum_start = match ei.number() {
                Some(n) => Some(n.to_int())
                None => Some(1)
              }
            None => first_enum_start = Some(1)
          }
        }
        list_items.push(self.convert_list_item(node, item_kind))
        last_item_end = node.end
        i += 1
        // Look ahead over spaces/parbreaks to see if another item of the same kind follows.
        let mut j = i
        let mut saw_parbreak = false
        while j < len {
          match items[j] {
            Single(s) if is_space_kind(s.node.kind()) => j += 1
            Single(s) if s.node.kind() is Parbreak => {
              saw_parbreak = true
              j += 1
            }
            _ => break
          }
        }
        if j < len &&
          items[j] is Single(next_node) &&
          next_node.node.kind() == item_kind {
          if saw_parbreak {
            spread = true
          }
          i = j
        } else {
          break
        }
      }
      _ => break
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
  self : Converter,
  node : SpannedNode,
  item_kind : @syntax.SyntaxKind,
) -> TxtNode {
  let children : Array[TxtNode] = []
  match item_kind {
    TermItem =>
      // TermItem has two Markup children: term and description.
      for child in node.children {
        if child.node.kind() is Markup {
          for b in self.convert_markup_blocks(child.children) {
            children.push(b)
          }
        }
      }
    _ =>
      match find_markup_child(node) {
        Some(markup) =>
          for b in self.convert_markup_blocks(markup.children) {
            children.push(b)
          }
        None => ()
      }
  }
  let spread = children.length() > 1
  self.make_node(ListItem(spread~, children~), node.start, node.end)
}

///|
fn Converter::convert_block_func_call(
  self : Converter,
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
      match find_func_args(func_call) {
        Some(args) => {
          match extract_named_arg(args, "level") {
            Some(lvl_node) =>
              match extract_int_literal(lvl_node) {
                Some(n) => depth = if n < 1 { 1 } else if n > 6 { 6 } else { n }
                None => ()
              }
            None => ()
          }
          let content_blocks = collect_content_blocks(args)
          if !content_blocks.is_empty() {
            match find_markup_child(content_blocks[0]) {
              Some(markup) =>
                body_children = self.convert_inline_nodes(markup.children)
              None => ()
            }
          }
        }
        None => ()
      }
      [self.make_node(Header(depth~, children=body_children), start, end)]
    }
    "quote" => {
      let body_blocks : Array[TxtNode] = []
      match find_func_args(func_call) {
        Some(args) =>
          for cb in collect_content_blocks(args) {
            match find_markup_child(cb) {
              Some(markup) =>
                for b in self.convert_markup_blocks(markup.children) {
                  body_blocks.push(b)
                }
              None => ()
            }
          }
        None => ()
      }
      [self.make_node(BlockQuote(body_blocks), start, end)]
    }
    "table" =>
      match find_func_args(func_call) {
        Some(args) => {
          let mut col_count = 1
          match extract_named_arg(args, "columns") {
            Some(cols_node) =>
              match extract_int_literal(cols_node) {
                Some(n) if n > 0 => col_count = n
                _ =>
                  if cols_node.node.kind() is Array {
                    let count = extract_positional_args(cols_node).length()
                    if count > 0 {
                      col_count = count
                    }
                  }
              }
            None => ()
          }
          let cells : Array[TxtNode] = []
          for arg in extract_positional_args(args) {
            if arg.node.kind() is ContentBlock {
              let cell_children = match find_markup_child(arg) {
                Some(markup) => self.convert_inline_nodes(markup.children)
                None => []
              }
              cells.push(
                self.make_node(TableCell(cell_children), arg.start, arg.end),
              )
            }
          }
          if cells.is_empty() {
            []
          } else {
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
        }
        None => []
      }
    _ => {
      // Container functions (figure, block, align, pad, rect, grid, columns, etc.):
      // Extract blocks from any ContentBlock arguments in source order.
      let out : Array[TxtNode] = []
      match find_func_args(func_call) {
        Some(args) =>
          for cb in collect_content_blocks(args) {
            match find_markup_child(cb) {
              Some(markup) =>
                for b in self.convert_markup_blocks(markup.children) {
                  out.push(b)
                }
              None => ()
            }
          }
        None => ()
      }
      out
    }
  }
}

///|
fn Converter::build_paragraph(
  self : Converter,
  items : Array[MarkupItem],
) -> TxtNode? {
  let children = self.convert_inline_items(items)
  if children.is_empty() {
    None
  } else {
    let start = children[0].range_start
    let end = children[children.length() - 1].range_end
    Some(self.make_node(Paragraph(children), start, end))
  }
}

///|
fn Converter::convert_inline_nodes(
  self : Converter,
  nodes : Array[SpannedNode],
) -> Array[TxtNode] {
  self.convert_inline_items(group_markup_items(nodes))
}

///|
/// Convert a slice of MarkupItems into inline TxtAST nodes,
/// trimming leading/trailing spaces and merging adjacent plain text into Str nodes.
fn Converter::convert_inline_items(
  self : Converter,
  items : Array[MarkupItem],
) -> Array[TxtNode] {
  // Trim leading and trailing pure whitespace items.
  let mut lo = 0
  let mut hi = items.length()
  while lo < hi {
    match items[lo] {
      Single(n) if is_space_kind(n.node.kind()) => lo += 1
      _ => break
    }
  }
  while hi > lo {
    match items[hi - 1] {
      Single(n) if is_space_kind(n.node.kind()) => hi -= 1
      _ => break
    }
  }
  let out : Array[TxtNode] = []
  let mut str_start : Int32? = None
  let mut str_end : Int32 = 0
  let str_buf = StringBuilder()

  fn flush_str() -> Unit {
    match str_start {
      Some(s) => {
        out.push(self.make_node(Str(value=str_buf.to_string()), s, str_end))
        str_start = None
        str_buf.reset()
      }
      None => ()
    }
  }

  fn push_str_piece(start : Int32, end : Int32, piece : String) -> Unit {
    match str_start {
      Some(_) =>
        if start == str_end {
          str_buf.write_string(piece)
          str_end = end
        } else {
          flush_str()
          str_start = Some(start)
          str_end = end
          str_buf.write_string(piece)
        }
      None => {
        str_start = Some(start)
        str_end = end
        str_buf.write_string(piece)
      }
    }
  }

  for idx = lo; idx < hi; idx = idx + 1 {
    let item = items[idx]
    match item {
      Single(node) =>
        match node.node.kind() {
          Text | SpaceNoNewline | SpaceWithNewline | SmartQuote =>
            push_str_piece(
              node.start,
              node.end,
              self.slice(node.start, node.end),
            )
          Escape => {
            flush_str()
            let ch = match
              (@ast.Escape::from_untyped(node.node) : @ast.Escape?) {
              Some(esc) => esc.get().to_string()
              None => self.slice(node.start, node.end)
            }
            out.push(self.make_node(Str(value=ch), node.start, node.end))
          }
          Shorthand => {
            flush_str()
            let ch = match
              (@ast.Shorthand::from_untyped(node.node) : @ast.Shorthand?) {
              Some(sh) => sh.get().to_string()
              None => self.slice(node.start, node.end)
            }
            out.push(self.make_node(Str(value=ch), node.start, node.end))
          }
          Linebreak => {
            flush_str()
            out.push(self.make_node(Break, node.start, node.end))
          }
          Strong => {
            flush_str()
            let children = match find_markup_child(node) {
              Some(markup) => self.convert_inline_nodes(markup.children)
              None => []
            }
            out.push(self.make_node(Strong(children), node.start, node.end))
          }
          Emph => {
            flush_str()
            let children = match find_markup_child(node) {
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
            let (value, _) = extract_raw_value_and_lang(node)
            out.push(self.make_node(Code(value~), node.start, node.end))
          }
          Equation => {
            flush_str()
            let value = extract_equation_value(node)
            out.push(self.make_node(Code(value~), node.start, node.end))
          }
          LineComment | BlockComment => {
            flush_str()
            let value = extract_comment_value(node)
            out.push(self.make_node(Comment(value~), node.start, node.end))
          }
          Ref => {
            flush_str()
            let mut supplement_markup : SpannedNode? = None
            for child in node.children {
              if child.node.kind() is ContentBlock {
                supplement_markup = find_markup_child(child)
              }
            }
            match supplement_markup {
              Some(markup) => {
                let target = match
                  (@ast.Ref::from_untyped(node.node) : @ast.Ref?) {
                  Some(r) => "@" + r.target()
                  None => self.slice(node.start, node.end)
                }
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
        for inline_node in self.convert_inline_hashed(hash, expr, end) {
          out.push(inline_node)
        }
      }
    }
  }
  flush_str()
  out
}

///|
fn Converter::convert_inline_hashed(
  self : Converter,
  hash : SpannedNode,
  expr : SpannedNode,
  end : Int32,
) -> Array[TxtNode] {
  let start = hash.start
  match expr.node.kind() {
    ContentBlock =>
      match find_markup_child(expr) {
        Some(markup) => self.convert_inline_nodes(markup.children)
        None => []
      }
    FuncCall =>
      match extract_func_callee_name(expr) {
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
          match find_func_args(expr) {
            Some(args) => {
              let pos = extract_positional_args(args)
              if !pos.is_empty() {
                match extract_str_literal(pos[0]) {
                  Some(s) => url = s
                  None => ()
                }
              }
              let cbs = collect_content_blocks(args)
              if !cbs.is_empty() {
                match find_markup_child(cbs[0]) {
                  Some(markup) =>
                    children = self.convert_inline_nodes(markup.children)
                  None => ()
                }
              } else if !pos.is_empty() && pos[0].node.kind() is Str {
                // `#link("https://...")` without body: use inner string range if non-empty.
                let str_node = pos[0]
                if str_node.end - str_node.start >= 2 {
                  children = [
                    self.make_node(
                      Str(value=url),
                      str_node.start + 1,
                      str_node.end - 1,
                    ),
                  ]
                }
              }
            }
            None => ()
          }
          [self.make_node(Link(url~, title=None, children~), start, end)]
        }
        Some("image") => {
          let mut url = ""
          let mut alt : String? = None
          match find_func_args(expr) {
            Some(args) => {
              let pos = extract_positional_args(args)
              if !pos.is_empty() {
                match extract_str_literal(pos[0]) {
                  Some(s) => url = s
                  None => ()
                }
              }
              match extract_named_arg(args, "alt") {
                Some(alt_node) => alt = extract_str_literal(alt_node)
                None => ()
              }
            }
            None => ()
          }
          [self.make_node(Image(url~, alt~, title=None), start, end)]
        }
        _ =>
          // Generic inline function call: if it has ContentBlock arguments, expose their prose;
          // otherwise treat the expression as inline Code so rules don't false-positive on Typst code.
          match find_func_args(expr) {
            Some(args) => {
              let cbs = collect_content_blocks(args)
              if cbs.is_empty() {
                [self.make_node(Code(value=self.slice(start, end)), start, end)]
              } else {
                let out : Array[TxtNode] = []
                for cb in cbs {
                  match find_markup_child(cb) {
                    Some(markup) =>
                      for n in self.convert_inline_nodes(markup.children) {
                        out.push(n)
                      }
                    None => ()
                  }
                }
                out
              }
            }
            None =>
              [self.make_node(Code(value=self.slice(start, end)), start, end)]
          }
      }
    _ => [self.make_node(Code(value=self.slice(start, end)), start, end)]
  }
}

///|
fn Converter::extract_first_content_inlines(
  self : Converter,
  func_call : SpannedNode,
) -> Array[TxtNode] {
  match find_func_args(func_call) {
    Some(args) => {
      let cbs = collect_content_blocks(args)
      if !cbs.is_empty() {
        match find_markup_child(cbs[0]) {
          Some(markup) => self.convert_inline_nodes(markup.children)
          None => []
        }
      } else {
        []
      }
    }
    None => []
  }
}

///|
/// Parse a Typst source document into a textlint TxtAST `Document` node.
pub fn parse_typst_to_txt_ast(source : String) -> TxtNode {
  let root_cst = @syntax.parse(source)
  let cursor : Ref[Int32] = { val: 0, }
  let spanned_root = build_spanned_tree(root_cst, cursor)
  let conv = Converter::new(source)
  let children = conv.convert_markup_blocks(spanned_root.children)
  conv.make_node(Document(children), 0, source.length())
}
