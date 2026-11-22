///|
test "heading and paragraph" {
  let doc = @textlint-plugin-typst-mbt.parse_typst_to_txt_ast(
    "= タイトル\n\nこれはテストです。\n",
  )
  assert_eq(doc.type_name(), "Document")
  assert_eq(doc.range_start, 0)
  assert_eq(doc.range_end, 18)
  guard doc.kind is Document(children) else { fail("expected Document") }
  assert_eq(children.length(), 2)
  guard children[0].kind is Header(depth~, children=h_children) else {
    fail("expected Header")
  }
  assert_eq(depth, 1)
  assert_eq(h_children.length(), 1)
  assert_eq(children[0].raw, "= タイトル")
  guard h_children[0].kind is Str(value~) else { fail("expected Str") }
  assert_eq(value, "タイトル")
  guard children[1].kind is Paragraph(p_children) else {
    fail("expected Paragraph")
  }
  assert_eq(p_children.length(), 1)
  guard p_children[0].kind is Str(value=p_val) else { fail("expected Str") }
  assert_eq(p_val, "これはテストです。")
}

///|
test "inline strong emph code equation link" {
  let src = "Hello *bold* _italic_ `code` $x + y$ https://example.com"
  let doc = @textlint-plugin-typst-mbt.parse_typst_to_txt_ast(src)
  guard doc.kind is Document([para]) else { fail("expected single paragraph") }
  guard para.kind is Paragraph(children) else { fail("expected Paragraph") }
  let types = children.map(fn(n) { n.type_name() })
  assert_eq(types, [
    "Str", "Strong", "Str", "Emphasis", "Str", "Code", "Str", "Code", "Str", "Link",
  ])
}

///|
test "lists and enum lists" {
  let src = "- item 1\n- item 2\n\n+ first\n+ second\n"
  let doc = @textlint-plugin-typst-mbt.parse_typst_to_txt_ast(src)
  guard doc.kind is Document(children) else { fail("expected Document") }
  assert_eq(children.length(), 2)
  guard children[0].kind is List(ordered=false, children=ul_items, ..) else {
    fail("expected unordered List")
  }
  assert_eq(ul_items.length(), 2)
  guard children[1].kind
    is List(ordered=true, start=Some(1), children=ol_items, ..) else {
    fail("expected ordered List")
  }
  assert_eq(ol_items.length(), 2)
}

///|
test "comments and directives" {
  let src = "// textlint-disable\nTODO: ignored\n// textlint-enable\n/* block comment */\n"
  let doc = @textlint-plugin-typst-mbt.parse_typst_to_txt_ast(src)
  guard doc.kind is Document(children) else { fail("expected Document") }
  let types = children.map(fn(n) { n.type_name() })
  assert_eq(types, ["Comment", "Paragraph", "Comment", "Comment"])
  guard children[0].kind is Comment(value~) else { fail("expected Comment") }
  assert_eq(value, " textlint-disable")
}

///|
test "code block and typst statements" {
  let src = "#let title = \"hello\"\n\n```rust\nfn main() {}\n```\n"
  let doc = @textlint-plugin-typst-mbt.parse_typst_to_txt_ast(src)
  guard doc.kind is Document(children) else { fail("expected Document") }
  assert_eq(children.length(), 2)
  guard children[0].kind is CodeBlock(lang=Some("typst"), ..) else {
    fail("expected typst CodeBlock")
  }
  guard children[1].kind is CodeBlock(lang=Some("rust"), value~) else {
    fail("expected rust CodeBlock")
  }
  assert_eq(value, "fn main() {}")
}

///|
test "semantic function calls quote table link image" {
  let src = "#quote[引用テキスト]\n\n#table(columns: 2, [A], [B], [C], [D])\n\n#link(\"https://typst.app\")[Typst] and #image(\"a.png\", alt: \"desc\")\n"
  let doc = @textlint-plugin-typst-mbt.parse_typst_to_txt_ast(src)
  guard doc.kind is Document(children) else { fail("expected Document") }
  let types = children.map(fn(n) { n.type_name() })
  assert_eq(types, ["BlockQuote", "Table", "Paragraph"])
  guard children[1].kind is Table(rows) else { fail("expected Table") }
  assert_eq(rows.length(), 2)
}

///|
test "utf16 surrogate pair and crlf locations" {
  let src = "😀\r\nあいう"
  let doc = @textlint-plugin-typst-mbt.parse_typst_to_txt_ast(src)
  assert_eq(doc.range_start, 0)
  assert_eq(doc.range_end, 7)
  assert_eq(doc.loc.start, { line: 1, column: 0, })
  assert_eq(doc.loc.end, { line: 2, column: 3, })
}

///|
test "json serialization output" {
  let json_str = @textlint-plugin-typst-mbt.parse_to_txt_ast_json("Hello")
  assert_true(json_str.contains("\"type\":\"Document\""))
  assert_true(json_str.contains("\"type\":\"Paragraph\""))
  assert_true(json_str.contains("\"type\":\"Str\""))
}
