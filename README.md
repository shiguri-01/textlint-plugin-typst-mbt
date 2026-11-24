# @shiguri/textlint-plugin-typst

A [textlint](https://textlint.github.io/) plugin for [Typst](https://typst.app/) documents.

> [!WARNING]
> This is an experimental project. AST mappings and APIs may change without notice.

- Lints `.typ` files, including prose inside tables, figures, footnotes, control flow, and custom macros.
- Ignores code blocks, inline code, math equations, labels, and Typst statements (`#let`, `#set`, `#show`, `#import`, `#include`).
- Supports `textlint --fix`, including multibyte characters and emoji.
- Supports [`textlint-filter-rule-comments`](https://github.com/textlint/textlint-filter-rule-comments) via `//` and `/* ... */` comments.

## Installation

```bash
vp add -D textlint @shiguri/textlint-plugin-typst
```

## Usage

Enable the plugin in `.textlintrc.json`:

```json
{
  "plugins": ["@shiguri/typst"],
  "rules": {
    "no-todo": true
  }
}
```

Run textlint on your `.typ` files:

```bash
vp exec textlint "**/*.typ"
```

### Options

By default, this plugin handles `.typ` files. To lint additional file extensions, pass an `extensions: string[]` option under `plugins["@shiguri/typst"]`.

### Ignoring Sections with Comments

With [`textlint-filter-rule-comments`](https://github.com/textlint/textlint-filter-rule-comments), both `//` and `/* ... */` comments work as directives:

```typst
// textlint-disable
TODO: This line is ignored by textlint.
// textlint-enable
```

## Typst-to-TxtAST Mapping

| Typst Syntax                                           | TxtAST Node                        | Notes                                                                    |
| ------------------------------------------------------ | ---------------------------------- | ------------------------------------------------------------------------ |
| `= Heading`, `#heading[...]`                           | `Header`                           | Depth 1–6                                                                |
| Text, escapes, shorthands                              | `Paragraph` / `Str`                |                                                                          |
| `*strong*`, `#strong[...]`                             | `Strong`                           |                                                                          |
| `_emph_`, `#emph[...]`                                 | `Emphasis`                         |                                                                          |
| `#strike[...]`                                         | `Delete`                           |                                                                          |
| `-`, `+`, `1.`, `/ term: desc`                         | `List` / `ListItem`                |                                                                          |
| `#quote[...]`                                          | `BlockQuote`                       |                                                                          |
| `#line(...)`                                           | `HorizontalRule`                   |                                                                          |
| `#table(...)`                                          | `Table` / `TableRow` / `TableCell` | Includes `table.header`, `table.footer`, `table.cell`                    |
| URL, `#link`, `@ref[...]`                              | `Link`                             |                                                                          |
| `#image(...)`                                          | `Image`                            |                                                                          |
| `\`                                                    | `Break`                            | Hard line break                                                          |
| `` `code` ``, `#raw(...)`, `$math$`, `@ref`, `<label>` | `Code`                             |                                                                          |
| ` ```...``` `, `$ ... $`, Typst statements             | `CodeBlock`                        | `#let`, `#set`, `#show`, `#import`, `#include`, `#raw(..., block: true)` |
| `// ...`, `/* ... */`                                  | `Comment`                          |                                                                          |
| Containers, control flow, macros                       | _(unwrapped)_                      | Unwraps `#figure`, `#grid`, `#if`, `#for`, `#context`, `#footnote`, etc. |

## API

The package also exports `parse`, `TypstProcessor`, and the default plugin object for programmatic use (e.g. with `@textlint/kernel`):

```ts
import { parse } from "@shiguri/textlint-plugin-typst";

const ast = parse("= Hello Typst\n\nThis is *bold* and _italic_.\n");
```

## Development

Prerequisites: [MoonBit](https://www.moonbitlang.com/download/) (`moon`) and [Vite+](https://viteplus.dev/) (`vp`).

```bash
vp install       # Install dependencies
vp run fmt       # Format files
vp run check     # Check formatting, lint, and types
vp run test      # Run all tests (or use test:mbt / test:js)
vp run build     # Build the plugin
vp run verify    # Run the full CI checks locally
```

## Acknowledgments

This plugin uses [moonbitlang/typst.mbt](https://github.com/moonbitlang/typst.mbt) for parsing Typst syntax and was inspired by the official [textlint/textlint-plugin-typst](https://github.com/textlint/textlint-plugin-typst).

## License

[MIT](LICENSE) (see [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES) for bundled components)
