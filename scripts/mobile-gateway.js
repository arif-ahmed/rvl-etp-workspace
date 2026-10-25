// Local API gateway for the Flutter apps (scripts/Setup-MobileApps.ps1 starts it; no npm install needed).
//
// The deployed system has ONE host that fans out by path (<host>/booking/api/v1/..., <host>/event/api/v1/...).
// Locally every service has its own port, so this tiny reverse proxy does the fan-out:
//   http://localhost:5200/<prefix>/...  ->  http://localhost:<port>/<prefix>/...
//
// Usage: node scripts/mobile-gateway.js [port]      (default 5200, listens on all interfaces)
'use strict';
const http = require('http');

const PORT = Number(process.argv[2] || process.env.GATEWAY_PORT || 5200);

// prefix -> backend port (see README "Services" table)
const ROUTES = {
  admin: 5101, booking: 5102, event: 5103, pushnotification: 5105, scheduler: 5106,
  ticketchecker: 5107, ticketing: 5108, userissue: 5110, utility: 5111,
};

const send = (res, status, body) => {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify(body));
};

http.createServer((req, res) => {
  const prefix = req.url.split('?')[0].split('/')[1] || '';

  if (prefix === 'health') return send(res, 200, { status: 'ok', routes: ROUTES });

  // The "identity" API (sign-up, OTP, profile) has no source in any repo: forward to mock-identity (node mock-identity/server.js).
  if (prefix === 'identity') {
    const up = http.request(
      { host: 'localhost', port: Number(process.env.MOCK_IDENTITY_PORT || 5120), path: req.url.replace(/^\/identity/, '') || '/', method: req.method, headers: { ...req.headers, host: 'localhost' } },
      r => { res.writeHead(r.statusCode, r.headers); r.pipe(res); },
    );
    up.on('error', e => send(res, 502, { status_message: 'mock_identity_unreachable', detail: e.code || String(e) }));
    return req.pipe(up);
  }

  const port = ROUTES[prefix];
  if (!port) return send(res, 404, { error: 'no_route', prefix });

  const upstream = http.request(
    { host: 'localhost', port, path: req.url, method: req.method, headers: { ...req.headers, host: 'localhost:' + port } },
    r => { res.writeHead(r.statusCode, r.headers); r.pipe(res); },
  );
  upstream.on('error', e => send(res, 502, { error: 'upstream_unreachable', prefix, port, detail: e.code || String(e) }));
  req.pipe(upstream);
}).listen(PORT, '0.0.0.0', () => console.log(`mobile gateway on :${PORT} -> ${Object.keys(ROUTES).join(', ')}`));
