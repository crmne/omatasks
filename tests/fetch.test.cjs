// Run Fetch.py against a local HTTP server and check it caps what the shell reads.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { spawn } = require('node:child_process');

const LIMIT = 16 * 1024 * 1024;

function serve(handler) {
    return new Promise(resolve => {
        const seen = [];
        const server = http.createServer((req, res) => {
            let body = '';
            req.on('data', chunk => { body += chunk; });
            req.on('end', () => { seen.push({ method: req.method, url: req.url, headers: req.headers, body }); handler(req, res); });
            res.on('error', () => {});
        });
        server.listen(0, '127.0.0.1', () => resolve({ server, seen, base: `http://127.0.0.1:${server.address().port}` }));
    });
}

function fetch(request, raw, args = ['Fetch.py']) {
    return new Promise(resolve => {
        const child = spawn('python3', args, { stdio: ['pipe', 'pipe', 'pipe'] });
        const out = [], err = [];
        child.stdout.on('data', chunk => out.push(chunk));
        child.stderr.on('data', chunk => err.push(chunk));
        child.on('close', code => {
            const text = Buffer.concat(out), split = text.indexOf(10);
            resolve({ code, size: text.length, stderr: Buffer.concat(err).toString(), meta: JSON.parse(text.subarray(0, split)), body: text.subarray(split + 1).toString() });
        });
        child.stdin.end(raw ?? JSON.stringify({ method: 'POST', token: 'secret-token', contentType: 'application/json', body: '{"a":1}', ...request }));
    });
}

test('Fetch.py sends the request from stdin and prints the status line and body', async () => {
    const { server, seen, base } = await serve((req, res) => { res.setHeader('Content-Type', 'application/json'); res.end('{"sync_token":"next"}'); });
    try {
        const result = await fetch({ url: base + '/sync', requestId: 'stable-id' });
        assert.deepEqual(result.meta, { status: 200, retryAfter: '' });
        assert.equal(result.body, '{"sync_token":"next"}');
        assert.equal(seen[0].headers.authorization, 'Bearer secret-token');
        assert.equal(seen[0].headers['x-request-id'], 'stable-id');
        assert.equal(seen[0].headers['content-type'], 'application/json');
        assert.equal(seen[0].body, '{"a":1}');
        assert.equal(result.stderr, '');
    } finally { server.close(); }
});

test('Fetch.py stops reading an endless response at the cap', async () => {
    const block = Buffer.alloc(1024 * 1024, 'x');
    let sent = 0;
    const { server, base } = await serve((req, res) => {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        const pump = () => { while (sent < 256 * 1024 * 1024 && res.write(block)) sent += block.length; if (sent < 256 * 1024 * 1024 && !res.destroyed) res.once('drain', pump); };
        pump();
    });
    try {
        const result = await fetch({ url: base + '/sync' });
        assert.deepEqual(result.meta, { status: 0, error: 'too-large' });
        assert.equal(result.body, '');
        assert.ok(result.size < 1024, 'the shell reads only the status line');
        assert.ok(sent < 64 * 1024 * 1024, `the server could push only ${sent} bytes before the helper stopped`);
    } finally { server.closeAllConnections(); server.close(); }
});

test('Fetch.py refuses a declared length over the cap without reading the body', async () => {
    const { server, base } = await serve((req, res) => { res.writeHead(200, { 'Content-Length': String(LIMIT + 1) }); res.write('{'); });
    try {
        const result = await fetch({ url: base + '/sync' });
        assert.deepEqual(result.meta, { status: 0, error: 'too-large' });
    } finally { server.closeAllConnections(); server.close(); }
});

test('Fetch.py accepts a body exactly at the cap', async () => {
    const body = Buffer.alloc(LIMIT, ' ');
    const { server, base } = await serve((req, res) => { res.end(body); });
    try {
        const result = await fetch({ url: base + '/sync' });
        assert.equal(result.meta.status, 200);
        assert.equal(result.body.length, LIMIT);
    } finally { server.close(); }
});

test('Fetch.py reports failures with Retry-After and no body', async () => {
    const { server, base } = await serve((req, res) => { res.writeHead(429, { 'Retry-After': '120' }); res.end('slow down'); });
    try {
        const result = await fetch({ url: base + '/sync' });
        assert.deepEqual(result.meta, { status: 429, retryAfter: '120' });
        assert.equal(result.body, '');
    } finally { server.close(); }
});

test('Fetch.py never follows a redirect with the token', async () => {
    const { server, seen, base } = await serve((req, res) => {
        if (req.url === '/elsewhere') { res.end('{}'); return; }
        res.writeHead(302, { Location: '/elsewhere' }); res.end();
    });
    try {
        const result = await fetch({ url: base + '/sync' });
        assert.equal(result.meta.status, 302);
        assert.deepEqual(seen.map(r => r.url), ['/sync']);
    } finally { server.close(); }
});

test('Fetch.py answers status 0 without details when the network fails or the request is malformed', async () => {
    const { server, base } = await serve(() => {});
    server.close();
    const failed = await fetch({ url: base + '/sync' });
    assert.deepEqual(failed.meta, { status: 0, error: 'unreachable' });
    assert.equal(failed.stderr, '');
    assert.doesNotMatch(JSON.stringify(failed), /secret-token/);
    assert.deepEqual((await fetch(null, 'not json')).meta, { status: 0, error: 'request' });
    assert.deepEqual((await fetch(null, '[]')).meta, { status: 0, error: 'request' });
});

// Runs Fetch.py with a resolver answering `addresses`, where connecting to any
// address but 127.0.0.1 hangs, as on a dead path, and logs each attempt to stderr.
function deadPaths(addresses) {
    return ['-c', `
import runpy, socket, sys
real = socket.socket.connect
def connect(self, target):
    print(target[0], self.gettimeout(), file=sys.stderr)
    if target[0] == '127.0.0.1':
        return real(self, target)
    raise TimeoutError
socket.socket.connect = connect
socket.getaddrinfo = lambda host, port, **_: [
    (socket.AF_INET6 if ':' in a else socket.AF_INET, socket.SOCK_STREAM, 6, '', (a, port)) for a in ${JSON.stringify(addresses)}]
runpy.run_path('Fetch.py', run_name='__main__')
`];
}

test('Fetch.py reaches IPv4 past a dead IPv6 path that lists many addresses', async () => {
    const { server, seen, base } = await serve((req, res) => { res.end('{"sync_token":"next"}'); });
    try {
        const url = base.replace('127.0.0.1', 'api.test') + '/sync';
        const result = await fetch({ url }, undefined, deadPaths(['::1', '::2', '::3', '::4', '::5', '127.0.0.1']));
        assert.equal(result.meta.status, 200);
        assert.equal(seen.length, 1);
        assert.deepEqual(result.stderr.trim().split('\n'), ['::1 4.0', '127.0.0.1 4.0']);
    } finally { server.close(); }
});

test('Fetch.py gives up within the deadline when no address answers, and says nothing was sent', async () => {
    const addresses = Array.from({ length: 8 }, (_, i) => '::' + (i + 1));
    const result = await fetch({ url: 'http://api.test:1/sync' }, undefined, deadPaths(addresses));
    assert.deepEqual(result.meta, { status: 0, error: 'unreachable' });
    assert.equal(result.stderr.trim().split('\n').length, 4);
});

test('Fetch.py does not call a request unsent once the connection was made', async () => {
    const { server, base } = await serve((req, res) => { res.destroy(); });
    try {
        const result = await fetch({ url: base + '/tasks/1/close', requestId: 'stable-id' });
        assert.deepEqual(result.meta, { status: 0, error: 'network' });
    } finally { server.close(); }
});
