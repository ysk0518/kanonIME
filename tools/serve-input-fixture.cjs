const { createServer } = require('node:http');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');

function createFixtureServer() {
  const page = readFileSync(resolve(__dirname, '../tests/device/input.html'));
  return createServer((request, response) => {
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      response.writeHead(405, { Allow: 'GET, HEAD' }); response.end(); return;
    }
    const path = (request.url ?? '/').split('?')[0];
    if (path !== '/' && path !== '/input.html') {
      response.writeHead(404); response.end(); return;
    }
    response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-store', 'Content-Length': page.length,
      'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; form-action 'none'" });
    response.end(request.method === 'HEAD' ? undefined : page);
  });
}

if (require.main === module) {
  const args = process.argv.slice(2);
  const host = args[0] ?? '127.0.0.1';
  const port = Number(args[1] ?? '8765');
  if (args.length > 2 || !Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('Usage: node tools/serve-input-fixture.cjs [host] [port]');
  }
  const server = createFixtureServer();
  server.listen(port, host, () => console.log(`Input fixture: http://${host}:${port}/input.html`));
}
module.exports = { createFixtureServer };
