import type { TextlintPluginCreator } from "@textlint/types";
import { TypstProcessor } from "./TypstProcessor.ts";

export { parse } from "./parse.ts";
export { TypstProcessor, type TypstPluginOptions } from "./TypstProcessor.ts";
export const Processor: typeof TypstProcessor = TypstProcessor;

const plugin: TextlintPluginCreator = {
  Processor: TypstProcessor,
};

export default plugin;
