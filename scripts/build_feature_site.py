#!/usr/bin/env python3
"""Build the static HTML site from docs/handover/feature-docs.

Default scope is the cross-cutting section only (first look). Widen later with:

    python scripts/build_feature_site.py --sections all
    python scripts/build_feature_site.py --sections 10-admin-portal,60-cross-cutting

Output is plain static HTML under site/ (works over file://, no server needed).
Hand-authored assets live in site/assets/ and are never touched here; the build
only writes HTML files and, if missing, downloads mermaid.min.js.
"""

import argparse
import hashlib
import html
import posixpath
import re
import sys
import urllib.request
from pathlib import Path

import markdown
from markdown.extensions.toc import slugify_unicode

ROOT = Path(__file__).resolve().parent.parent
DOCS_DEFAULT = ROOT / "docs" / "handover" / "feature-docs"
OUT_DEFAULT = ROOT / "site"
MERMAID_URL = "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"
MERMAID_CDN_TAG = '<script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>'

UI = {
    "en": {
        "features": "Features",
        "contents": "Contents",
        "prev": "Previous",
        "next": "Next",
        "na": "Not included in the site yet",
        "scope_note": "First look: only the cross-cutting section is included. "
                      "The remaining sections will be added by re-running the build with a wider scope.",
        "router_title": "Choose a language",
        "router_note": "Light / dark mode can be switched from the top bar on any page.",
    },
    "bn": {
        "features": "ফিচারসমূহ",
        "contents": "সূচিপত্র",
        "prev": "পূর্ববর্তী",
        "next": "পরবর্তী",
        "na": "এখনো সাইটে যোগ হয়নি",
        "scope_note": "প্রথম দৃশ্য: আপাতত শুধু ক্রস-কাটিং অংশটি রয়েছে। "
                      "বাকি অংশগুলো পরে বিল্ড আবার চালিয়ে যোগ হবে।",
        "router_title": "ভাষা বেছে নিন",
        "router_note": "যেকোনো পেজের উপরের বার থেকে লাইট / ডার্ক মোড বদলানো যায়।",
    },
}

SVG_MENU = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 6h16M4 12h16M4 18h16"/></svg>'
SVG_SUN = '<svg class="icon-sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4M2 12h2m16 0h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>'
SVG_MOON = '<svg class="icon-moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 12.8A9 9 0 1 1 11.2 3 7 7 0 0 0 21 12.8z"/></svg>'

THEME_BOOT = """<script>
(function(){try{var t=localStorage.getItem('fd-theme');
if(!t)t=window.matchMedia&&matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light';
document.documentElement.setAttribute('data-theme',t);}catch(e){}})();
</script>"""


# --------------------------------------------------------------------------
# parsing helpers
# --------------------------------------------------------------------------

def parse_section_readme(text):
    """Return (number, short_title, full_title, description, [features]) from a section README."""
    m = re.match(r"#\s+(\d+)\s+·\s+(.+)\s*$", text, re.M)
    if not m:
        raise ValueError("section README has no '# <num> · <title>' H1")
    num, full_title = m.group(1), m.group(2).strip()
    short_title = re.sub(r"\s*\(.*$", "", full_title).strip()

    desc = ""
    for block in re.split(r"\n\s*\n", text):
        block = block.strip()
        if block.startswith(("#", "|", ">", "[")) or not block:
            continue
        desc = block.replace("\n", " ")
        break

    feats = []
    row = re.compile(r"^\|\s*([A-Z]+-\d+)\s*\|\s*\[([^\]]+)\]\(([^)]+?\.md)\)\s*\|\s*(.+?)\s*\|\s*$")
    for line in text.splitlines():
        rm = row.match(line)
        if rm:
            feats.append({"id": rm.group(1), "title": rm.group(2), "file": rm.group(3),
                          "purpose": rm.group(4)})
    return num, short_title, full_title, desc, feats


def strip_feature_h1(text):
    """Drop the H1 line (rendered as a custom page header instead). Return (fid, title, rest)."""
    m = re.match(r"#\s+([A-Z]+-\d+)\s+·\s+(.+?)\s*(?:\n|$)", text)
    if not m:
        raise ValueError("feature file has no '# <ID> · <title>' H1")
    return m.group(1), m.group(2), text[m.end():]


BN_LIST_NUM = re.compile(r"^(\s*)([০-৯]+)([.)])\s+")


def normalize_bn_list_numbers(text):
    """Bengali numerals ('১.') are not list markers for the markdown parser;
    convert them to Arabic outside fenced code (CSS renders them Bengali again)."""
    out, in_fence = [], False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            out.append(line)
            continue
        if not in_fence:
            line = BN_LIST_NUM.sub(lambda m: m.group(1) + str(int(m.group(2))) + m.group(3) + " ", line)
        out.append(line)
    return "\n".join(out)


def inline_md(text):
    """Render an inline-markdown string (table cell purpose) to HTML without <p>."""
    return markdown.markdown(text).removeprefix("<p>").removesuffix("</p>")


# --------------------------------------------------------------------------
# html post-processing
# --------------------------------------------------------------------------

MERMAID_BLOCK = re.compile(r'<pre><code class="language-mermaid">(.*?)</code></pre>', re.S)
UNCONFIRMED = re.compile(r"<code>(\[UNCONFIRMED:[^\]]*\])</code>")
HOP_TAG = re.compile(r"<strong>(\[[^\]]+\])</strong>")
ANCHOR = re.compile(r'<a href="([^"]*)">(.*?)</a>')


def md_rel_to_html(rel):
    if rel == "README.md":
        return "index.html"
    if rel.endswith("/README.md"):
        return rel[: -len("README.md")] + "index.html"
    return rel[: -len(".md")] + ".html" if rel.endswith(".md") else None


def rewrite_links(body, cur_dir, built_md, na_label):
    def repl(m):
        href, inner = m.group(1), m.group(2)
        if href.startswith(("http://", "https://", "mailto:", "#")) or not href:
            return m.group(0)
        path, _, anchor = href.partition("#")
        if not path.endswith(".md"):
            return m.group(0)
        rel = posixpath.normpath(posixpath.join(cur_dir, path))
        if rel in built_md:
            target_html = md_rel_to_html(rel)
            if target_html is None:
                return m.group(0)
            new_href = posixpath.relpath(target_html, cur_dir or ".")
            if anchor:
                new_href += "#" + anchor
            return f'<a href="{new_href}">{inner}</a>'
        return f'<span class="link-na" title="{html.escape(na_label)}">{inner}</span>'

    return ANCHOR.sub(repl, body)


def convert_feature(src, lang, cur_dir, built_md):
    text = normalize_bn_list_numbers(src)
    fid, title, rest = strip_feature_h1(text)

    md = markdown.Markdown(
        extensions=["tables", "fenced_code", "toc", "sane_lists"],
        extension_configs={"toc": {"toc_depth": "2-3", "slugify": slugify_unicode}},
    )
    body = md.convert(rest)

    body = MERMAID_BLOCK.sub(
        lambda m: '<div class="mermaid">' + html.unescape(m.group(1)) + "</div>", body)
    body = UNCONFIRMED.sub(
        lambda m: '<span class="badge-unconfirmed">' + m.group(1) + "</span>", body)
    body = HOP_TAG.sub(r'<strong class="hop-tag">\1</strong>', body)
    body = rewrite_links(body, cur_dir, built_md, UI[lang]["na"])
    return fid, title, body


# --------------------------------------------------------------------------
# page templates
# --------------------------------------------------------------------------

def asset_version(assets: Path, name: str) -> str:
    """Content hash for cache-busting query strings (?v=…) on asset links."""
    data = (assets / name).read_bytes()
    return hashlib.md5(data).hexdigest()[:8]


def page(lang, title, crumb, content, sidebar, to_root, mermaid_tag, lang_toggle=True):
    brand_href = f"{to_root}{lang}/index.html" if lang else f"{to_root}en/"
    lang_btn = ""
    if lang_toggle and lang:
        other = "বাংলা" if lang == "en" else "EN"
        lang_btn = (f'<button class="icon-btn" id="langToggle" title="Switch language / ভাষা বদলান" '
                    f'aria-label="Switch language">{other}</button>')
    return f"""<!doctype html>
<html lang="{lang or 'en'}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)} · GoBCB Feature Docs</title>
{THEME_BOOT}
<link rel="stylesheet" href="{to_root}assets/site.css?v={css_v}">
</head>
<body>
<header class="topbar">
  <button class="icon-btn" id="menuToggle" aria-label="Menu">{SVG_MENU}</button>
  <a class="brand" href="{brand_href}"><span class="brand-mark"></span>GoBCB&nbsp;<small>· Feature Docs</small></a>
  <span class="topbar-spacer"></span>
  {lang_btn}
  <button class="icon-btn" id="themeToggle" title="Light / dark" aria-label="Toggle theme">{SVG_SUN}{SVG_MOON}</button>
</header>
<div class="layout">
  <aside class="sidebar" id="sidebar">
{sidebar}
  </aside>
  <main class="content">
{crumb}
{content}
  </main>
</div>
{mermaid_tag}
<script src="{to_root}assets/site.js?v={js_v}"></script>
</body>
</html>
"""


def sidebar_html(sections, ui, in_section, active=None):
    """sections: [(num, short_title, full_title, desc, feats, dir_name)] for one language.

    in_section=True  -> page lives inside the section dir (links relative to it)
    in_section=False -> page is the language root index (links prefixed with <dir>/)
    active: 'sec:<dir>' marks the section link, '<dir>/<file>.html' a feature link.
    """
    parts = []
    for num, short, _full, _desc, feats, dirname in sections:
        prefix = "" if in_section else dirname + "/"
        is_on = " is-active" if active == f"sec:{dirname}" else ""
        parts.append(f'    <a class="side-section{is_on}" '
                     f'href="{prefix}index.html">{num} · {html.escape(short)}</a>')
        parts.append(f'    <div class="side-group">{html.escape(ui["features"])}</div>')
        for f in feats:
            fname = f["file"][:-3]
            is_on = " is-active" if active == f"{dirname}/{fname}.html" else ""
            parts.append(
                f'    <a class="side-item{is_on}" href="{prefix}{fname}.html">'
                f'<span class="id-chip">{f["id"]}</span><span>{html.escape(f["title"])}</span></a>')
    return "\n".join(parts)


def crumb_html(items):
    """items: [(label, href_or_None), ...]"""
    spans = []
    for label, href in items:
        if spans:
            spans.append('<span class="sep">›</span>')
        label = html.escape(label)
        spans.append(f"<a href=\"{href}\">{label}</a>" if href else f"<span>{label}</span>")
    return '<div class="crumb">' + "".join(spans) + "</div>"


# --------------------------------------------------------------------------
# build
# --------------------------------------------------------------------------

def ensure_mermaid(assets: Path) -> str:
    """Prefer the vendored mermaid; download once if absent, fall back to CDN."""
    vendor = assets / "mermaid.min.js"
    if not vendor.exists() or vendor.stat().st_size < 100_000:
        try:
            print("downloading mermaid.min.js …")
            with urllib.request.urlopen(MERMAID_URL, timeout=60) as r:
                vendor.write_bytes(r.read())
        except Exception as e:  # noqa: BLE001 - offline fallback
            print(f"  download failed ({e}); falling back to CDN tag", file=sys.stderr)
            return MERMAID_CDN_TAG
    return '<script src="{to_root}assets/mermaid.min.js"></script>'


def discover_sections(docs: Path, wanted):
    dirs = sorted(d.name for d in (docs / "en").iterdir()
                  if d.is_dir() and re.match(r"\d\d-", d.name))
    if wanted == "all":
        return dirs
    sections = [s.strip() for s in wanted.split(",") if s.strip()]
    missing = [s for s in sections if s not in dirs]
    if missing:
        sys.exit(f"unknown section(s) {missing}; available: {dirs}")
    return sections


def build(docs: Path, out: Path, wanted):
    global css_v, js_v
    assets = out / "assets"
    assets.mkdir(parents=True, exist_ok=True)
    mermaid_tag_tpl = ensure_mermaid(assets)
    css_v = asset_version(assets, "site.css")
    js_v = asset_version(assets, "site.js")

    section_dirs = discover_sections(docs, wanted)

    # pass 1: parse every section README (per language trees are mirrored)
    parsed = {}
    for lang in ("en", "bn"):
        parsed[lang] = []
        for dirname in section_dirs:
            readme = docs / lang / dirname / "README.md"
            num, short, full, desc, feats = parse_section_readme(readme.read_text(encoding="utf-8"))
            missing = [f["file"] for f in feats if not (docs / lang / dirname / f["file"]).exists()]
            if missing:
                sys.exit(f"{lang}/{dirname}: README links to missing files {missing}")
            parsed[lang].append((num, short, full, desc, feats, dirname))

    built_md = {"README.md"}
    built_md.update(f"{d}/README.md" for d in section_dirs)
    for lang in ("en", "bn"):
        for _, _, _, _, feats, d in parsed[lang]:
            built_md.update(f"{d}/{f['file']}" for f in feats)

    counts = {}
    for lang in ("en", "bn"):
        ui = UI[lang]
        n_pages = 0

        # ---- language root index -------------------------------------
        cards = "\n".join(
            f'    <a class="card" href="{d}/index.html">'
            f'<span class="card-title"><span class="id-chip">{num}</span> {html.escape(short)}</span>'
            f'<span class="card-desc">{inline_md(desc)}</span></a>'
            for num, short, full, desc, feats, d in parsed[lang])
        content = (f'<h1>{html.escape(ui["contents"])}</h1>\n'
                   f'<p class="scope-note">{html.escape(ui["scope_note"])}</p>\n'
                   f'<div class="cards">\n{cards}\n    </div>')
        # sidebar links from the language root are prefixed with each section dir
        side = sidebar_html(parsed[lang], ui, in_section=False)
        (out / lang / "index.html").parent.mkdir(parents=True, exist_ok=True)
        (out / lang / "index.html").write_text(
            page(lang, ui["contents"], "", content, side, "../",
                 mermaid_tag_tpl.format(to_root="../"), lang_toggle=False),
            encoding="utf-8")
        n_pages += 1

        # ---- one section at a time ------------------------------------
        for num, short, full, desc, feats, dirname in parsed[lang]:
            sec_dir_out = out / lang / dirname
            sec_dir_out.mkdir(parents=True, exist_ok=True)
            to_root = "../../"

            # section index (cards grid built from the README table)
            cards = "\n".join(
                f'      <a class="card" href="{f["file"][:-3]}.html">'
                f'<span class="card-title"><span class="id-chip">{f["id"]}</span> {html.escape(f["title"])}</span>'
                f'<span class="card-desc">{inline_md(f["purpose"])}</span></a>'
                for f in feats)
            content = (f'<h1><span class="id-chip">{num}</span> {html.escape(full)}</h1>\n'
                       f'<p>{inline_md(desc)}</p>\n'
                       f'<div class="cards">\n{cards}\n    </div>')
            side = sidebar_html(parsed[lang], ui, in_section=True, active=f"sec:{dirname}")
            (sec_dir_out / "index.html").write_text(
                page(lang, f"{num} · {short}", crumb_html([(ui["contents"], "../index.html"), (f"{num} · {short}", None)]),
                     content, side, to_root, mermaid_tag_tpl.format(to_root=to_root)),
                encoding="utf-8")
            n_pages += 1

            # feature pages
            for i, f in enumerate(feats):
                src = (docs / lang / dirname / f["file"]).read_text(encoding="utf-8")
                fid, title, body = convert_feature(src, lang, dirname, built_md)
                if fid != f["id"]:
                    sys.exit(f"{lang}/{dirname}/{f['file']}: H1 says {fid}, README says {f['id']}")

                pager = ["<div class=\"pager\">"]
                if i > 0:
                    p = feats[i - 1]
                    pager.append(f'  <a href="{p["file"][:-3]}.html"><span class="pager-label">'
                                 f'{html.escape(ui["prev"])}</span><span>{p["id"]} · {html.escape(p["title"])}</span></a>')
                else:
                    pager.append('  <span class="empty"></span>')
                if i < len(feats) - 1:
                    nx = feats[i + 1]
                    pager.append(f'  <a class="pager-next" href="{nx["file"][:-3]}.html"><span class="pager-label">'
                                 f'{html.escape(ui["next"])}</span><span>{nx["id"]} · {html.escape(nx["title"])}</span></a>')
                else:
                    pager.append('  <span class="empty"></span>')
                pager.append("</div>")
                content = (f'<h1><span class="id-chip">{fid}</span> {html.escape(title)}</h1>\n{body}\n'
                           + "\n".join(pager))
                side = sidebar_html(parsed[lang], ui, in_section=True,
                                    active=f"{dirname}/{f['file'][:-3]}.html")
                (sec_dir_out / (f["file"][:-3] + ".html")).write_text(
                    page(lang, f"{fid} · {title}",
                         crumb_html([(ui["contents"], "../index.html"),
                                     (f"{num} · {short}", "index.html"),
                                     (fid, None)]),
                         content, side, to_root, mermaid_tag_tpl.format(to_root=to_root)),
                    encoding="utf-8")
                n_pages += 1
        counts[lang] = n_pages

    # ---- language router at the site root ------------------------------
    router = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>GoBCB Feature Docs</title>
{THEME_BOOT}
<link rel="stylesheet" href="assets/site.css?v={css_v}">
</head>
<body>
<header class="topbar">
  <span class="brand"><span class="brand-mark"></span>GoBCB&nbsp;<small>· Feature Docs</small></span>
  <span class="topbar-spacer"></span>
  <button class="icon-btn" id="themeToggle" title="Light / dark" aria-label="Toggle theme">{SVG_SUN}{SVG_MOON}</button>
</header>
<div class="router-wrap">
  <h1>{UI['en']['router_title']} · {UI['bn']['router_title']}</h1>
  <div class="router-cards">
    <a class="router-card" href="en/">English<small>Read the feature documentation in English</small></a>
    <a class="router-card" href="bn/">বাংলা<small>বাংলায় ফিচার ডকুমেন্টেশন পড়ুন</small></a>
  </div>
  <p class="router-note">{UI['en']['router_note']}<br/>{UI['bn']['router_note']}</p>
</div>
<script src="assets/site.js?v={js_v}"></script>
</body>
</html>
"""
    (out / "index.html").write_text(router, encoding="utf-8")

    print(f"built {sum(counts.values()) + 1} pages under {out}")
    for lang, n in counts.items():
        print(f"  {lang}: {n} pages ({len(section_dirs)} section(s): {', '.join(section_dirs)})")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sections", default="60-cross-cutting",
                    help="comma list of section dirs under docs/handover/feature-docs/<lang>/, or 'all'")
    ap.add_argument("--docs", type=Path, default=DOCS_DEFAULT, help="feature-docs source root")
    ap.add_argument("--out", type=Path, default=OUT_DEFAULT, help="site output root")
    args = ap.parse_args()
    build(args.docs, args.out, args.sections)


if __name__ == "__main__":
    main()
