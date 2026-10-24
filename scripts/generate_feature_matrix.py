#!/usr/bin/env python3
"""Generate the GoBCB feature-matrix workbook from docs/handover/feature-docs.

Reads (never writes) the markdown feature documentation and produces
docs/handover/feature-matrix/GoBCB-Feature-Matrix.xlsx:

  Cover & Legend | Summary | Feature Matrix | Open Queries | Traceability | Gap Log | Review

The markdown docs remain the source of truth; this workbook is a generated view
plus the BS-23 review tracker. Re-run after the docs change -- review entries
(status / comments / responses / gap rows) are read back from an existing
workbook and merged by feature or query id, so they survive regeneration.

Usage:
    python scripts/generate_feature_matrix.py [--lang en] [--out PATH] [--no-preserve]

Dependencies: Python 3.9+, openpyxl.
"""

import argparse
import datetime
import json
import re
import sys
from pathlib import Path

from openpyxl import Workbook, load_workbook
from openpyxl.formatting.rule import CellIsRule, FormulaRule
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.datavalidation import DataValidation

# ---------------------------------------------------------------------------
# Design tokens (xlsx design system, "professional" palette; English-only
# workbook, so the cross-platform CJK font chain is not needed).
# ---------------------------------------------------------------------------
PRIMARY = "1B2A4A"
PRIMARY_LIGHT = "D6E4F0"
SECONDARY = PRIMARY_LIGHT
ACCENT_POSITIVE = "1B7D46"
ACCENT_NEGATIVE = "C0392B"
ACCENT_WARNING = "D4820A"
NEUTRAL_900 = "37352F"
NEUTRAL_600 = "8C8A84"
NEUTRAL_200 = "E9E9E8"
NEUTRAL_100 = "F7F7F5"
NEUTRAL_0 = "FFFFFF"
CF_POS_FILL = "E8F5E9"
CF_NEG_FILL = "FDEDEC"
CF_WARN_FILL = "FEF9E7"
FONT_NAME = "Calibri"

WORKSPACE = Path(__file__).resolve().parents[1]
DOCS_ROOT = WORKSPACE / "docs" / "handover" / "feature-docs"
DEFAULT_OUT = WORKSPACE / "docs" / "handover" / "feature-matrix" / "GoBCB-Feature-Matrix.xlsx"
DEFAULT_CROSSCHECK = WORKSPACE / "docs" / "handover" / "feature-matrix" / "closure-crosscheck.json"

FM_SHEET = "Feature Matrix"
OQ_SHEET = "Open Queries"
CC_SHEET = "Closure Cross-Check"

FM_STATUS = ["Not reviewed", "Confirmed", "Correction needed", "Missing detail", "Not a feature"]
OQ_STATUS = ["Open", "Answered - accepted", "Answered - disputed", "N/A"]
CC_STATUS = ["Open", "In progress", "Resolved", "N/A"]
CC_VERDICTS = ["Gap", "Discrepancy", "Question", "Obtain deliverable", "Future scope", "Confirmed"]
QUERY_KINDS = ["External", "Deployment", "Ambiguity", "Defect"]

AREAS = [
    ("10-admin-portal", "Admin Portal", "A"),
    ("20-user-portal", "User Web Portal", "P"),
    ("30-user-app", "User App", "U"),
    ("40-checker-app", "Checker App", "C"),
    ("50-system-initiated", "System-Initiated", "S"),
    ("60-cross-cutting", "Cross-Cutting", "X"),
]
AREA_BY_DIR = {d: n for d, n, _ in AREAS}

MODULE_TAGS = [
    "Programs & Events",
    "Venues & Seating",
    "Pricing & Promotions",
    "Bookings & Payments",
    "Ticketing",
    "Gate Operations & Checking",
    "Users & Accounts",
    "Auth & Security",
    "Notifications",
    "Reporting & Reconciliation",
    "Content & CMS",
    "Support & Issues",
    "Platform & Infrastructure",
]

# RVL-defined functional grouping (NOT part of the BS-23 docs) -- one tag per
# feature id, used only as a secondary "Module" axis for filtering.
MODULE_MAP = {
    # 10 Admin Portal
    "A-01": "Programs & Events", "A-02": "Programs & Events", "A-03": "Programs & Events",
    "A-04": "Programs & Events", "A-07": "Programs & Events", "A-08": "Programs & Events",
    "A-20": "Programs & Events",
    "A-05": "Venues & Seating", "A-06": "Venues & Seating", "A-10": "Venues & Seating",
    "A-09": "Pricing & Promotions", "A-15": "Pricing & Promotions", "A-16": "Pricing & Promotions",
    "A-11": "Ticketing", "A-12": "Ticketing", "A-13": "Ticketing",
    "A-17": "Gate Operations & Checking", "A-18": "Gate Operations & Checking",
    "A-19": "Gate Operations & Checking",
    "A-25": "Users & Accounts", "A-26": "Users & Accounts",
    "A-27": "Auth & Security",
    "A-21": "Reporting & Reconciliation", "A-22": "Reporting & Reconciliation",
    "A-23": "Reporting & Reconciliation",
    "A-14": "Content & CMS", "A-28": "Content & CMS", "A-29": "Content & CMS",
    "A-30": "Content & CMS", "A-31": "Content & CMS",
    "A-24": "Support & Issues",
    # 20 User portal
    "P-01": "Content & CMS", "P-02": "Programs & Events", "P-03": "Content & CMS",
    "P-04": "Bookings & Payments", "P-05": "Pricing & Promotions", "P-06": "Bookings & Payments",
    "P-07": "Bookings & Payments", "P-08": "Ticketing", "P-09": "Ticketing",
    "P-10": "Ticketing", "P-11": "Users & Accounts", "P-12": "Support & Issues",
    "P-13": "Content & CMS",
    # 30 User app
    "U-01": "Platform & Infrastructure", "U-02": "Programs & Events", "U-03": "Content & CMS",
    "U-04": "Bookings & Payments", "U-05": "Bookings & Payments", "U-06": "Bookings & Payments",
    "U-07": "Users & Accounts", "U-08": "Support & Issues", "U-09": "Notifications",
    "U-10": "Notifications",
    # 40 Checker app
    "C-01": "Gate Operations & Checking", "C-02": "Gate Operations & Checking",
    "C-03": "Gate Operations & Checking", "C-04": "Gate Operations & Checking",
    "C-05": "Gate Operations & Checking", "C-06": "Gate Operations & Checking",
    # 50 System-initiated
    "S-01": "Venues & Seating", "S-02": "Venues & Seating", "S-03": "Venues & Seating",
    "S-04": "Venues & Seating",
    "S-05": "Bookings & Payments", "S-06": "Bookings & Payments", "S-10": "Bookings & Payments",
    "S-07": "Ticketing", "S-08": "Ticketing", "S-09": "Ticketing",
    "S-11": "Notifications", "S-12": "Notifications", "S-13": "Notifications",
    "S-14": "Gate Operations & Checking", "S-15": "Gate Operations & Checking",
    "S-16": "Pricing & Promotions", "S-17": "Pricing & Promotions",
    # 60 Cross-cutting
    "X-01": "Auth & Security", "X-02": "Auth & Security", "X-03": "Auth & Security",
    "X-04": "Auth & Security", "X-07": "Auth & Security", "X-08": "Auth & Security",
    "X-09": "Auth & Security", "X-10": "Auth & Security", "X-12": "Auth & Security",
    "X-14": "Auth & Security", "X-15": "Auth & Security", "X-16": "Auth & Security",
    "X-17": "Auth & Security", "X-18": "Auth & Security", "X-24": "Auth & Security",
    "X-05": "Users & Accounts", "X-06": "Users & Accounts", "X-11": "Users & Accounts",
    "X-13": "Users & Accounts",
    "X-21": "Notifications", "X-22": "Notifications", "X-23": "Notifications",
    "X-19": "Platform & Infrastructure", "X-20": "Platform & Infrastructure",
    "X-25": "Platform & Infrastructure", "X-26": "Platform & Infrastructure",
}

FEATURE_ID_RE = re.compile(r"\b([AUPCSX]-\d{2})\b")
QUERY_ID_RE = re.compile(r"\b(Q-\d{2})\b")


class ParseError(RuntimeError):
    pass


# ---------------------------------------------------------------------------
# Small markdown helpers
# ---------------------------------------------------------------------------

def strip_md(text):
    """Markdown -> plain single-line text (links keep their label)."""
    if text is None:
        return ""
    s = str(text)
    s = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", s)  # links -> label
    s = s.replace("**", "").replace("__", "")
    s = s.replace("`", "")
    s = re.sub(r"\s+", " ", s)
    return s.strip()


def md_table_rows(text):
    """All rows of every markdown table in *text* as lists of stripped cells."""
    rows = []
    for line in text.splitlines():
        s = line.strip()
        if not (s.startswith("|") and s.endswith("|")):
            continue
        cells = [c.strip() for c in s[1:-1].split("|")]
        if cells and all(re.fullmatch(r":?-{2,}:?", c or "-") for c in cells):
            continue  # separator row
        rows.append(cells)
    return rows


def section_body(text, number):
    """Body of '## <number>. <title>' up to the next '## ' heading."""
    m = re.search(rf"^## {number}\. .*$", text, re.M)
    if not m:
        raise ParseError(f"section {number} not found")
    rest = text[m.end():]
    nxt = re.search(r"^## ", rest, re.M)
    return rest[: nxt.start()] if nxt else rest


def truncate(s, n):
    return s if len(s) <= n else s[: n - 1].rstrip() + "…"


# ---------------------------------------------------------------------------
# Parsers
# ---------------------------------------------------------------------------

def parse_area_readme(area_dir):
    """{id: {name, purpose, file}} from the area README feature table + blurb."""
    readme = area_dir / "README.md"
    text = readme.read_text(encoding="utf-8")
    blurb = ""
    for line in text.splitlines():
        t = line.strip()
        if t and not t.startswith("#") and not t.startswith("[") and not t.startswith(">") and len(t) > 20:
            blurb = strip_md(t)
            break
    feats = {}
    for cells in md_table_rows(text):
        if len(cells) >= 3 and FEATURE_ID_RE.fullmatch(cells[0]):
            fid = cells[0]
            link = re.search(r"\]\(([^)]+)\)", cells[1])
            feats[fid] = {
                "name": strip_md(cells[1]),
                "purpose": strip_md(cells[2]),
                "file": link.group(1) if link else None,
            }
    if not feats:
        raise ParseError(f"no feature table found in {readme}")
    return feats, blurb


def parse_feature_doc(path, fid):
    text = path.read_text(encoding="utf-8")
    m = re.match(rf"# {re.escape(fid)} · (.+)$", text, re.M)
    if not m:
        raise ParseError(f"{path.name}: H1 does not match '{fid} · <title>'")
    title = m.group(1).strip()

    secs = {}
    for num, body in re.findall(r"^## (\d+)\. .*$([\s\S]*?)(?=^## |\Z)", text, re.M):
        secs[int(num)] = body
    missing = [n for n in range(1, 12) if n not in secs]
    if missing:
        raise ParseError(f"{path.name}: missing sections {missing}")

    # -- §2 trigger & actor, condensed for a mixed audience ------------------
    s2 = secs[2]
    actor = ""
    m = re.search(r"^\|\s*Actor\s*\|(.+)\|\s*$", s2, re.M)
    if m:
        actor = strip_md(m.group(1))
    else:
        prod = re.search(r"\*\*Producer:\*\*(.+)", s2)
        cons = re.search(r"\*\*Consumer:\*\*(.+)", s2)
        if prod and cons:
            actor = (f"Producer: {truncate(strip_md(prod.group(1)), 110)} "
                     f"· Consumer: {truncate(strip_md(cons.group(1)), 110)}")
        else:
            plain = strip_md(s2)
            sent = re.match(r"(.+?\.)(\s|$)", plain)
            actor = sent.group(1) if sent else plain
            if len(actor) < 40:
                second = re.match(r".+?\.\s*(.+?\.)", plain)
                if second:
                    actor = f"{actor} {second.group(1)}"
            actor = truncate(actor, 220)

    # -- §6 endpoint count ----------------------------------------------------
    endpoints = sum(
        1 for line in secs[6].splitlines()
        if re.match(r"^\|\s*(GET|POST|PUT|DELETE|PATCH)\s*\|", line.strip())
    )

    # -- §10 depends / affects (outside the mermaid block) --------------------
    s10 = re.sub(r"```[\s\S]*?```", "", secs[10])
    m = re.search(r"\*\*Depends on:\*\*(.*?)\*\*Affects:\*\*(.*?)(?:\n\n|\Z)", s10, re.S)
    if not m:
        raise ParseError(f"{path.name}: §10 Depends on / Affects line not found")
    dep_ids = sorted(set(FEATURE_ID_RE.findall(m.group(1))))
    aff_ids = sorted(set(FEATURE_ID_RE.findall(m.group(2))))
    depends = ", ".join(dep_ids) if dep_ids else truncate(strip_md(m.group(1)), 60) or "—"
    affects = ", ".join(aff_ids) if aff_ids else truncate(strip_md(m.group(2)), 60) or "—"

    # -- §11 local testability -------------------------------------------------
    m = re.search(r"Local testability:\s*(.+?)\*\*", secs[11])
    testability = (m.group(1) if m else secs[11].strip().splitlines()[0]).strip().rstrip(".")
    testability = truncate(strip_md(testability), 40)

    unconfirmed = sorted(set(re.findall(r"UNCONFIRMED: (Q-\d+)", text)))

    return {
        "title": title, "actor": actor, "endpoints": endpoints,
        "depends": depends, "affects": affects,
        "testability": testability, "unconfirmed": unconfirmed,
    }


def parse_traceability(path):
    """§2 feature->service, §3 feature->endpoint, §4 state maps."""
    text = path.read_text(encoding="utf-8")
    services, endpoints = {}, {}
    for cells in md_table_rows(section_body(text, 2)):
        if len(cells) >= 4:
            ids = FEATURE_ID_RE.findall(cells[0])
            if ids:
                services[ids[0]] = (strip_md(cells[2]), strip_md(cells[3]))
    for cells in md_table_rows(section_body(text, 3)):
        if len(cells) >= 3:
            ids = FEATURE_ID_RE.findall(cells[0])
            if ids:
                endpoints[ids[0]] = (strip_md(cells[1]), strip_md(cells[2]))

    def state_map(body, key_col, feat_cols):
        mapping = {}
        for cells in md_table_rows(body):
            if len(cells) < 2:
                continue
            key = strip_md(cells[key_col])
            ids = set()
            for c in feat_cols:
                if c < len(cells):
                    ids |= set(FEATURE_ID_RE.findall(cells[c]))
            for fid in ids:
                mapping.setdefault(fid, []).append(key)
        return mapping

    s4 = section_body(text, 4)

    def part(a, b=None):
        start = s4.find(f"### {a}")
        if start < 0:
            raise ParseError(f"traceability subsection {a} not found")
        end = s4.find(f"### {b}") if b else len(s4)
        return s4[start:end]

    queues = state_map(part("4.1", "4.2"), 0, [3])
    redis = state_map(part("4.2", "4.3"), 0, [3])
    local = state_map(part("4.3", "4.4"), 0, [0, 1, 2, 3])  # ids appear in mixed columns
    external = state_map(part("4.4"), 0, [1])
    return services, endpoints, queues, redis, local, external


def parse_open_queries(path):
    """[(id, kind, question, why, [cited feature ids])] + kind summary check."""
    text = path.read_text(encoding="utf-8")
    kind_by_section = {2: "External", 3: "Deployment", 4: "Ambiguity", 5: "Defect"}
    colname = {2: "Question", 3: "Question", 4: "Question", 5: "Finding"}
    queries = {}
    for num, kind in kind_by_section.items():
        try:
            body = section_body(text, num)
        except ParseError:
            continue
        for cells in md_table_rows(body):
            if not cells or not re.fullmatch(r"\*\*(Q-\d+)\*\*", cells[0]):
                continue
            qid = cells[0].strip("*")
            if len(cells) < 4:
                raise ParseError(f"open query {qid}: expected 4 columns, got {len(cells)}")
            queries[qid] = {
                "kind": kind,
                "question": strip_md(cells[1]),
                "why": strip_md(cells[2]),
                "cited": sorted(set(FEATURE_ID_RE.findall(cells[3]))),
            }
    # cross-check against the §1 summary table; section-table membership wins
    for cells in md_table_rows(section_body(text, 1)):
        if len(cells) >= 3 and cells[0] in QUERY_KINDS:
            expected = set(QUERY_ID_RE.findall(cells[2]))
            got = {q for q, v in queries.items() if v["kind"] == cells[0]}
            if expected != got:
                print(f"warning: 99-open-queries.md §1 says kind {cells[0]} = {sorted(expected)}, "
                      f"but the section tables give {sorted(got)} (section tables win); "
                      f"difference: {sorted(expected ^ got)}", file=sys.stderr)
    return queries


def parse_readme_extras(path):
    """Evidence baseline rows + 'The numbers' rows from the master README."""
    text = path.read_text(encoding="utf-8")
    baseline = []
    m = re.search(r"### Evidence baseline(.*?)^## ", text, re.M | re.S)
    if m:
        for cells in md_table_rows(m.group(1)):
            if len(cells) == 2 and "Repository" not in cells[0]:
                baseline.append((cells[0].strip("`"), cells[1].strip("`")))
    numbers = []
    m = re.search(r"## The numbers(.*?)^## ", text, re.M | re.S)
    if m:
        for cells in md_table_rows(m.group(1)):
            if len(cells) == 2 and cells[0]:
                numbers.append((strip_md(cells[0]), strip_md(cells[1])))
    return baseline, numbers


def collect(lang):
    """Parse the whole en/ (or bn/) tree -> (features, queries, extras)."""
    root = DOCS_ROOT / lang
    features = []
    for d, area, letter in AREAS:
        area_dir = root / d
        feats, blurb = parse_area_readme(area_dir)
        for fid in sorted(feats):
            info = feats[fid]
            if not info["file"]:
                raise ParseError(f"{fid}: no doc link in area README")
            doc_path = area_dir / info["file"]
            if not doc_path.exists():
                raise ParseError(f"missing feature doc: {doc_path}")
            parsed = parse_feature_doc(doc_path, fid)
            parsed.update({
                "id": fid, "area": area, "dir": d, "module": MODULE_MAP.get(fid, ""),
                "name": info["name"], "purpose": info["purpose"],
                "doc": f"feature-docs/{lang}/{d}/{info['file']}",
                "area_blurb": blurb,
            })
            features.append(parsed)
    return features


# ---------------------------------------------------------------------------
# Review-data preservation
# ---------------------------------------------------------------------------

def read_previous_review(path):
    """Pull user-entered review data out of an existing workbook."""
    prev = {"fm": {}, "oq": {}, "cc": {}, "gap": []}
    if not path.exists():
        return prev
    wb = load_workbook(path, data_only=False)
    if FM_SHEET in wb.sheetnames:
        ws = wb[FM_SHEET]
        for row in ws.iter_rows(min_row=5, min_col=2, max_col=18):
            fid = row[2].value  # column D
            if isinstance(fid, str) and FEATURE_ID_RE.fullmatch(fid.strip()):
                status, comment = row[15].value, row[16].value  # Q, R
                if status or comment:
                    prev["fm"][fid.strip()] = (status or "Not reviewed", comment or "")
    if OQ_SHEET in wb.sheetnames:
        ws = wb[OQ_SHEET]
        for row in ws.iter_rows(min_row=5, min_col=2, max_col=10):
            qid = row[0].value  # column B
            if isinstance(qid, str) and QUERY_ID_RE.fullmatch(qid.strip()):
                vals = [c.value for c in row[5:9]]  # G..J
                if any(v not in (None, "") for v in vals):
                    prev["oq"][qid.strip()] = vals
    if CC_SHEET in wb.sheetnames:
        ws = wb[CC_SHEET]
        for row in ws.iter_rows(min_row=5, min_col=2, max_col=11):
            ref = row[0].value  # column B
            if isinstance(ref, str) and ref.startswith("CC-"):
                status, notes = row[8].value, row[9].value  # J, K
                if status or notes:
                    prev["cc"][ref.strip()] = (status or "Open", notes or "")
    if "Gap Log" in wb.sheetnames:
        ws = wb["Gap Log"]
        for row in ws.iter_rows(min_row=5, min_col=2, max_col=8):
            if any(c.value not in (None, "") for c in row):
                prev["gap"].append([c.value for c in row])
    wb.close()
    return prev


# ---------------------------------------------------------------------------
# Styling helpers
# ---------------------------------------------------------------------------

def title_row(ws, title, subtitle, last_col):
    ws.sheet_view.showGridLines = False
    ws.column_dimensions["A"].width = 3
    ws.row_dimensions[1].height = 15
    ws.merge_cells(start_row=2, start_column=2, end_row=2, end_column=last_col)
    c = ws.cell(row=2, column=2, value=title)
    c.font = Font(name=FONT_NAME, size=16, bold=True, color=PRIMARY)
    c.alignment = Alignment(horizontal="left", vertical="center")
    ws.row_dimensions[2].height = 32
    if subtitle:
        ws.merge_cells(start_row=3, start_column=2, end_row=3, end_column=last_col)
        s = ws.cell(row=3, column=2, value=subtitle)
        s.font = Font(name=FONT_NAME, size=9, color=NEUTRAL_600)
        s.alignment = Alignment(horizontal="left", vertical="center")
        ws.row_dimensions[3].height = 14


def style_headers(ws, row, headers, start_col=2):
    for i, h in enumerate(headers, start_col):
        c = ws.cell(row=row, column=i, value=h)
        c.fill = PatternFill("solid", fgColor=PRIMARY)
        c.font = Font(name=FONT_NAME, size=11, bold=True, color="FFFFFF")
        c.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
        c.border = Border(bottom=Side(style="thin", color=NEUTRAL_200))
    ws.row_dimensions[row].height = 30


def set_widths(ws, widths, start_col=2):
    for i, w in enumerate(widths, start_col):
        ws.column_dimensions[get_column_letter(i)].width = w


def est_height(values, widths, min_h=22):
    """Row height estimate for wrapped text (Calibri 11)."""
    lines = 1
    for v, w in zip(values, widths):
        if v is None:
            continue
        s = str(v)
        need = sum(max(1, -(-len(seg) // max(1, int(w) - 1))) for seg in s.split("\n"))
        lines = max(lines, need)
    return min(max(min_h, lines * 14.5 + 7.5), 320)


# ---------------------------------------------------------------------------
# Sheet builders
# ---------------------------------------------------------------------------

def build_matrix(wb, features, queries, prev):
    ws = wb.create_sheet(FM_SHEET)
    ws.sheet_properties.tabColor = PRIMARY
    headers = ["Area", "Module", "ID", "Feature", "What it does", "Who starts it",
               "Service(s)", "Endpoints", "Primary endpoint", "Depends on", "Affects",
               "Open queries", "Defect risk", "Local testability", "Doc",
               "BS-23 status", "BS-23 comments / corrections"]
    widths = [16, 20, 8, 24, 46, 30, 18, 10, 30, 14, 14, 14, 10, 16, 34, 15, 32]
    title_row(ws, "Feature Matrix — all 103 features, grouped by area",
              "One row per feature doc (docs/handover/feature-docs). Columns A–O are generated from the docs; "
              "columns P–Q are the BS-23 review. Module is an RVL-defined functional tag.", 1 + len(headers))
    style_headers(ws, 4, headers)
    set_widths(ws, widths)

    area_fill = {a: (NEUTRAL_0, NEUTRAL_100) for _, a, _ in AREAS}
    body_font = Font(name=FONT_NAME, size=11, color=NEUTRAL_900)
    link_font = Font(name=FONT_NAME, size=11, color=PRIMARY, underline="single")
    top_border = Border(top=Side(style="medium", color=NEUTRAL_200))

    kind_of = {q: v["kind"] for q, v in queries.items()}
    row = 5
    last_area = None
    band = 0
    for f in features:
        defect_qs = [q for q in f["unconfirmed"] if kind_of.get(q) == "Defect"]
        defect = f"Yes ({len(defect_qs)})" if defect_qs else "—"
        status, comment = prev["fm"].get(f["id"], ("Not reviewed", ""))
        vals = [
            f["area"], f["module"], f["id"], f["name"], f["purpose"], f["actor"],
            f["service"], f["endpoints"] if f["endpoints"] else "—", f["endpoint"],
            f["depends"], f["affects"], ", ".join(f["unconfirmed"]) or "—",
            defect, f["testability"], f["doc"], status, comment,
        ]
        fill = PatternFill("solid", fgColor=area_fill[f["area"]][band % 2])
        wrap_cols = {3, 4, 5, 6, 8, 9, 10, 11, 14, 16}  # 0-based offsets of long-text columns
        for i, v in enumerate(vals):
            col = 2 + i
            c = ws.cell(row=row, column=col, value=v)
            c.fill = fill
            c.font = body_font
            c.alignment = Alignment(
                horizontal="right" if i == 7 else "left",
                vertical="top" if i in wrap_cols else "center",
                wrap_text=True,
            )
            if f["area"] != last_area:
                c.border = top_border
        idc = ws.cell(row=row, column=4)
        idc.font = link_font
        idc.alignment = Alignment(horizontal="center", vertical="center")
        idc.hyperlink = f"../{f['doc']}"
        ws.row_dimensions[row].height = est_height(vals, widths)
        if f["area"] != last_area:
            last_area = f["area"]
            band = 0
        else:
            band += 1
        row += 1

    last = row - 1
    ws.auto_filter.ref = f"B4:{get_column_letter(1 + len(headers))}{last}"
    ws.freeze_panes = "E5"

    dv = DataValidation(type="list", formula1=f'"{",".join(FM_STATUS)}"', allow_blank=True)
    ws.add_data_validation(dv)
    dv.add(f"Q5:Q{last}")

    cf = ws.conditional_formatting
    col_q = f"Q5:Q{last}"
    cf.add(col_q, CellIsRule(operator="equal", formula=['"Confirmed"'],
                             fill=PatternFill(bgColor=CF_POS_FILL), font=Font(color=ACCENT_POSITIVE)))
    cf.add(col_q, CellIsRule(operator="equal", formula=['"Correction needed"'],
                             fill=PatternFill(bgColor=CF_NEG_FILL), font=Font(color=ACCENT_NEGATIVE)))
    cf.add(col_q, CellIsRule(operator="equal", formula=['"Missing detail"'],
                             fill=PatternFill(bgColor=CF_WARN_FILL), font=Font(color=ACCENT_WARNING)))
    cf.add(f"N5:N{last}", FormulaRule(formula=[f'LEFT(N5,3)="Yes"'],
                                      fill=PatternFill(bgColor=CF_NEG_FILL), font=Font(color=ACCENT_NEGATIVE)))
    return 5, last


def build_queries(wb, queries, prev):
    ws = wb.create_sheet(OQ_SHEET)
    ws.sheet_properties.tabColor = ACCENT_WARNING
    headers = ["Q-ID", "Kind", "Question / finding", "Why it is open (evidence)",
               "Cited features", "BS-23 response", "Status", "Answered by", "Date"]
    widths = [8, 12, 46, 60, 20, 40, 20, 14, 12]
    title_row(ws, "Open Queries — 75 items for the BS-23 review",
              "From 99-open-queries.md. Every [UNCONFIRMED: Q-nn] marker in the docs points here. "
              "Kinds: External (BS23 answers), Deployment (BS23/infra), Ambiguity (BS23/business), Defect (RVL fixes).",
              1 + len(headers))
    style_headers(ws, 4, headers)
    set_widths(ws, widths)

    body_font = Font(name=FONT_NAME, size=11, color=NEUTRAL_900)
    row = 5
    for qid in sorted(queries):
        q = queries[qid]
        defaults = ["", "Open", "", ""]
        saved = prev["oq"].get(qid, defaults)
        vals = [qid, q["kind"], q["question"], q["why"], ", ".join(q["cited"]) or "—",
                saved[0] or "", saved[1] or "Open", saved[2] or "", saved[3] or ""]
        fill = PatternFill("solid", fgColor=NEUTRAL_0 if (row - 5) % 2 == 0 else NEUTRAL_100)
        for i, v in enumerate(vals):
            c = ws.cell(row=row, column=2 + i, value=v)
            c.fill = fill
            c.font = body_font
            c.alignment = Alignment(horizontal="center" if i in (0, 1, 8) else "left",
                                    vertical="top" if i in (2, 3, 5) else "center", wrap_text=True)
            if i == 8:
                c.number_format = "YYYY-MM-DD"
        ws.row_dimensions[row].height = est_height(vals, widths)
        row += 1

    last = row - 1
    ws.auto_filter.ref = f"B4:{get_column_letter(1 + len(headers))}{last}"
    ws.freeze_panes = "D5"
    dv = DataValidation(type="list", formula1=f'"{",".join(OQ_STATUS)}"', allow_blank=True)
    ws.add_data_validation(dv)
    dv.add(f"H5:H{last}")
    cf = ws.conditional_formatting
    cf.add(f"H5:H{last}", CellIsRule(operator="equal", formula=['"Answered - accepted"'],
                                     fill=PatternFill(bgColor=CF_POS_FILL), font=Font(color=ACCENT_POSITIVE)))
    cf.add(f"H5:H{last}", CellIsRule(operator="equal", formula=['"Answered - disputed"'],
                                     fill=PatternFill(bgColor=CF_NEG_FILL), font=Font(color=ACCENT_NEGATIVE)))
    cf.add(f"C5:C{last}", CellIsRule(operator="equal", formula=['"Defect"'],
                                     fill=PatternFill(bgColor=CF_WARN_FILL), font=Font(color=ACCENT_WARNING)))
    return 5, last


def build_crosscheck(wb, cc_rows, prev):
    ws = wb.create_sheet(CC_SHEET)
    ws.sheet_properties.tabColor = ACCENT_NEGATIVE
    headers = ["Ref", "Topic", "BS-23 report says", "Our documentation says",
               "Verdict", "Related IDs", "Action", "Owner", "Status", "Notes / BS-23 response"]
    widths = [8, 24, 48, 48, 16, 16, 44, 13, 12, 32]
    verdicts = [r["verdict"] for r in cc_rows]
    vsum = ", ".join(f"{v}: {verdicts.count(v)}" for v in CC_VERDICTS if v in verdicts)
    subtitle = (f"{len(cc_rows)} findings ({vsum}). Source: closure-crosscheck.json — edit that file "
                f"and regenerate; the Status and Notes columns entered here are preserved.")
    title_row(ws, "Closure Cross-Check — BS-23 closure report V1.2 vs our feature docs",
              subtitle, 1 + len(headers))
    style_headers(ws, 4, headers)
    set_widths(ws, widths)
    body_font = Font(name=FONT_NAME, size=11, color=NEUTRAL_900)
    row = 5
    for r in cc_rows:
        status, notes = prev["cc"].get(r["ref"], (r.get("status", "Open"), ""))
        vals = [r["ref"], r["topic"], r["pdf_says"], r["docs_say"], r["verdict"],
                r["related"], r["action"], r["owner"], status, notes]
        fill = PatternFill("solid", fgColor=NEUTRAL_0 if (row - 5) % 2 == 0 else NEUTRAL_100)
        for i, v in enumerate(vals):
            c = ws.cell(row=row, column=2 + i, value=v)
            c.fill = fill
            c.font = body_font
            c.alignment = Alignment(horizontal="center" if i in (0, 4, 8) else "left",
                                    vertical="top" if i in (1, 2, 3, 6, 9) else "center",
                                    wrap_text=True)
        ws.row_dimensions[row].height = est_height(vals, widths)
        row += 1
    last = row - 1
    ws.auto_filter.ref = f"B4:{get_column_letter(1 + len(headers))}{last}"
    ws.freeze_panes = "D5"
    dv = DataValidation(type="list", formula1=f'"{",".join(CC_STATUS)}"', allow_blank=True)
    ws.add_data_validation(dv)
    dv.add(f"J5:J{last}")
    cf = ws.conditional_formatting
    for verdict, fill, color in [
        ("Gap", CF_NEG_FILL, ACCENT_NEGATIVE),
        ("Discrepancy", CF_WARN_FILL, ACCENT_WARNING),
        ("Question", CF_WARN_FILL, ACCENT_WARNING),
        ("Obtain deliverable", CF_WARN_FILL, ACCENT_WARNING),
        ("Confirmed", CF_POS_FILL, ACCENT_POSITIVE),
    ]:
        cf.add(f"F5:F{last}", CellIsRule(operator="equal", formula=[f'"{verdict}"'],
                                         fill=PatternFill(bgColor=fill), font=Font(color=color)))
    cf.add(f"J5:J{last}", CellIsRule(operator="equal", formula=['"Resolved"'],
                                     fill=PatternFill(bgColor=CF_POS_FILL), font=Font(color=ACCENT_POSITIVE)))
    cf.add(f"J5:J{last}", CellIsRule(operator="equal", formula=['"In progress"'],
                                     fill=PatternFill(bgColor=CF_WARN_FILL), font=Font(color=ACCENT_WARNING)))
    return 5, last


def build_traceability(wb, features, trace):
    ws = wb.create_sheet("Traceability")
    ws.sheet_properties.tabColor = PRIMARY
    headers = ["ID", "Feature", "Area", "Service(s)", "Also touches / trigger",
               "Primary endpoint", "Auth", "Queues", "Redis keys", "Local state", "External systems"]
    widths = [8, 24, 15, 20, 32, 34, 10, 22, 22, 22, 22]
    title_row(ws, "Technical Traceability — feature → service, endpoint, state",
              "From 02-traceability-matrix.md (§2, §3, §4). For DEV/OPS: where each feature's behaviour lives.",
              1 + len(headers))
    style_headers(ws, 4, headers)
    set_widths(ws, widths)
    body_font = Font(name=FONT_NAME, size=11, color=NEUTRAL_900)
    top_border = Border(top=Side(style="medium", color=NEUTRAL_200))
    row = 5
    last_area = None
    for f in features:
        fid = f["id"]
        svc, extra = trace["services"].get(fid, ("—", "—"))
        ep, auth = trace["endpoints"].get(fid, ("—", "—"))
        vals = [fid, f["name"], f["area"], svc, extra, ep, auth,
                "; ".join(trace["queues"].get(fid, [])) or "—",
                "; ".join(trace["redis"].get(fid, [])) or "—",
                "; ".join(trace["local"].get(fid, [])) or "—",
                "; ".join(trace["external"].get(fid, [])) or "—"]
        fill = PatternFill("solid", fgColor=NEUTRAL_0 if (row - 5) % 2 == 0 else NEUTRAL_100)
        for i, v in enumerate(vals):
            c = ws.cell(row=row, column=2 + i, value=v)
            c.fill = fill
            c.font = body_font
            c.alignment = Alignment(vertical="top" if i in (4, 5, 7, 8, 9, 10) else "center",
                                    horizontal="left", wrap_text=True)
            if f["area"] != last_area:
                c.border = top_border
        ws.row_dimensions[row].height = est_height(vals, widths)
        last_area = f["area"]
        row += 1
    last = row - 1
    ws.auto_filter.ref = f"B4:{get_column_letter(1 + len(headers))}{last}"
    ws.freeze_panes = "D5"
    return last


def build_gap_log(wb, prev):
    ws = wb.create_sheet("Gap Log")
    ws.sheet_properties.tabColor = ACCENT_POSITIVE
    headers = ["Area", "Proposed missing feature / gap", "Why we think it is missing",
               "Where seen (screen, endpoint, doc)", "Raised by", "Date", "BS-23 response"]
    widths = [16, 34, 40, 30, 14, 12, 34]
    title_row(ws, "Gap Log — anything the documentation missed",
              "For the BS-23 review: record features or behaviours that exist in the product but not in the "
              "feature docs (or vice versa). Add rows as needed.", 1 + len(headers))
    style_headers(ws, 4, headers)
    set_widths(ws, widths)
    body_font = Font(name=FONT_NAME, size=11, color=NEUTRAL_900)
    rows = prev["gap"] + [[]] * max(0, 25 - len(prev["gap"]))
    for r, vals in enumerate(rows):
        row = 5 + r
        fill = PatternFill("solid", fgColor=NEUTRAL_0 if r % 2 == 0 else NEUTRAL_100)
        for i in range(len(headers)):
            c = ws.cell(row=row, column=2 + i, value=vals[i] if i < len(vals) else None)
            c.fill = fill
            c.font = body_font
            c.alignment = Alignment(vertical="top", wrap_text=True, horizontal="left")
            if i == 5:
                c.number_format = "YYYY-MM-DD"
        ws.row_dimensions[row].height = 22
    last = 4 + len(rows)
    dv = DataValidation(type="list",
                        formula1=f'"{"Admin Portal,User Web Portal,User App,Checker App,System-Initiated,Cross-Cutting,Other"}"',
                        allow_blank=True)
    ws.add_data_validation(dv)
    dv.add(f"B5:B{last}")
    return last


def build_cover(wb, baseline, numbers, generated_on):
    ws = wb.active
    ws.title = "Cover & Legend"
    ws.sheet_properties.tabColor = NEUTRAL_600
    ws.sheet_view.showGridLines = False
    ws.column_dimensions["A"].width = 3
    for col, w in zip("BCDEF", (30, 34, 34, 26, 26)):
        ws.column_dimensions[col].width = w
    ws.row_dimensions[1].height = 15

    r = 2
    ws.merge_cells(start_row=r, start_column=2, end_row=r, end_column=6)
    c = ws.cell(row=r, column=2, value="GoBCB (rvl-etp) — Feature Matrix & BS-23 Verification Tracker")
    c.font = Font(name=FONT_NAME, size=16, bold=True, color=PRIMARY)
    ws.row_dimensions[r].height = 32
    r += 1
    ws.merge_cells(start_row=r, start_column=2, end_row=r, end_column=6)
    c = ws.cell(row=r, column=2,
                value=f"Generated {generated_on} from docs/handover/feature-docs (English). "
                      f"The markdown docs remain the source of truth; regenerate with "
                      f"scripts/generate_feature_matrix.py — review entries are preserved.")
    c.font = Font(name=FONT_NAME, size=9, color=NEUTRAL_600)
    r += 2

    def block(title):
        nonlocal r
        c = ws.cell(row=r, column=2, value=title)
        c.font = Font(name=FONT_NAME, size=12, bold=True, color=PRIMARY)
        ws.row_dimensions[r].height = 24
        r += 1

    def table(rows, headers=("Item", "Detail")):
        nonlocal r
        style_headers(ws, r, list(headers) + [""] * (5 - len(headers)))
        r += 1
        for i, row_vals in enumerate(rows):
            fill = PatternFill("solid", fgColor=NEUTRAL_0 if i % 2 == 0 else NEUTRAL_100)
            for j, v in enumerate(row_vals):
                c = ws.cell(row=r, column=2 + j, value=v)
                c.fill = fill
                c.font = Font(name=FONT_NAME, size=11, color=NEUTRAL_900)
                c.alignment = Alignment(vertical="top", wrap_text=True, horizontal="left")
            for j in range(len(row_vals), 5):
                ws.cell(row=r, column=2 + j).fill = fill
            ws.row_dimensions[r].height = est_height(row_vals, [30, 34, 34, 26, 26][: len(row_vals)])
            r += 1
        r += 1

    block("Purpose")
    ws.merge_cells(start_row=r, start_column=2, end_row=r, end_column=6)
    c = ws.cell(row=r, column=2, value=(
        "One readable overview of every feature of the event & ticketing platform for PM, QA, DEV, OPS and "
        "Head of Engineering, and the working document for the BS-23 verification review: confirm each feature, "
        "correct what is wrong, answer the 75 open queries, and log anything the documentation missed."))
    c.font = Font(name=FONT_NAME, size=11, color=NEUTRAL_900)
    c.alignment = Alignment(vertical="top", wrap_text=True)
    ws.row_dimensions[r].height = 52
    r += 2

    block("How to use this workbook")
    table([
        ["PM / HoE", "Summary sheet, then Feature Matrix filtered by Module or Area."],
        ["QA", "Feature Matrix: 'What it does', 'Local testability', and defect-linked features (red 'Defect risk')."],
        ["DEV", "Traceability sheet (service, endpoint, state) and the 'Depends on / Affects' columns."],
        ["OPS", "System-Initiated area, 'Deployment' open queries, Traceability 'External systems' column."],
        ["BS-23 review session", "Feature Matrix status dropdown + comments → Open Queries responses → Gap Log."],
    ], headers=("Role", "Where to look"))

    block("Evidence baseline (line numbers in the docs are valid for these commits)")
    table([(repo, commit) for repo, commit in baseline], headers=("Repository", "Commit"))

    block("Numbers from the documentation")
    table([(k, v) for k, v in numbers], headers=("Metric", "Value"))

    block("Legend — Feature Matrix review status")
    table([
        ["Not reviewed", "Default. Not yet checked with BS-23."],
        ["Confirmed", "BS-23 confirms the documented feature is correct and complete."],
        ["Correction needed", "BS-23 says the description is wrong — note the correction in the comments column."],
        ["Missing detail", "Feature exists but a part of it is not documented."],
        ["Not a feature", "Should not be tracked as a product feature (explain in comments)."],
    ], headers=("Status", "Meaning"))

    block("Legend — other columns")
    table([
        ["Module", "RVL-defined functional tag for filtering (NOT part of the BS-23 docs)."],
        ["Defect risk", "Feature cites at least one open query of kind 'Defect' (code that appears wrong)."],
        ["Open queries", "Q-IDs this feature's doc cites as [UNCONFIRMED] — see the Open Queries sheet."],
        ["Local testability", "From each doc's developer test guide: Full / Partial / Not locally."],
        ["Query kinds", "External → BS23 answers · Deployment → BS23/infra · Ambiguity → BS23/business · Defect → RVL fixes."],
    ], headers=("Column", "Meaning"))


def build_summary(wb, features, queries, fm_last, oq_last):
    ws = wb.create_sheet("Summary", 1)
    ws.sheet_properties.tabColor = SECONDARY
    ws.sheet_view.showGridLines = False
    ws.column_dimensions["A"].width = 3
    ws.row_dimensions[1].height = 15
    widths = [26, 12, 14, 13, 13, 12, 15, 13, 13]
    for i, w in enumerate(widths, 2):
        ws.column_dimensions[get_column_letter(i)].width = w

    ws.merge_cells("B2:J2")
    c = ws["B2"]
    c.value = "Summary — numbers & BS-23 verification progress"
    c.font = Font(name=FONT_NAME, size=16, bold=True, color=PRIMARY)
    ws.row_dimensions[2].height = 32

    kind_of = {q: v["kind"] for q, v in queries.items()}
    by_area = {a: [f for f in features if f["area"] == a] for _, a, _ in AREAS}
    testability = {"Full": 0, "Partial": 0, "Not locally": 0, "Mixed / other": 0}
    for f in features:
        t = f["testability"]
        if t.startswith("Full"):
            testability["Full"] += 1
        elif t.startswith("Partial"):
            testability["Partial"] += 1
        elif t.startswith("Not locally"):
            testability["Not locally"] += 1
        else:
            testability["Mixed / other"] += 1

    r = 4
    hdr_font = Font(name=FONT_NAME, size=12, bold=True, color=PRIMARY)

    def section_title(text):
        nonlocal r
        c = ws.cell(row=r, column=2, value=text)
        c.font = hdr_font
        ws.row_dimensions[r].height = 22
        r += 1

    # -- Table 1: features by area & review progress -------------------------
    section_title("Features by area & review progress (live counts from the Feature Matrix)")
    headers = ["Area", "Features", "With open queries", "Defect-linked",
               "Not reviewed", "Confirmed", "Correction needed", "Missing detail", "Not a feature"]
    style_headers(ws, r, headers)
    hdr_row = r
    r += 1
    first_data = r
    for _, area, _ in AREAS:
        feats = by_area[area]
        with_q = sum(1 for f in feats if f["unconfirmed"])
        defect = sum(1 for f in feats if any(kind_of.get(q) == "Defect" for q in f["unconfirmed"]))
        ws.cell(row=r, column=2, value=area)
        ws.cell(row=r, column=3, value=len(feats))
        ws.cell(row=r, column=4, value=with_q)
        ws.cell(row=r, column=5, value=defect)
        for j, status in enumerate(FM_STATUS):
            ws.cell(row=r, column=6 + j,
                    value=f"=COUNTIFS('{FM_SHEET}'!$B$5:$B${fm_last},$B{r},'{FM_SHEET}'!$Q$5:$Q${fm_last},\"{status}\")")
        r += 1
    total_row = r
    ws.cell(row=total_row, column=2, value="Total")
    for col in range(3, 11):
        letter = get_column_letter(col)
        ws.cell(row=total_row, column=col, value=f"=SUM({letter}{first_data}:{letter}{total_row - 1})")
    for rr in range(first_data, total_row + 1):
        fill = PatternFill("solid", fgColor=SECONDARY if rr == total_row else (NEUTRAL_0 if (rr - first_data) % 2 == 0 else NEUTRAL_100))
        for col in range(2, 11):
            c = ws.cell(row=rr, column=col)
            c.fill = fill
            c.font = Font(name=FONT_NAME, size=11, bold=rr == total_row,
                          color=PRIMARY if rr == total_row else NEUTRAL_900)
            c.alignment = Alignment(horizontal="left" if col == 2 else "right", vertical="center")
            if rr == total_row:
                c.border = Border(top=Side(style="medium", color=NEUTRAL_200))
    r = total_row + 3

    # -- Table 2: open queries by kind & answer status ------------------------
    section_title("Open queries by kind & answer status (live counts from the Open Queries sheet)")
    style_headers(ws, r, ["Kind", "Count", "Who answers", "Open", "Answered - accepted", "Answered - disputed", "N/A"])
    r += 1
    q_first = r
    who = {"External": "BS23", "Deployment": "BS23 / infrastructure",
           "Ambiguity": "BS23 / the business", "Defect": "RVL (finding to fix)"}
    for kind in QUERY_KINDS:
        ids = [q for q, v in queries.items() if v["kind"] == kind]
        ws.cell(row=r, column=2, value=kind)
        ws.cell(row=r, column=3, value=len(ids))
        ws.cell(row=r, column=4, value=who[kind])
        for j, status in enumerate(OQ_STATUS):
            ws.cell(row=r, column=5 + j,
                    value=f"=COUNTIFS('{OQ_SHEET}'!$C$5:$C${oq_last},$B{r},'{OQ_SHEET}'!$H$5:$H${oq_last},\"{status}\")")
        r += 1
    q_total = r
    ws.cell(row=q_total, column=2, value="Total")
    ws.cell(row=q_total, column=3, value=f"=SUM(C{q_first}:C{q_total - 1})")
    for col in range(5, 9):
        letter = get_column_letter(col)
        ws.cell(row=q_total, column=col, value=f"=SUM({letter}{q_first}:{letter}{q_total - 1})")
    for rr in range(q_first, q_total + 1):
        fill = PatternFill("solid", fgColor=SECONDARY if rr == q_total else (NEUTRAL_0 if (rr - q_first) % 2 == 0 else NEUTRAL_100))
        for col in range(2, 9):
            c = ws.cell(row=rr, column=col)
            c.fill = fill
            c.font = Font(name=FONT_NAME, size=11, bold=rr == q_total,
                          color=PRIMARY if rr == q_total else NEUTRAL_900)
            c.alignment = Alignment(horizontal="left" if col in (2, 4) else "right", vertical="center")
            if rr == q_total:
                c.border = Border(top=Side(style="medium", color=NEUTRAL_200))
    r = q_total + 3

    # -- Table 3: local testability -------------------------------------------
    section_title("Local testability (from each doc's developer test guide)")
    style_headers(ws, r, ["Rating", "Features"])
    r += 1
    t_first = r
    for k, v in testability.items():
        ws.cell(row=r, column=2, value=k)
        ws.cell(row=r, column=3, value=v)
        r += 1
    for i, rr in enumerate(range(t_first, r)):
        fill = PatternFill("solid", fgColor=NEUTRAL_0 if i % 2 == 0 else NEUTRAL_100)
        for col in (2, 3):
            c = ws.cell(row=rr, column=col)
            c.fill = fill
            c.font = Font(name=FONT_NAME, size=11, color=NEUTRAL_900)
            c.alignment = Alignment(horizontal="left" if col == 2 else "right")
    return total_row, q_total


def build_review(wb, fm_last, oq_last, summary_area_total_row, summary_q_total_row):
    ws = wb.create_sheet("Review")
    ws.sheet_properties.tabColor = "FFC000"
    ws.sheet_view.showGridLines = False
    ws.column_dimensions["A"].width = 3
    for col, w in zip("BCDE", (44, 14, 14, 12)):
        ws.column_dimensions[col].width = w
    ws.row_dimensions[1].height = 15
    ws.merge_cells("B2:E2")
    c = ws["B2"]
    c.value = "Review — workbook integrity self-checks (live formulas)"
    c.font = Font(name=FONT_NAME, size=14, bold=True, color=PRIMARY)
    ws.row_dimensions[2].height = 28

    style_headers(ws, 4, ["Check", "Expected", "Actual", "Status"])
    checks = [
        ("Feature rows in Feature Matrix", 103, f"=COUNTA('{FM_SHEET}'!D5:D{fm_last})"),
        ("Open-query rows in Open Queries", 75, f"=COUNTA('{OQ_SHEET}'!B5:B{oq_last})"),
        ("Every feature has a BS-23 status", 103, f"=COUNTA('{FM_SHEET}'!Q5:Q{fm_last})"),
        ("Every query has a status", 75, f"=COUNTA('{OQ_SHEET}'!H5:H{oq_last})"),
        ("Summary area totals equal feature rows", 103, f"=Summary!C{summary_area_total_row}"),
        ("Summary query total equals query rows", 75, f"=Summary!C{summary_q_total_row}"),
    ]
    for i, (name, expected, actual) in enumerate(checks):
        row = 5 + i
        ws.cell(row=row, column=2, value=name)
        ws.cell(row=row, column=3, value=expected)
        ws.cell(row=row, column=4, value=actual)
        ws.cell(row=row, column=5, value=f'=IF(C{row}=D{row},"PASS","FAIL")')
        fill = PatternFill("solid", fgColor=NEUTRAL_0 if i % 2 == 0 else NEUTRAL_100)
        for col in range(2, 6):
            c = ws.cell(row=row, column=col)
            c.fill = fill
            c.font = Font(name=FONT_NAME, size=11, color=NEUTRAL_900)
            c.alignment = Alignment(horizontal="left" if col == 2 else "center", vertical="center")
    last = 4 + len(checks)
    cf = ws.conditional_formatting
    cf.add(f"E5:E{last}", CellIsRule(operator="equal", formula=['"PASS"'],
                                     fill=PatternFill(bgColor=CF_POS_FILL), font=Font(color=ACCENT_POSITIVE)))
    cf.add(f"E5:E{last}", CellIsRule(operator="equal", formula=['"FAIL"'],
                                     fill=PatternFill(bgColor=CF_NEG_FILL), font=Font(color=ACCENT_NEGATIVE)))
    return last


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--lang", default="en", help="language tree under feature-docs (default: en)")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--crosscheck", type=Path, default=DEFAULT_CROSSCHECK,
                    help="closure-report cross-check json (sheet is skipped if the file is missing)")
    ap.add_argument("--no-preserve", action="store_true",
                    help="do not merge review entries from an existing workbook")
    args = ap.parse_args()

    root = DOCS_ROOT / args.lang
    if not root.exists():
        sys.exit(f"error: {root} not found")

    features = collect(args.lang)
    expected_per_area = {a: n for (_, a, _), n in zip(AREAS, [31, 13, 10, 6, 17, 26])}
    got_per_area = {}
    for f in features:
        got_per_area[f["area"]] = got_per_area.get(f["area"], 0) + 1
    if got_per_area != expected_per_area:
        sys.exit(f"error: feature counts per area {got_per_area} != expected {expected_per_area}")
    if len(features) != 103:
        sys.exit(f"error: expected 103 features, got {len(features)}")
    ids = [f["id"] for f in features]
    if len(set(ids)) != 103:
        sys.exit("error: duplicate feature ids")
    if set(MODULE_MAP) != set(ids):
        sys.exit(f"error: MODULE_MAP mismatch: missing {set(ids) - set(MODULE_MAP)}, "
                 f"extra {set(MODULE_MAP) - set(ids)}")

    queries = parse_open_queries(DOCS_ROOT / args.lang / "99-open-queries.md")
    if len(queries) != 75:
        sys.exit(f"error: expected 75 open queries, got {len(queries)}")
    for f in features:
        unknown = [q for q in f["unconfirmed"] if q not in queries]
        if unknown:
            sys.exit(f"error: {f['id']} cites unknown queries {unknown}")

    trace = {}
    (trace["services"], trace["endpoints"], trace["queues"],
     trace["redis"], trace["local"], trace["external"]) = parse_traceability(
        DOCS_ROOT / args.lang / "02-traceability-matrix.md")
    missing_svc = [f["id"] for f in features if f["id"] not in trace["services"]]
    if missing_svc:
        sys.exit(f"error: traceability §2 missing services for {missing_svc[:5]}...")

    baseline, numbers = parse_readme_extras(DOCS_ROOT / args.lang / "README.md")

    # enrich features with traceability info
    for f in features:
        f["service"] = trace["services"][f["id"]][0]
        f["endpoint"] = trace["endpoints"].get(f["id"], ("—", ""))[0]

    prev = {"fm": {}, "oq": {}, "cc": {}, "gap": []} if args.no_preserve else read_previous_review(args.out)

    cc_rows = []
    if args.crosscheck.exists():
        cc_doc = json.loads(args.crosscheck.read_text(encoding="utf-8"))
        cc_rows = cc_doc.get("rows", [])
        refs = [r["ref"] for r in cc_rows]
        if len(set(refs)) != len(refs):
            sys.exit("error: duplicate refs in closure-crosscheck.json")
        bad = [r["ref"] for r in cc_rows
               if r.get("verdict") not in CC_VERDICTS or not all(k in r for k in
                   ("ref", "topic", "pdf_says", "docs_say", "related", "action", "owner"))]
        if bad:
            sys.exit(f"error: malformed cross-check rows (bad verdict or missing field): {bad}")

    wb = Workbook()
    build_cover(wb, baseline, numbers, datetime.date.today().isoformat())
    fm_first, fm_last = build_matrix(wb, features, queries, prev)
    oq_first, oq_last = build_queries(wb, queries, prev)
    cc_first = cc_last = None
    if cc_rows:
        cc_first, cc_last = build_crosscheck(wb, cc_rows, prev)
    trace_last = build_traceability(wb, features, trace)
    gap_last = build_gap_log(wb, prev)
    area_total_row, q_total_row = build_summary(wb, features, queries, fm_last, oq_last)
    review_last = build_review(wb, fm_last, oq_last, area_total_row, q_total_row)

    # sheet order: Cover, Summary, Feature Matrix, Open Queries, Closure Cross-Check, Traceability, Gap Log, Review
    order = ["Cover & Legend", "Summary", FM_SHEET, OQ_SHEET, CC_SHEET, "Traceability", "Gap Log", "Review"]
    wb._sheets = [wb[name] for name in order if name in wb.sheetnames]

    wb.properties.creator = "Z.ai"
    args.out.parent.mkdir(parents=True, exist_ok=True)
    wb.save(args.out)

    # machine-readable expectations for post-recalc verification
    kind_count = {k: sum(1 for v in queries.values() if v["kind"] == k) for k in QUERY_KINDS}
    testability = {"Full": 0, "Partial": 0, "Not locally": 0, "Mixed / other": 0}
    for f in features:
        t = f["testability"]
        if t.startswith("Full"):
            testability["Full"] += 1
        elif t.startswith("Partial"):
            testability["Partial"] += 1
        elif t.startswith("Not locally"):
            testability["Not locally"] += 1
        else:
            testability["Mixed / other"] += 1
    merged = {"fm": len(prev["fm"]), "oq": len(prev["oq"]), "cc": len(prev["cc"]), "gap": len(prev["gap"])}
    print(json.dumps({
        "wrote": str(args.out),
        "features": len(features),
        "areas": got_per_area,
        "queries": len(queries),
        "query_kinds": kind_count,
        "testability": testability,
        "features_with_queries": sum(1 for f in features if f["unconfirmed"]),
        "defect_features": sum(1 for f in features
                               if any(queries[q]["kind"] == "Defect" for q in f["unconfirmed"])),
        "crosscheck_rows": len(cc_rows),
        "preserved_review_entries": merged,
        "rows": {"fm": [fm_first, fm_last], "oq": [oq_first, oq_last],
                 "cc": [cc_first, cc_last],
                 "trace_last": trace_last, "gap_last": gap_last,
                 "summary_area_total_row": area_total_row, "summary_q_total_row": q_total_row},
    }, indent=2))


if __name__ == "__main__":
    main()
