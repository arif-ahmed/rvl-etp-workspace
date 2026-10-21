#!/usr/bin/env python3
"""Generate one Postman collection per ETP backend service from its controllers.

Reads (never writes) rvl-gobcb-backend/Services/*; writes postman/services/*.postman_collection.json
plus postman/etp-local-services.postman_environment.json. Re-run after backend changes.
One request per endpoint, folders per controller.  Run: python scripts/generate-postman.py
"""
import json, re, uuid, hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SERVICES = ROOT / "rvl-gobcb-backend" / "Services"
OUT = ROOT / "postman"
PORTS = {"Admin": 5101, "Booking": 5102, "Event": 5103, "Platform": 5104, "PushNotification": 5105,
         "Scheduler": 5106, "TicketChecker": 5107, "Ticketing": 5108, "UserAuth": 5109,
         "UserIssue": 5110, "Utility": 5111}
TOKENS = {"admin": "access_token_admin", "user": "access_token_user",
          "ticket-checker": "access_token_ticket_checker", "agent": "access_token_agent"}

LOGIN_PHONES = {"phone_admin": "+8801700000001", "phone_event_manager": "+8801700000002",
                "phone_ticket_manager": "+8801700000003", "phone_ticket_operator": "+8801700000004",
                "phone_customer_support": "+8801700000005", "phone_user": "+8801700000011",
                "phone_ticket_checker": "+8801700000021", "phone_agent": "+8801700000031"}

all_cs = [p for p in SERVICES.rglob("*.cs") if "obj" not in p.parts and "bin" not in p.parts]
_src = {}


def src(p):
    if p not in _src:
        _src[p] = p.read_text(encoding="utf-8-sig", errors="ignore")
    return _src[p]


# ---- model skeletons ------------------------------------------------------------------------
def default_for(t, depth, seen):
    t = t.strip().rstrip("?")
    if re.match(r"(List|IList|IEnumerable|ICollection|IReadOnlyList|HashSet)<", t) or t.endswith("[]"):
        inner = re.sub(r"^[A-Za-z]+<(.*)>$", r"\1", t) if "<" in t else t[:-2]
        return [default_for(inner, depth + 1, seen)] if depth < 2 else []
    if t in ("string", "String"):
        return "string"
    if t in ("int", "long", "short", "byte", "decimal", "double", "float", "uint", "ulong"):
        return 0
    if t == "bool":
        return False
    if t in ("DateTime", "DateTimeOffset"):
        return "2026-01-01T00:00:00Z"
    if t == "Guid":
        return "00000000-0000-0000-0000-000000000000"
    if t in ("object", "dynamic") or t.startswith("Dictionary"):
        return {}
    return skeleton(t, depth + 1, seen)


def skeleton(name, depth=0, seen=None):
    seen = seen or set()
    name = name.split(".")[-1]
    if depth > 2 or name in seen:
        return {}
    for p in all_cs:
        s = src(p)
        m = re.search(r"\b(?:class|record)\s+%s\b[^{;]*\{" % re.escape(name), s)
        if not m:
            continue
        d, i = 1, m.end()
        while i < len(s) and d:
            d += (s[i] == "{") - (s[i] == "}")
            i += 1
        body = s[m.end():i - 1]
        out = {}
        for pm in re.finditer(r"public\s+(?:required\s+)?([\w<>\[\],\.? ]+?)\s+(\w+)\s*\{\s*get;", body):
            out[pm.group(2)] = default_for(pm.group(1), depth, seen | {name})
        return out
    if any(re.search(r"\benum\s+%s\b" % re.escape(name), src(p)) for p in all_cs):
        return 0
    return {}


# ---- controller parsing ---------------------------------------------------------------------
def auth_of(attrs):
    """Token key, None (anonymous) or 'inherit'."""
    if "AllowAnonymous" in attrs:
        return None
    if not re.search(r"\[Authorize\b", attrs):
        return "inherit"
    m = re.search(r"\[Authorize\(([^\]]*)\]", attrs, re.S)
    a = m.group(1) if m else ""
    for k, v in (("ticket-checker", "TicketChecker"), ("agent", "Agent"), ("user", "User"), ("admin", "Admin")):
        if re.search(r"Policy\s*=\s*AuthScheme\.%s" % v, a):
            return k
    return "admin"  # Roles = ... / bare [Authorize] / multi-scheme: staff roles live in the admin pool


def split_params(s):
    out, d, cur = [], 0, ""
    for c in s:
        if c in "<([":
            d += 1
        elif c in ">)]":
            d -= 1
        if c == "," and d == 0:
            out.append(cur)
            cur = ""
        else:
            cur += c
    if cur.strip():
        out.append(cur)
    return [x.strip() for x in out]


PAT = re.compile(r"((?:[ \t]*\[[^\n]*\]\s*\n|[ \t]*///[^\n]*\n)*)[ \t]*public\s+(?:async\s+)?[\w<>\[\],\.? ]+?\s+(\w+)\s*\(([^)]*)\)", re.S)


def parse_controller(path):
    s = src(path)
    cm = re.search(r"((?:\s*\[[^\]]*\]\s*)*)\s*public\s+(?:abstract\s+)?class\s+(\w+)", s)
    if not cm:
        return None
    ctrl = re.sub(r"Controller$", "", cm.group(2))
    cattrs = cm.group(1)
    rm = re.search(r'\[Route\("([^"]*)"\)\]', cattrs)
    base = (rm.group(1) if rm else "").replace("[controller]", ctrl)
    cauth = auth_of(cattrs)
    cauth = None if cauth == "inherit" else cauth
    eps = []
    for m in PAT.finditer(s[cm.end():]):
        attrs, mname, params = m.group(1), m.group(2), m.group(3)
        hm = re.search(r'\[Http(Get|Post|Put|Delete|Patch)(?:\(\s*(?:"([^"]*)")?[^)]*\))?\]', attrs)
        if not hm:
            continue
        sub = hm.group(2) or ""
        r2 = re.search(r'\[Route\("([^"]*)"\)\]', attrs)
        if r2 and not sub:
            sub = r2.group(1)
        summ = re.search(r"<summary>\s*(.*?)\s*</summary>", re.sub(r"\s*///\s*", " ", attrs), re.S)
        a = auth_of(attrs)
        eps.append(dict(method=hm.group(1).upper(), sub=sub, name=mname, params=split_params(params),
                        auth=cauth if a == "inherit" else a, doc=summ.group(1).strip() if summ else ""))
    return ctrl, base, eps


def build_request(ctrl, base, ep):
    path = "/".join(x.strip("/") for x in (base, ep["sub"]) if x.strip("/"))
    path = re.sub(r"\{(\w+)(?::[^}]*)?\??\}", r"{\1}", path)
    placeholders = set(re.findall(r"\{(\w+)\}", path))
    query, body, form = [], None, []
    for p in ep["params"]:
        default = re.search(r"=\s*(.+)$", p)
        pn = re.sub(r"\s*=.*$", "", p).strip()
        mm = re.match(r"((?:\[[^\]]*\]\s*)*)([\w<>\[\],\.?]+)\s+(\w+)$", pn)
        if not mm:
            continue
        pattrs, ptype, pname = mm.groups()
        if "CancellationToken" in ptype or "FromHeader" in pattrs or "FromServices" in pattrs:
            continue
        if "IFormFile" in ptype or "FromForm" in pattrs:
            form.append(pname)
        elif "FromBody" in pattrs:
            inner = re.sub(r"^[A-Za-z]+<(.*)>$", r"\1", ptype) if "<" in ptype else ptype.rstrip("?")
            body = skeleton(inner)
            if "<" in ptype:
                body = [body]
        elif pname in placeholders:
            continue
        elif (ep["method"] in ("POST", "PUT", "PATCH") and re.match(r"[A-Z]\w+$", ptype)
              and ptype not in ("DateTime", "Guid") and not default and body is None):
            body = skeleton(ptype)  # implicit [FromBody] on [ApiController]
        else:
            query.append((pname, default.group(1).strip('" ') if default else ""))
    pvars = [{"key": k, "value": "1"} for k in re.findall(r"\{(\w+)\}", path)]
    pm_path = re.sub(r"\{(\w+)\}", r":\1", path)
    qs = "&".join(f"{k}={v}" for k, v in query)
    url = {"raw": "{{base_url}}/" + pm_path + ("?" + qs if qs else ""),
           "host": ["{{base_url}}"], "path": pm_path.split("/"),
           "query": [{"key": k, "value": v, "disabled": not v} for k, v in query],
           "variable": pvars}
    req = {"method": ep["method"], "header": [], "url": url, "description": ep["doc"]}
    if ep["auth"]:
        req["auth"] = {"type": "bearer", "bearer": [{"key": "token", "value": "{{%s}}" % TOKENS[ep["auth"]], "type": "string"}]}
        req["description"] = (req["description"] + "\n\n" if req["description"] else "") + f"Auth: `{ep['auth']}` token"
    else:
        req["auth"] = {"type": "noauth"}
    if form:
        req["body"] = {"mode": "formdata", "formdata": [{"key": f, "type": "file", "src": []} for f in form]}
    elif body is not None:
        req["header"].append({"key": "Content-Type", "value": "application/json"})
        req["body"] = {"mode": "raw", "raw": json.dumps(body, indent=2), "options": {"raw": {"language": "json"}}}
    return {"name": f"{ep['method']} /{path}", "request": req}


def uid(*a):
    return str(uuid.UUID(hashlib.md5("|".join(a).encode()).hexdigest()))


def main():
    (OUT / "services").mkdir(parents=True, exist_ok=True)
    summary = []
    for svc, port in PORTS.items():
        files = sorted(p for p in (SERVICES / svc).rglob("*Controller.cs") if "obj" not in p.parts and "bin" not in p.parts)
        folders = []
        for f in files:
            r = parse_controller(f)
            if not r or not r[2]:
                continue
            ctrl, base, eps = r
            seen, items = {}, []
            for ep in eps:
                it = build_request(ctrl, base, ep)
                seen[it["name"]] = seen.get(it["name"], 0) + 1
                if seen[it["name"]] > 1:
                    it["name"] += f" ({ep['name']})"
                items.append(it)
            folders.append({"name": ctrl, "item": items})
        if not folders:
            summary.append((svc, 0, 0))
            continue
        col = {"info": {"_postman_id": uid(svc), "name": f"ETP - {svc} Service",
                        "description": f"Endpoints of the {svc} service (port {port} locally), one request per endpoint grouped by controller. "
                                       "Generated by scripts/generate-postman.py. Get tokens via the ETP Cognito & Auth collection.",
                        "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
               "variable": [{"key": "base_url", "value": "{{%s_base_url}}" % svc.lower(), "type": "string"}],
               "item": folders}
        (OUT / "services" / f"etp-{svc.lower()}.postman_collection.json").write_text(json.dumps(col, indent=2), encoding="utf-8")
        summary.append((svc, len(folders), sum(len(f["item"]) for f in folders)))
    vals = [{"key": f"{s.lower()}_base_url", "value": f"http://localhost:{p}", "type": "default", "enabled": True} for s, p in PORTS.items()]
    for k in TOKENS.values():
        vals.append({"key": k, "value": "", "type": "secret", "enabled": True})
    # used by etp-login-all-pools (Floci Cognito); same keys/defaults as etp-local-floci env
    for k, v, t in [("floci_url", "http://localhost:4566", "default"), ("aws_region", "ap-southeast-1", "default"),
                    ("aws_access_key", "test", "default"), ("aws_secret_key", "test", "secret"),
                    ("test_password", "Passw0rd!23", "secret"), ("client_name", "etp-local", "default")]:
        vals.append({"key": k, "value": v, "type": t, "enabled": True})
    for pool in ("admin", "user", "ticketchecker", "agent"):
        vals.append({"key": f"{pool}_pool_id", "value": "", "type": "default", "enabled": True})
        vals.append({"key": f"{pool}_client_id", "value": "", "type": "default", "enabled": True})
    for k, v in LOGIN_PHONES.items():
        vals.append({"key": k, "value": v, "type": "default", "enabled": True})
    env = {"id": uid("env"), "name": "ETP Local - Services", "_postman_variable_scope": "environment", "values": vals}
    (OUT / "etp-local-services.postman_environment.json").write_text(json.dumps(env, indent=2), encoding="utf-8")
    for s in summary:
        print("%-18s controllers=%d endpoints=%d" % s)


main()
exec(compile((ROOT / "scripts" / "generate-postman-login.py").read_text(encoding="utf-8"), "generate-postman-login.py", "exec"))
