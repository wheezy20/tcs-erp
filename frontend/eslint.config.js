import js from "@eslint/js";
import eslintPluginPrettier from "eslint-plugin-prettier/recommended";
import globals from "globals";
import reactHooks from "eslint-plugin-react-hooks";
import reactRefresh from "eslint-plugin-react-refresh";
import tseslint from "typescript-eslint";

export default tseslint.config(
  {
    ignores: [
      "dist",
      ".output",
      ".vinxi",
      ".vercel",
      ".wrangler",
      ".tanstack",
      "src/lib/database.types.ts",
      "src/routeTree.gen.ts",
    ],
  },
  {
    extends: [js.configs.recommended, ...tseslint.configs.recommended],
    files: ["**/*.{ts,tsx}"],
    languageOptions: {
      ecmaVersion: 2020,
      globals: globals.browser,
    },
    plugins: {
      "react-hooks": reactHooks,
      "react-refresh": reactRefresh,
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
      "no-restricted-imports": [
        "error",
        {
          paths: [
            {
              name: "server-only",
              message:
                "TanStack Start does not use the Next.js `server-only` package. Rename the module to `*.server.ts` or mark it with `@tanstack/react-start/server-only`.",
            },
          ],
        },
      ],
      "react-refresh/only-export-components": ["warn", { allowConstantExport: true }],
      "@typescript-eslint/no-unused-vars": "off",
    },
  },
  // Admissions carry-forwards as lint errors (docs/DESIGN.md, "Project
  // layout"): explicit column lists only, and no token hash column, ever.
  // Best-effort (a computed string evades it); test-runner also greps.
  {
    files: ["src/modules/admissions/**/*.{ts,tsx}"],
    rules: {
      "no-restricted-syntax": [
        "error",
        {
          selector: "CallExpression[callee.property.name='select'] > Literal[value=/\\*/]",
          message: "Select explicit columns, never *.",
        },
        {
          selector: "Literal[value=/token_hash/]",
          message: "Never read a token hash column.",
        },
        {
          selector: "TemplateElement[value.raw=/token_hash/]",
          message: "Never read a token hash column.",
        },
      ],
    },
  },
  eslintPluginPrettier,
);
