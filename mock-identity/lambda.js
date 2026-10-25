// Lambda entrypoint (API Gateway proxy event, payload v1 or v2) so the same mock can be deployed to Floci Lambda.
// Handler: lambda.handler   (see README for the create-function steps)
'use strict';
const { handle } = require('./handler');

exports.handler = async event => {
  const method = event.httpMethod || (event.requestContext && event.requestContext.http && event.requestContext.http.method) || 'GET';
  const path = event.path || event.rawPath || '/';
  const raw = event.isBase64Encoded ? Buffer.from(event.body || '', 'base64').toString() : event.body;
  let body = {};
  try { body = raw ? JSON.parse(raw) : {}; } catch { /* non-JSON body */ }
  const headers = Object.fromEntries(Object.entries(event.headers || {}).map(([k, v]) => [k.toLowerCase(), v]));
  const out = await handle({ method, path, headers, query: event.queryStringParameters || {}, body });
  return {
    statusCode: out.statusCode,
    headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
    body: JSON.stringify(out.body),
  };
};
