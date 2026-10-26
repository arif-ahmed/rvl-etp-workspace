# Part of generate-postman.py (exec'd from it): builds postman/etp-login-all-pools.postman_collection.json
# Logs in every seeded user of all four Cognito pools (scripts/Seed-EtpCognitoUsers.ps1) and stores access_token_* in the environment.
POOLS = [  # (pool key, seeded pool name, [(env token suffix, phone var, expected custom:role)])
    ("admin", "etp-admin", [("admin", "phone_admin", "admin"), ("event_manager", "phone_event_manager", "event_manager"),
                            ("ticket_manager", "phone_ticket_manager", "ticket_manager"),
                            ("ticket_operator", "phone_ticket_operator", "ticket_operator"),
                            ("customer_support", "phone_customer_support", "customer_support")]),
    ("user", "etp-user", [("user", "phone_user", "user")]),
    ("ticketchecker", "etp-ticketchecker", [("ticket_checker", "phone_ticket_checker", "ticket-checker")]),
    ("agent", "etp-agent", [("agent", "phone_agent", "agent")]),
]
_JSON = [{"key": "Content-Type", "value": "application/x-amz-json-1.1"}]
_SIGN = {"type": "awsv4", "awsv4": [{"key": k, "value": v, "type": "string"} for k, v in (
    ("accessKey", "{{aws_access_key}}"), ("secretKey", "{{aws_secret_key}}"), ("region", "{{aws_region}}"), ("service", "cognito-idp"))]}


def _cognito(name, target, body, test, signed, desc=""):
    return {"name": name, "event": [{"listen": "test", "script": {"type": "text/javascript", "exec": test}}],
            "request": {"method": "POST", "header": _JSON + [{"key": "X-Amz-Target", "value": "AWSCognitoIdentityProviderService." + target}],
                        "url": "{{floci_url}}/", "description": desc, "auth": _SIGN if signed else {"type": "noauth"},
                        "body": {"mode": "raw", "raw": json.dumps(body, indent=2), "options": {"raw": {"language": "json"}}}}}


_setup = [_cognito("Resolve pool ids (ListUserPools)", "ListUserPools", {"MaxResults": 60}, [
    "pm.test('200', () => pm.response.to.have.status(200));",
    "const pools = pm.response.json().UserPools || [];",
] + [f"{{ const p = pools.find(x => x.Name === '{n}'); pm.test('pool {n} exists (run scripts/Seed-EtpCognitoUsers.ps1)', () => pm.expect(p).to.exist); if (p) pm.environment.set('{k}_pool_id', p.Id); }}" for k, n, _ in POOLS],
    True, "Run first. Resolves the four pool ids from the seeded pool names.")]
for k, n, _ in POOLS:
    _setup.append(_cognito(f"Resolve {k} client id", "ListUserPoolClients", {"UserPoolId": "{{%s_pool_id}}" % k, "MaxResults": 60}, [
        "pm.test('200', () => pm.response.to.have.status(200));",
        "const c = (pm.response.json().UserPoolClients || []).find(c => c.ClientName === pm.environment.get('client_name'));",
        "pm.test('app client exists', () => pm.expect(c).to.exist);",
        f"if (c) pm.environment.set('{k}_client_id', c.ClientId);"], True))

_JWT = "function jwt(t){const p=t.split('.')[1].replace(/-/g,'+').replace(/_/g,'/');return JSON.parse(CryptoJS.enc.Utf8.stringify(CryptoJS.enc.Base64.parse(p)));}"
_logins = []
for k, n, users in POOLS:
    folder = []
    for suffix, phone, role in users:
        folder.append(_cognito(f"Login as {suffix}", "InitiateAuth", {
            "AuthFlow": "USER_PASSWORD_AUTH", "ClientId": "{{%s_client_id}}" % k,
            "AuthParameters": {"USERNAME": "{{%s}}" % phone, "PASSWORD": "{{test_password}}"}}, [
            _JWT,
            "pm.test('200 InitiateAuth', () => pm.response.to.have.status(200));",
            "const r = pm.response.json().AuthenticationResult;",
            "pm.test('token issued (no challenge)', () => pm.expect(r).to.exist);",
            "if (!r) return;",
            f"pm.environment.set('access_token_{suffix}', r.AccessToken);",
            f"pm.environment.set('id_token_{suffix}', r.IdToken);",
            f"pm.environment.set('refresh_token_{suffix}', r.RefreshToken);",
            f"pm.test('id token custom:role = {role}', () => pm.expect(jwt(r.IdToken)['custom:role']).to.eql('{role}'));",
        ], False))
    _logins.append({"name": f"{k.capitalize()} pool", "item": folder})

_login_col = {"info": {"_postman_id": uid("login-all-pools"), "name": "ETP - Login (all pools)",
                       "description": "Logs in every seeded user across the Admin, User, TicketChecker and Agent Cognito pools and stores "
                                      "access_token_* / id_token_* / refresh_token_* in the environment 'ETP Local - Services'. "
                                      "Run folder '00 - Resolve' first, then the pool folders (or the whole collection). Prereq: scripts/Seed-EtpCognitoUsers.ps1.",
                       "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
              "item": [{"name": "00 - Resolve", "item": _setup}] + _logins}
(OUT / "etp-login-all-pools.postman_collection.json").write_text(json.dumps(_login_col, indent=2), encoding="utf-8")
print("login collection: %d requests" % (len(_setup) + sum(len(f["item"]) for f in _logins)))
