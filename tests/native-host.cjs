const { readFileSync, writeFileSync, mkdirSync, mkdtempSync, readdirSync, statSync } = require('node:fs');
const { resolve, join } = require('node:path');
const { spawnSync } = require('node:child_process');
const { createHash } = require('node:crypto');

const root = resolve(__dirname, '..');
function hash(path) { return createHash('sha256').update(readFileSync(path)).digest('hex'); }

function main() {
  if (process.argv.length !== 4 || process.argv[2] !== '--mozc') {
    console.error('Usage: node tests/native-host.cjs --mozc <session_handler_main executable>');
    return 2;
  }
  const executable = resolve(process.argv[3]);
  if (!statSync(executable).isFile()) { throw new Error('Mozc host executable is not a file'); }
  const suite = join(__dirname, 'integration');
  const setup = readFileSync(join(suite, 'setup.tsv'), 'utf8').trimEnd() + '\n';
  const files = readdirSync(join(suite, 'cases')).filter(name => /^H\d+-.*\.tsv$/.test(name)).sort();
  if (files.length === 0) { throw new Error('No Mozc host fixtures found'); }
  const outputRoot = join(root, '.local', 'native-host');
  mkdirSync(outputRoot, { recursive: true });
  const runDirectory = mkdtempSync(join(outputRoot, 'run-'));
  const report = {
    scope: 'upstream-mozc-host-session', dictionary: 'oss', startedAt: new Date().toISOString(),
    executableSha256: hash(executable), setupSha256: hash(join(suite, 'setup.tsv')),
    bridgeSourceSha256: hash(join(root, 'native/bridge/kanon_bridge.cc')),
    applicationLibrarySha256: hash(join(root, 'entry/libs/arm64-v8a/libkanon_bridge.so')),
    checks: []
  };

  function execute(name, body, expectedFailure = false) {
    const caseDirectory = join(runDirectory, name);
    mkdirSync(caseDirectory);
    const input = join(caseDirectory, 'input.tsv');
    const profile = join(caseDirectory, 'profile');
    // Upstream creates this path itself; an existing directory fails on Windows.
    writeFileSync(input, setup + body.trimEnd() + '\n', 'utf8');
    // --test must be paired with --dictionary=oss: otherwise upstream uses mock data.
    const result = spawnSync(executable, ['--test', '--dictionary=oss', `--input=${input}`, `--profile=${profile}`], {
      cwd: caseDirectory, input: '', encoding: 'utf8', timeout: 30000, maxBuffer: 8 * 1024 * 1024
    });
    const output = (result.stdout ?? '') + (result.stderr ?? '');
    writeFileSync(join(caseDirectory, 'output.log'), output, 'utf8');
    const passed = !result.error && (expectedFailure ?
      result.status === 1 && output.includes('[ FAILED ]') && output.includes('Expected preedit:') :
      result.status === 0 && output.includes('[ PASSED ]') && !output.includes('ERROR:'));
    report.checks.push({ name, expectedFailure, passed, exitCode: result.status,
      signal: result.signal, error: result.error?.code ?? null, inputSha256: hash(input) });
    console.log(`${name}: ${passed ? 'PASS' : 'FAIL'}`);
    return passed;
  }

  // Prove that the tool evaluates assertions rather than merely accepting input.
  execute('control-wrong-preedit', 'SEND_KEYS\tki\nEXPECT_PREEDIT\tKANON_EXPECTED_FAILURE', true);
  for (const file of files) {
    const body = readFileSync(join(suite, 'cases', file), 'utf8');
    if (!/^EXPECT_/m.test(body)) { throw new Error(`Fixture has no assertions: ${file}`); }
    execute(file.replace(/\.tsv$/, ''), body);
  }
  report.finishedAt = new Date().toISOString();
  writeFileSync(join(runDirectory, 'report.json'), JSON.stringify(report, null, 2) + '\n', 'utf8');
  console.log(`Report: ${join(runDirectory, 'report.json')}`);
  return report.checks.every(check => check.passed) ? 0 : 1;
}

try { process.exitCode = main(); }
catch (error) { console.error(`ENVIRONMENT/SETUP ERROR: ${error.message}`); process.exitCode = 2; }
