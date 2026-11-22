import type {
  TextlintMessage,
  TextlintPluginOptions,
  TextlintPluginPostProcessResult,
  TextlintPluginPreProcessResult,
  TextlintPluginProcessor,
} from "@textlint/types";
import { parse } from "./parse.ts";

export interface TypstPluginOptions extends TextlintPluginOptions {
  extensions?: string[];
}

export class TypstProcessor implements TextlintPluginProcessor {
  private readonly extensions: string[];

  constructor(options: TypstPluginOptions = {}) {
    this.extensions = Array.isArray(options.extensions)
      ? options.extensions.filter((ext): ext is string => typeof ext === "string")
      : [];
  }

  availableExtensions(): string[] {
    return [".typ", ...this.extensions];
  }

  processor(_ext: string): {
    preProcess(text: string, filePath?: string): TextlintPluginPreProcessResult;
    postProcess(messages: TextlintMessage[], filePath?: string): TextlintPluginPostProcessResult;
  } {
    return {
      preProcess(text: string, _filePath?: string): TextlintPluginPreProcessResult {
        return parse(text);
      },
      postProcess(messages: TextlintMessage[], filePath?: string): TextlintPluginPostProcessResult {
        return {
          messages,
          filePath: filePath ?? "<typst>",
        };
      },
    };
  }
}
