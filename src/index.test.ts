import { test as assertTxtAST, isTxtAST } from "@textlint/ast-tester";
import { TextlintKernel } from "@textlint/kernel";
import type { TextlintRuleModule } from "@textlint/types";
import filterComments from "textlint-filter-rule-comments";
import ruleNoTodo from "textlint-rule-no-todo";
import { describe, expect, it } from "vite-plus/test";
import plugin, { Processor, TypstProcessor, parse } from "./index.ts";

describe("parse (TxtAST conformance via @textlint/ast-tester)", () => {
  const samples: Array<[string, string]> = [
    ["empty document", ""],
    ["whitespace only", "   \n\n\t  "],
    ["simple heading and paragraph", "= Hello Typst\n\nThis is a paragraph.\n"],
    [
      "japanese text with emoji surrogate pairs",
      "= 日本語の見出し 😀\n\n絵文字🎉と*太字*と_斜体_を含む文章です。\n",
    ],
    ["crlf line endings", "= Title\r\n\r\nLine 1\r\nLine 2\r\n"],
    ["cr line endings", "= Title\r\rLine 1\rLine 2\r"],
    [
      "nested lists, enum lists, and term lists",
      [
        "- item 1",
        "  - nested a",
        "  - nested b",
        "- item 2",
        "",
        "+ first",
        "3. third",
        "",
        "/ Typst: A modern typesetting system.",
        "/ MoonBit: A fast language for Wasm and JS.",
      ].join("\n"),
    ],
    [
      "code blocks, inline code, and math",
      [
        "Inline `let x = 1` and math $a^2 + b^2 = c^2$.",
        "",
        "$ integral_0^infinity e^(-x^2) d x = sqrt(pi) / 2 $",
        "",
        "```typst",
        "#set text(size: 12pt)",
        "= Not a heading",
        "```",
      ].join("\n"),
    ],
    [
      "comments and directives",
      [
        "// textlint-disable",
        "TODO: suppressed",
        "// textlint-enable",
        "Inline /* block comment */ text // trailing comment",
      ].join("\n"),
    ],
    [
      "semantic function calls",
      [
        '#set page(paper: "a4")',
        '#import "@preview/example:0.1.0": *',
        '#let author = "Alice";',
        "",
        "#heading(level: 2)[Function Heading]",
        "",
        "#quote[This is a quoted paragraph.]",
        "",
        "#line(length: 100%)",
        "",
        "#table(",
        "  columns: 2,",
        "  [Header 1], [Header 2],",
        "  [Cell 1], [Cell 2],",
        ")",
        "",
        'See #link("https://typst.app")[Typst] and #strike[old] #strong[bold] #emph[italic].',
        'Image: #image("fig.png", alt: "Diagram")',
        "Footnote: #footnote[This note should be linted.]",
      ].join("\n"),
    ],
    [
      "escapes, shorthands, labels, refs, hard breaks",
      "Escaped \\*star\\* and --- dash... \\ \nNext line @sec-intro and @sec-intro[Section 1] <sec-intro>",
    ],
    [
      "malformed typst syntax still yields valid TxtAST",
      "= Unclosed *bold and #func(\n$ unclosed math\n```unclosed code",
    ],
  ];

  for (const [name, source] of samples) {
    it(`produces valid TxtAST for: ${name}`, () => {
      const ast = parse(source);
      expect(isTxtAST(ast)).toBe(true);
      assertTxtAST(ast as unknown as Record<string, unknown>);
      expect(ast.type).toBe("Document");
      expect(ast.raw).toBe(source);
      expect(ast.range).toEqual([0, source.length]);
    });
  }
});

describe("TypstProcessor", () => {
  it("exposes .typ by default and merges custom extensions", () => {
    expect(plugin.Processor).toBe(TypstProcessor);
    expect(Processor).toBe(TypstProcessor);

    const defaultProc = new TypstProcessor();
    expect(defaultProc.availableExtensions()).toEqual([".typ"]);

    const customProc = new TypstProcessor({ extensions: [".typst"] });
    expect(customProc.availableExtensions()).toEqual([".typ", ".typst"]);
  });
});

describe("textlint integration via TextlintKernel", () => {
  const kernel = new TextlintKernel();

  it("reports lint errors at exact line/column and ignores code/math", async () => {
    const source = [
      "= 導入",
      "",
      "これはTODO: 修正すべき文章です。",
      "",
      "```",
      "TODO: inside code block should be ignored",
      "```",
      "",
      "Inline `TODO: ignored` and $TODO$.",
      "",
      "- TODO: inside list item",
    ].join("\n");

    const result = await kernel.lintText(source, {
      ext: ".typ",
      filePath: "sample.typ",
      plugins: [
        {
          pluginId: "typst",
          plugin,
        },
      ],
      rules: [
        {
          ruleId: "no-todo",
          rule: ruleNoTodo,
        },
      ],
    });

    expect(result.filePath).toBe("sample.typ");
    expect(result.messages).toHaveLength(2);
    expect(result.messages[0]).toMatchObject({
      ruleId: "no-todo",
      line: 3,
      column: 4,
    });
    expect(result.messages[1]).toMatchObject({
      ruleId: "no-todo",
      line: 11,
      column: 3,
    });
  });

  it("supports textlint-filter-rule-comments with // and /* */", async () => {
    const source = [
      "// textlint-disable",
      "TODO: ignored by line comment",
      "// textlint-enable",
      "TODO: should be reported",
      "/* textlint-disable */",
      "TODO: ignored by block comment",
      "/* textlint-enable */",
    ].join("\n");

    const result = await kernel.lintText(source, {
      ext: ".typ",
      filePath: "comments.typ",
      plugins: [{ pluginId: "typst", plugin }],
      rules: [{ ruleId: "no-todo", rule: ruleNoTodo }],
      filterRules: [{ ruleId: "comments", rule: filterComments }],
    });

    expect(result.messages).toHaveLength(1);
    expect(result.messages[0]).toMatchObject({
      ruleId: "no-todo",
      line: 4,
      column: 1,
    });
  });

  it("supports auto-fixing with exact UTF-16 ranges including Japanese and emoji", async () => {
    const fixTypoRule: TextlintRuleModule = (context) => {
      const { Syntax, RuleError, report, fixer, getSource } = context;
      return {
        [Syntax.Str](node) {
          const text = getSource(node);
          const idx = text.indexOf("teh");
          if (idx !== -1) {
            report(
              node,
              new RuleError("Typo 'teh'", {
                index: idx,
                fix: fixer.replaceTextRange([idx, idx + 3], "the"),
              }),
            );
          }
        },
      };
    };

    const source = "= 日本語 😀\n\nこれは *teh* テストと #footnote[また teh です]。\n";
    const fixed = await kernel.fixText(source, {
      ext: ".typ",
      filePath: "fix.typ",
      plugins: [{ pluginId: "typst", plugin }],
      rules: [
        {
          ruleId: "fix-typo",
          rule: {
            linter: fixTypoRule,
            fixer: fixTypoRule,
          },
        },
      ],
    });

    expect(fixed.output).toBe("= 日本語 😀\n\nこれは *the* テストと #footnote[また the です]。\n");
  });
});
