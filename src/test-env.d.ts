declare module "textlint-filter-rule-comments" {
  import type { TextlintFilterRuleReporter } from "@textlint/types";
  const rule: TextlintFilterRuleReporter;
  export default rule;
}

declare module "textlint-rule-no-todo" {
  import type { TextlintRuleModule } from "@textlint/types";
  const rule: TextlintRuleModule;
  export default rule;
}
