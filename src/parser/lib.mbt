///|
/// Parse Typst source text into a textlint TxtAST encoded as a JSON string.
/// Exported to JavaScript / WebAssembly hosts.
#export_name("parse_to_txt_ast_json")
pub fn parse_to_txt_ast_json(text : String) -> String {
  parse_typst_to_txt_ast(text).to_json().stringify()
}
