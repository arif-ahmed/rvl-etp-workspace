// Mock of the missing Identity/Auth + Serverless Lambda APIs (no source in any repo; contract inferred from callers).
// Pure handler: handle({ method, path, headers, query, body }) -> { statusCode, body }.
// Used by server.js (local HTTP) and lambda.js (API Gateway proxy event) - no dependencies, Node 18+.
//
// Cognito is Floci (AWS_ENDPOINT_URL, default http://localhost:4566), called over the raw JSON protocol.
'use strict';
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const FLOCI = process.env.AWS_ENDPOINT_URL || 'http://localhost:4566';
const REGION = process.env.AWS_REGION || 'ap-southeast-1';
const OTP = process.env.MOCK_OTP || '123456';
const OTP_TTL_MS = Number(process.env.MOCK_OTP_TTL_MS || 5 * 60 * 1000);
const SENDER = process.env.MOCK_EMAIL_SENDER || 'noreply@etp.local';
const STORE_FILE = process.env.MOCK_STORE_FILE || path.join(__dirname, 'data.json');
const USER_POOL_NAME = process.env.MOCK_USER_POOL_NAME || 'etp-user';

// ---- state (pending registrations, OTPs, profiles); persisted so restarts keep sign-ups ----
const state = { pending: {}, profiles: {}, otps: {}, outbox: [] };
try { Object.assign(state, JSON.parse(fs.readFileSync(STORE_FILE, 'utf8'))); } catch { /* first run */ }
const save = () => { try { fs.writeFileSync(STORE_FILE, JSON.stringify(state, null, 2)); } catch { /* read-only fs (Lambda) */ } };

// Abandoned sign-ups and stale OTPs are dropped after PENDING_TTL_MS (default 30 min).
const PENDING_TTL_MS = Number(process.env.MOCK_PENDING_TTL_MS || 30 * 60 * 1000);
function purgeExpired() {
  const now = Date.now();
  for (const [id, p] of Object.entries(state.pending)) if (now - (p.cached_at || 0) > PENDING_TTL_MS) delete state.pending[id];
  for (const [k, o] of Object.entries(state.otps)) if (now > o.expires) delete state.otps[k];
}
purgeExpired();

// ---- helpers ----
const ok = (status_message, data, extra) => ({ statusCode: 200, body: { status: 'success', message: status_message, status_message, ...(data !== undefined ? { data } : {}), ...extra } });
const fail = (statusCode, status_message) => ({ statusCode, body: { status: 'error', message: status_message, status_message } });

// +8801700000011 is the Cognito username in the seed data; accept 01..., 8801..., +8801...
const normPhone = p => {
  const d = String(p || '').replace(/[^\d+]/g, '');
  if (d.startsWith('+')) return d;
  if (d.startsWith('880')) return '+' + d;
  if (d.startsWith('0')) return '+88' + d;
  return '+880' + d;
};
const jwtPayload = tok => { try { return JSON.parse(Buffer.from(String(tok).split('.')[1], 'base64').toString()); } catch { return {}; } };

async function cognito(target, payload) {
  const r = await fetch(FLOCI + '/', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-amz-json-1.1', 'X-Amz-Target': 'AWSCognitoIdentityProviderService.' + target },
    body: JSON.stringify(payload),
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) { const e = new Error(j.message || j.Message || target + ' failed'); e.code = String(j.__type || '').split('#').pop(); throw e; }
  return j;
}

let poolIdCache;
async function userPoolId() {
  if (process.env.MOCK_USER_POOL_ID) return process.env.MOCK_USER_POOL_ID;
  if (poolIdCache) return poolIdCache;
  const { UserPools = [] } = await cognito('ListUserPools', { MaxResults: 60 });
  const p = UserPools.find(x => x.Name === USER_POOL_NAME);
  if (!p) throw new Error(`Cognito pool '${USER_POOL_NAME}' not found in Floci - run floci/seed-users.ps1`);
  return (poolIdCache = p.Id);
}

const attr = (user, name) => ((user.UserAttributes || user.Attributes || []).find(a => a.Name === name) || {}).Value || '';
async function getUserByPhone(phone) {
  try { return await cognito('AdminGetUser', { UserPoolId: await userPoolId(), Username: phone }); }
  catch (e) { if (e.code === 'UserNotFoundException') return null; throw e; }
}
async function getUserBySub(sub) {
  const { Users = [] } = await cognito('ListUsers', { UserPoolId: await userPoolId(), Filter: `sub = "${sub}"`, Limit: 1 });
  return Users[0] || null;
}

// Email OTPs go through Floci SES (best effort); SMS OTPs are only logged + recorded in the outbox.
async function sendEmail(to, subject, text) {
  const form = new URLSearchParams({ Action: 'SendEmail', Version: '2010-12-01', Source: SENDER, 'Destination.ToAddresses.member.1': to, 'Message.Subject.Data': subject, 'Message.Body.Text.Data': text });
  try {
    const r = await fetch(FLOCI + '/', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded', Authorization: `AWS4-HMAC-SHA256 Credential=test/20260101/${REGION}/ses/aws4_request, SignedHeaders=host, Signature=x` }, body: form });
    return r.ok;
  } catch { return false; }
}

async function issueOtp(type, destination, purpose) {
  const key = `${type}:${type === 'sms' ? normPhone(destination) : String(destination).toLowerCase()}`;
  state.otps[key] = { otp: OTP, expires: Date.now() + OTP_TTL_MS, purpose };
  let delivered = 'logged';
  if (type === 'email' && await sendEmail(destination, 'Your ETP verification code', `Your verification code is ${OTP}`)) delivered = 'ses';
  state.outbox.push({ at: new Date().toISOString(), type, destination, otp: OTP, purpose, delivered });
  state.outbox = state.outbox.slice(-50);
  console.log(`[mock-identity] OTP ${OTP} -> ${type} ${destination} (${purpose}, ${delivered})`);
  save();
}
function checkOtp(type, destination, otp) {
  const key = `${type}:${type === 'sms' ? normPhone(destination) : String(destination).toLowerCase()}`;
  const rec = state.otps[key];
  if (!rec) return otp === OTP ? null : 'invalid_otp';   // 123456 always works, even without a send
  if (Date.now() > rec.expires) return 'otp_has_expired';
  return otp === rec.otp ? null : 'invalid_otp';
}

const profileFor = (user, extra = {}) => {
  const sub = attr(user, 'sub');
  const p = { ...(state.profiles[sub] || {}), ...extra };
  const vtype = p.verification_type || '', vid = p.verification_id || '';
  const v = { verification_id: vid, verification_type: vtype };
  return {
    user_id: sub, temp_user_id: p.temp_user_id || sub, name: attr(user, 'name') || p.name || '', phone: attr(user, 'phone_number'),
    email: attr(user, 'email'), address: p.address || '', dob: p.dob || '', role: attr(user, 'custom:role') || 'user',
    verified: true, isProfileCompleted: String(Boolean(p.address && p.dob && vid)), registration_datetime: p.registered_at || '2026-01-01T00:00:00Z',
    ...(p.one_id ? { one_id: p.one_id } : {}), ...(p.sso_provider ? { sso_provider: p.sso_provider } : {}),
    nonsensitive_data: { ekyc: { verified: 'true', data: '' }, verification: v },
    sensitive_data: { ekyc: { verified: 'true', data: '' }, payment: { verified: 'true', id: '' }, verification: v },
  };
};

// ---- routes (matched on path suffix so /identity/..., /p/identity/..., a stage prefix etc. all work) ----
const routes = {
  'POST /user/register-cached': async ({ body }) => {
    const phone = normPhone(body.phone);
    if (!body.name || !body.phone || !body.email) return fail(400, 'missing_required_fields');
    if (body.verification_type && !body.verification_id) return fail(400, 'passport_or_nid_required');
    if (await getUserByPhone(phone)) return fail(400, 'user_already_exists');
    const id = crypto.randomUUID();
    purgeExpired();
    state.pending[id] = { ...body, phone, temp_user_id: id, cached_at: Date.now() };
    save();
    return ok('user_data_saved', { user_id: id, temp_user_id: id });
  },

  'POST /otp/send-otp': async ({ body }) => {
    if (!['sms', 'email'].includes(body.type) || !body.destination) return fail(400, 'invalid_request');
    await issueOtp(body.type, body.destination, 'register');
    return ok('otp_generated_and_enqueued_successfully');
  },

  'POST /otp/verify-otp': async ({ body }) => {
    const err = checkOtp(body.type, body.destination, String(body.otp));
    if (err) return fail(400, err);
    if (body.type === 'sms') {
      const phone = normPhone(body.destination);
      const found = Object.entries(state.pending).find(([, v]) => v.phone === phone);
      return ok('sms_otp_verified_successfully', { user_id: found ? found[0] : crypto.randomUUID() });
    }
    return ok('email_otp_verified_successfully');
  },

  'POST /user/register': async ({ body }) => {
    const pend = state.pending[body.user_id];
    if (!pend) return fail(404, 'user_not_found');
    if (!body.password) return fail(400, 'invalid_request');
    const pool = await userPoolId();
    if (await getUserByPhone(pend.phone)) return fail(400, 'user_already_exists');
    const attrs = [
      ['phone_number', pend.phone], ['name', pend.name], ['email', pend.email], ['custom:role', 'user'],
      ['email_verified', 'true'], ['phone_number_verified', 'true'],
    ].map(([Name, Value]) => ({ Name, Value }));
    const created = await cognito('AdminCreateUser', { UserPoolId: pool, Username: pend.phone, MessageAction: 'SUPPRESS', UserAttributes: attrs });
    await cognito('AdminSetUserPassword', { UserPoolId: pool, Username: pend.phone, Password: body.password, Permanent: true });
    const sub = attr(created.User, 'sub');
    state.profiles[sub] = {
      temp_user_id: body.user_id, address: body.address || pend.address || '', dob: pend.dob || '',
      verification_type: pend.verification_type || '', verification_id: pend.verification_id || '', registered_at: new Date().toISOString(),
    };
    // The real user now lives in the pool: discard the temporary record and its OTPs.
    delete state.pending[body.user_id];
    delete state.otps[`sms:${pend.phone}`];
    delete state.otps[`email:${String(pend.email).toLowerCase()}`];
    save();
    return ok('user_registered_successfully', { user_id: sub });
  },

  'GET /user/my-profile': async ({ headers }) => {
    const t = jwtPayload(String(headers.authorization || '').replace(/^Bearer\s+/i, ''));
    const u = (t.sub && await getUserBySub(t.sub)) || (t.username && await getUserByPhone(t.username));
    if (!u) return fail(404, 'user_not_found');
    return { statusCode: 200, body: { user_data: profileFor(u) } };   // portal reads user_data directly
  },

  'PUT /user/my-profile': async ({ headers, body }) => {
    const t = jwtPayload(String(headers.authorization || '').replace(/^Bearer\s+/i, ''));
    if (!t.sub) return fail(401, 'unauthorized');
    state.profiles[t.sub] = { ...(state.profiles[t.sub] || {}), ...['verification_id', 'verification_type', 'address', 'dob'].reduce((a, k) => (k in body ? { ...a, [k]: body[k] } : a), {}) };
    save();
    return ok('profile_updated_successfully');
  },

  'POST /otp/password-reset-request': async ({ body }) => {
    const phone = normPhone(body.phone);
    if (!(await getUserByPhone(phone))) return fail(404, 'phone_number_not_found');
    await issueOtp('sms', phone, 'password-reset');
    return ok('otp_generated_and_enqueued_successfully');
  },

  'POST /otp/password-reset': async ({ body }) => {
    const phone = normPhone(body.phone);
    if (!(await getUserByPhone(phone))) return fail(404, 'phone_number_not_found');
    const err = checkOtp('sms', phone, String(body.otp));
    if (err) return fail(400, err);
    await cognito('AdminSetUserPassword', { UserPoolId: await userPoolId(), Username: phone, Password: body.password, Permanent: true });
    return ok('password_reset_successfully');
  },

  'DELETE /user/delete-my-profile': async ({ headers }) => {
    const t = jwtPayload(String(headers.authorization || '').replace(/^Bearer\s+/i, ''));
    const u = t.sub && await getUserBySub(t.sub);
    if (!u) return fail(404, 'user_not_found');
    await cognito('AdminDeleteUser', { UserPoolId: await userPoolId(), Username: u.Username });
    delete state.profiles[t.sub];
    save();
    return ok('user_deleted_successfully');
  },

  'POST /user/register-sso': async ({ headers, body }) => {
    const t = jwtPayload(String(headers.authorization || '').replace(/^Bearer\s+/i, ''));
    const sub = body.cognito_sub || t.sub;
    if (!sub) return fail(400, 'invalid_request');
    state.profiles[sub] = { ...(state.profiles[sub] || {}), sso_provider: 'OneID', registered_at: new Date().toISOString() };
    save();
    return ok('user_registered_successfully', { user_id: sub });
  },

  'GET /user/allowed-app-version': async () => ok('success', {
    up: { android: { version: '1.0.0', build_number: '1', app_link: '' }, ios: { version: '1.0.0', build_number: '1', app_link: '' } },
    tc: { android: { version: '1.0.0', build_number: '1', app_link: '' }, ios: { version: '1.0.0', build_number: '1', app_link: '' } },
  }),

  // Serverless API (backend ServerlessClient): bulk user lookup by Cognito sub
  'GET /user/get-bulk-users': async ({ query }) => {
    const ids = String(query.user_ids || '').split(',').map(s => s.trim()).filter(Boolean);
    const out = [];
    for (const id of ids) {
      const u = await getUserBySub(id);
      if (!u) continue;
      const p = state.profiles[id] || {};
      out.push({ user_id: id, name: attr(u, 'name'), phone: attr(u, 'phone_number'), email: attr(u, 'email'), verification_type: p.verification_type || '', verification_id: p.verification_id || '' });
    }
    return out.length ? { statusCode: 200, body: out } : fail(404, 'user_not_found');
  },

  // Serverless API (admin portal 2FA)
  'POST /admin/login-2fa-send-otp': async ({ body }) => {
    if (!body.destination) return fail(400, 'invalid_request');
    await issueOtp('sms', body.destination, 'admin-2fa');
    return ok('otp_generated_and_enqueued_successfully');
  },
  'POST /admin/login-2fa-verify-otp': async ({ body }) => {
    const err = checkOtp('sms', body.destination, String(body.otp));
    return err ? fail(400, err) : ok('sms_otp_verified_successfully');
  },

  // dev helpers
  'GET /__dev/outbox': async () => ({ statusCode: 200, body: state.outbox }),
  'GET /__dev/health': async () => ({ statusCode: 200, body: { status: 'ok', floci: FLOCI } }),
};

async function handle(req) {
  const p = req.path.replace(/\/+$/, '');
  const key = Object.keys(routes).find(k => { const [m, suffix] = k.split(' '); return m === req.method && p.endsWith(suffix); });
  if (!key) return fail(404, 'route_not_found');
  try { return await routes[key]({ ...req, headers: req.headers || {}, query: req.query || {}, body: req.body || {} }); }
  catch (e) { console.error('[mock-identity]', key, e); return fail(500, 'internal_server_error'); }
}

module.exports = { handle };
