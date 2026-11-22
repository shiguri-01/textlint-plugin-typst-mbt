import { defineConfig } from "vite-plus";

export default defineConfig({
  fmt: {
    ignorePatterns: ["_build/**", "target/**", ".mooncakes/**", "dist/**"],
  },
  lint: {
    ignorePatterns: ["_build/**", "target/**", ".mooncakes/**", "dist/**"],
    jsPlugins: [{ name: "vite-plus", specifier: "vite-plus/oxlint-plugin" }],
    rules: { "vite-plus/prefer-vite-plus-imports": "error" },
    options: { typeAware: true, typeCheck: true },
  },
  pack: {
    entry: ["src/index.ts"],
    format: ["esm", "cjs"],
    dts: true,
    clean: true,
    sourcemap: true,
    deps: {
      onlyBundle: false,
    },
    outputOptions: {
      exports: "named",
    },
  },
});
