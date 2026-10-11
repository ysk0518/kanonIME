const { readFileSync, realpathSync } = require('node:fs');
const { resolve, sep, relative } = require('node:path');
const ts = require('typescript');

const sourceRoot = realpathSync(resolve(__dirname, '../../entry/src/main/ets'));
const forbidden = new Set(['AppStorage', 'PersistentStorage', '$r', '$rawfile', 'ESObject']);

// Execute the product .ets files, without manually porting or copying their logic.
// Fail closed if a core module begins depending on Harmony/UI/native globals.
require.extensions['.ets'] = (module, filename) => {
  const actual = realpathSync(filename);
  if (!actual.startsWith(sourceRoot + sep)) { throw new Error('Unexpected .ets source location'); }
  let source = readFileSync(actual, 'utf8');
  const parsed = ts.createSourceFile(actual, source, ts.ScriptTarget.ES2020, true, ts.ScriptKind.TS);
  function inspect(node) {
    if (ts.isImportDeclaration(node) && !node.moduleSpecifier.text.startsWith('.')) {
      throw new Error(`Platform import in unit-test target: ${node.moduleSpecifier.text}`);
    }
    if (ts.isIdentifier(node) && forbidden.has(node.text)) {
      throw new Error(`Platform global in unit-test target: ${node.text}`);
    }
    if (ts.isCallExpression(node) && node.expression.kind === ts.SyntaxKind.ImportKeyword) {
      throw new Error('Dynamic platform loading in unit-test target');
    }
    ts.forEachChild(node, inspect);
  }
  inspect(parsed);
  if (process.env.KANON_TEST_MUTATION) {
    source = require('./source-mutations.cjs').mutate(relative(sourceRoot, actual), source,
      process.env.KANON_TEST_MUTATION);
  }
  const result = ts.transpileModule(source, {
    fileName: actual.replace(/\.ets$/, '.ts'), reportDiagnostics: true,
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS,
      esModuleInterop: true, isolatedModules: true }
  });
  const errors = result.diagnostics.filter(item => item.category === ts.DiagnosticCategory.Error);
  if (errors.length) { throw new Error(ts.formatDiagnosticsWithColorAndContext(errors, {
    getCanonicalFileName: path => path, getCurrentDirectory: () => process.cwd(), getNewLine: () => '\n'
  })); }
  module._compile(result.outputText, actual);
};
