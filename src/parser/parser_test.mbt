///|
test "heading and paragraph" {
  let doc = @textlint-plugin-typst.parse_typst_to_txt_ast(
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
  let doc = @textlint-plugin-typst.parse_typst_to_txt_ast(src)
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
  let doc = @textlint-plugin-typst.parse_typst_to_txt_ast(src)
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
  let doc = @textlint-plugin-typst.parse_typst_to_txt_ast(src)
  guard doc.kind is Document(children) else { fail("expected Document") }
  let types = children.map(fn(n) { n.type_name() })
  assert_eq(types, ["Comment", "Paragraph", "Comment", "Comment"])
  guard children[0].kind is Comment(value~) else { fail("expected Comment") }
  assert_eq(value, " textlint-disable")
}

///|
test "code block and typst statements" {
  let src = "#let title = \"hello\"\n\n```rust\nfn main() {}\n```\n"
  let doc = @textlint-plugin-typst.parse_typst_to_txt_ast(src)
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
  let doc = @textlint-plugin-typst.parse_typst_to_txt_ast(src)
  guard doc.kind is Document(children) else { fail("expected Document") }
  let types = children.map(fn(n) { n.type_name() })
  assert_eq(types, ["BlockQuote", "Table", "Paragraph"])
  guard children[1].kind is Table(rows) else { fail("expected Table") }
  assert_eq(rows.length(), 2)
}

///|
test "utf16 surrogate pair and crlf locations" {
  let src = "😀\r\nあいう"
  let doc = @textlint-plugin-typst.parse_typst_to_txt_ast(src)
  assert_eq(doc.range_start, 0)
  assert_eq(doc.range_end, 7)
  assert_eq(doc.loc.start, { line: 1, column: 0, })
  assert_eq(doc.loc.end, { line: 2, column: 3, })
}

///|
test "json serialization output" {
  let src = "Hello\n\n```rust\nlet x = 1\n```\n"
  let doc = @textlint-plugin-typst.parse_typst_to_txt_ast(src)
  guard doc.to_json()
    is {
      "type": "Document",
      "children": [
        {
          "type": "Paragraph",
          "children": [{ "type": "Str", "value": "Hello", .. }],
          ..
        },
        { "type": "CodeBlock", "lang": "rust", "value": "let x = 1", .. },
      ],
      "range": [0, _],
      "loc": { "start": { "line": 1, "column": 0, .. }, .. },
      ..
    } else {
    fail("unexpected JSON structure")
  }
  let json_str = @textlint-plugin-typst.parse_to_txt_ast_json("Hello")
  assert_true(json_str.contains("\"type\":\"Document\""))
  assert_true(json_str.contains("\"type\":\"Paragraph\""))
  assert_true(json_str.contains("\"type\":\"Str\""))
}

///|
test "table header footer cell and nested figure table" {
  let src =
    #|#figure(
    #|  table(
    #|    columns: 2,
    #|    table.header([H1], [H2]),
    #|    table.cell(colspan: 2)[Body cell],
    #|    table.footer([F1], [F2]),
    #|  ),
    #|  caption: [Table caption],
    #|)
  let doc = @textlint-plugin-typst.parse_typst_to_txt_ast(src)
  guard doc.kind is Document(children) else { fail("expected Document") }
  assert_eq(children.map(fn(n) { n.type_name() }), ["Table", "Paragraph"])
  guard children[0].kind is Table(rows) else { fail("expected Table") }
  // 5 cells (H1, H2, Body cell, F1, F2) with columns: 2 -> 3 rows (2, 2, 1)
  assert_eq(rows.length(), 3)
}

///|
test "control flow if for context blocks and inline" {
  let src =
    #|#if true [
    #|  = Branch Heading
    #|
    #|  Branch body.
    #|] else [
    #|  Fallback body.
    #|]
    #|
    #|#for x in (1, 2) [Loop item.]
    #|
    #|#context [Context text.]
    #|
    #|Inline #if ok [yes] else [no] end.
  let doc = @textlint-plugin-typst.parse_typst_to_txt_ast(src)
  guard doc.kind is Document(children) else { fail("expected Document") }
  assert_eq(children.map(fn(n) { n.type_name() }), [
    "Header", "Paragraph", "Paragraph", "Paragraph", "Paragraph", "Paragraph",
  ])
}

///|
test "custom block macro vs same-line inline macro" {
  let src =
    #|#note[
    #|  = Note Title
    #|
    #|  Note body.
    #|
    #|  - item 1
    #|]
    #|
    #|#badge[NEW] Inline text after badge.
  let doc = @textlint-plugin-typst.parse_typst_to_txt_ast(src)
  guard doc.kind is Document(children) else { fail("expected Document") }
  assert_eq(children.map(fn(n) { n.type_name() }), [
    "Header", "Paragraph", "List", "Paragraph",
  ])
}

///|
test "raw function form block and inline" {
  let src =
    #|#raw("fn main() {}", lang: "rust", block: true)
    #|
    #|Inline #raw("x = 1") here.
  let doc = @textlint-plugin-typst.parse_typst_to_txt_ast(src)
  guard doc.kind is Document(children) else { fail("expected Document") }
  assert_eq(children.map(fn(n) { n.type_name() }), ["CodeBlock", "Paragraph"])
  guard children[0].kind is CodeBlock(value~, lang=Some("rust")) else {
    fail("expected rust CodeBlock")
  }
  assert_eq(value, "fn main() {}")
}

///|
test "footnote splits host paragraph into separate blocks" {
  let src =
    #|導入です。#footnote(numbering: it => [*#it*])[短い補足。]#footnote(body: [名前付き。])続きです。
    #|
    #|- 項目。#footnote(numbering: "a")[補足1。
    #|
    #|補足2。]後続。
  let doc = @textlint-plugin-typst.parse_typst_to_txt_ast(src)
  guard doc.kind is Document([p1, p2, p3, p4, list_node]) else {
    fail("expected 4 Paragraphs and 1 List")
  }
  assert_eq([p1.raw, p2.raw, p3.raw, p4.raw], [
    "導入です。", "短い補足。", "名前付き。", "続きです。",
  ])
  guard list_node.kind is List(children=[list_item], ..) else {
    fail("expected single ListItem")
  }
  guard list_item.kind is ListItem(children=li_children, ..) else {
    fail("expected ListItem")
  }
  assert_eq(li_children.map(fn(n) { n.raw }), [
    "項目。", "補足1。", "補足2。", "後続。",
  ])
}

///|
test "footnote label reference stays inline as code" {
  let src =
    #|前掲の脚注#footnote(<fn1>)を参照してください。
    #|
    #|#footnote(numbering: it => [*#it*], <fn1>)
  let doc = @textlint-plugin-typst.parse_typst_to_txt_ast(src)
  guard doc.kind is Document([inline_para, standalone_para]) else {
    fail("expected 2 Paragraphs")
  }
  guard inline_para.kind is Paragraph(inline_children) else {
    fail("expected Paragraph")
  }
  assert_eq(inline_children.map(fn(n) { n.type_name() }), ["Str", "Code", "Str"])
  guard standalone_para.kind is Paragraph(standalone_children) else {
    fail("expected Paragraph")
  }
  assert_eq(standalone_children.map(fn(n) { n.type_name() }), ["Code"])
}
