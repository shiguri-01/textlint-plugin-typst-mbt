import type { TxtDocumentNode } from "@textlint/ast-node-types";
import { parseToTxtAst } from "../_build/js/release/build/textlint-plugin-typst.js";

/**
 * Parse Typst source text directly into a textlint TxtAST `Document` node
 * without JSON serialization/deserialization overhead.
 */
export function parse(text: string): TxtDocumentNode {
  return parseToTxtAst(text) as unknown as TxtDocumentNode;
}
