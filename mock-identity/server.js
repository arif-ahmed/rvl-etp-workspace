// Local HTTP entrypoint for the identity/serverless mock.  Usage: node mock-identity/server.js [port]  (default 5120)
'use strict';
const http = require('http');
const { handle } = require('./handler');

const PORT = Number(process.argv[2] || process.env.MOCK_IDENTITY_PORT || 5120);

http.createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,DELETE,OPTIONS');
  if (req.method === 'OPTIONS') { res.statusCode = 204; return res.end(); }

  let raw = '';
  for await (const c of req) raw += c;
  let body = {};
  try { body = raw ? JSON.parse(raw) : {}; } catch { /* non-JSON body */ }

  const url = new URL(req.url, 'http://localhost');
  const out = await handle({ method: req.method, path: url.pathname, headers: req.headers, query: Object.fromEntries(url.searchParams), body });
  res.statusCode = out.statusCode;
  res.setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify(out.body));
}).listen(PORT, '0.0.0.0', () => console.log(`mock-identity on :${PORT}  (OTP ${process.env.MOCK_OTP || '123456'}, Floci ${process.env.AWS_ENDPOINT_URL || 'http://localhost:4566'})`));
