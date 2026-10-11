const test = require('node:test');
const assert = require('node:assert/strict');
const { request } = require('node:http');
const { createFixtureServer } = require('../../tools/serve-input-fixture.cjs');

function fetchFixture(port, path, method = 'GET') {
  return new Promise((resolve, reject) => {
    const req = request({ host: '127.0.0.1', port, path, method }, response => {
      let body = '';
      response.setEncoding('utf8');
      response.on('data', data => { body += data; });
      response.on('end', () => resolve({ status: response.statusCode, headers: response.headers, body }));
    });
    req.on('error', reject); req.end();
  });
}

test('P15: web input fixture serves only the fixed page and does not accept submitted text', async () => {
  const server = createFixtureServer();
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const port = server.address().port;
    const page = await fetchFixture(port, '/input.html');
    assert.equal(page.status, 200);
    assert.match(page.body, /id="kanon_web_input"/);
    assert.match(page.body, /id="kanon_web_textarea"/);
    assert.equal(page.headers['cache-control'], 'no-store');
    assert.match(page.headers['content-security-policy'], /form-action 'none'/);
    assert.equal((await fetchFixture(port, '/input.html', 'HEAD')).body, '');
    assert.equal((await fetchFixture(port, '/')).body, page.body);
    assert.equal((await fetchFixture(port, '/entry/src/main/ets/pages/Index.ets')).status, 404);
    assert.equal((await fetchFixture(port, '/..%2fREADME.md')).status, 404);
    assert.equal((await fetchFixture(port, '/input.html', 'POST')).status, 405);
  } finally { await new Promise(resolve => server.close(resolve)); }
});
