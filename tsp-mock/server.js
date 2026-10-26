// Local stand-in for the TSP (trust service provider) gateway used by Ticketing to sign ticket PDFs.
// Usage: node tsp-mock/server.js [port]  (default 5130)
//
// Ticketing calls it with two HttpClients whose BaseAddress is TSP:AuthUrl / TSP:SignUrl (must end in '/'),
// and both clients request the empty relative path ("") — so the actual hit is exactly /auth/ and /sign/.
//   TspAuthProvider:        GET  {TSP:AuthUrl}  -> TspResponse { code, data.token }        (bearer token, cached 1 min in Redis)
//   TspSignedTicketProvider: POST {TSP:SignUrl} -> TspResponse { code, data.signedData[] }  (base64 signed PDFs)
//
// The sign endpoint echoes each submitted PDF back as "signed". Nothing downstream parses the QR or the
// PDF signature locally (only the checker app does, and it cannot run against Floci), so an echo is enough
// to exercise the whole aftermath: signed upload to S3, ticket -> Generated, order -> Generated, OneID skip,
// checker gate list update, SQS message deletion. See tsp-mock/README.md for the test flow.
'use strict';
const http = require('http');

const PORT = Number(process.argv[2] || process.env.MOCK_TSP_PORT || 5130);
const TOKEN = process.env.MOCK_TSP_TOKEN || 'mock-tsp-token';

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

// Route on path suffix so /auth, /auth/ and any prefix (a stage, /tsp, ...) all work,
// matching how mock-identity tolerates prefixed identity paths. The trailing slash is dropped because the
// clients' BaseAddress ends in '/' and they request the empty relative path — the hit is exactly /auth/ and /sign/.
function route(pathname) {
  const p = pathname.length > 1 && pathname.endsWith('/') ? pathname.slice(0, -1) : pathname;
  if (p.endsWith('/auth')) return 'auth';
  if (p.endsWith('/sign')) return 'sign';
  return null;
}

const server = http.createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  if (req.method === 'OPTIONS') { res.statusCode = 204; return res.end(); }

  const pathname = new URL(req.url, 'http://localhost').pathname;
  const action = route(pathname);

  if (req.method === 'GET' && action === 'auth') {
    console.log(`auth  <- token request`);
    res.setHeader('Content-Type', 'application/json');
    return res.end(JSON.stringify({ code: 200, message: 'ok', userName: 'tsp-mock-user', data: { token: TOKEN, signedData: [] } }));
  }

  if (req.method === 'POST' && action === 'sign') {
    const raw = await readBody(req);
    let payload = {};
    try { payload = JSON.parse(raw.toString('utf8') || '{}'); } catch { /* fall through with empty payload */ }
    const docs = Array.isArray(payload.documents) ? payload.documents : [];
    const signedData = docs.map((d) => d.data);
    console.log(
      `sign  <- ${docs.length} document(s): ` +
      docs.map((d) => `${d.fileName} (${Buffer.byteLength(String(d.data || ''), 'base64')} bytes pdf, ` +
        `vds qr fields ${d.vdsData && d.vdsData.qrCodeData ? Object.keys(d.vdsData.qrCodeData).length : 0}, ` +
        `qr page ${d.vdsData && d.vdsData.qrCodePage} @ ${d.vdsData && d.vdsData.qrCodeXPosition}x${d.vdsData && d.vdsData.qrCodeYPosition})`).join('; ')
    );
    res.setHeader('Content-Type', 'application/json');
    return res.end(JSON.stringify({ code: 200, message: 'signed (mock echo)', userName: payload.userId || null, data: { token: null, signedData } }));
  }

  console.log(`unmatched ${req.method} ${pathname}`);
  res.statusCode = 404;
  res.setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify({ code: 404, message: `no mock for ${req.method} ${pathname}`, data: null }));
});

server.listen(PORT, '0.0.0.0', () => console.log(`tsp-mock on :${PORT}  (echo-signs PDFs; token '${TOKEN}')`));
