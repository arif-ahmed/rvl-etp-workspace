# feature-docs-site

Static HTML site generated from [`docs/handover/feature-docs`](../../docs/handover/feature-docs)
(English + বাংলা, light/dark). First look covers the cross-cutting section only.

## Layout

| Path | What it is |
|---|---|
| `assets/` | Hand-authored source: `site.css`, `site.js`, vendored `vendor/mermaid.min.js` and `vendor/fonts/` (Plus Jakarta Sans + Anek Bangla, self-hosted) |
| `dist/` | **Generated** output — fully self-contained, works offline via `file://` |

Never edit `dist/` by hand; it is wiped on every build.

## Build

```bash
python scripts/build_feature_site.py                      # cross-cutting only (current scope)
python scripts/build_feature_site.py --sections all       # full 103-feature site
```

Requires Python 3.10+ with `pip install markdown`. Fonts and mermaid are vendored
into `assets/vendor/` automatically on first run (needs network once; afterwards
the build is fully offline).

## Deploy (Vercel or any static host)

`dist/` is plain static HTML — no framework, no build on the host needed:

- **Vercel**: import the repo → Framework Preset **Other** → Root Directory
  `apps/feature-docs-site/dist` → deploy. (Optional: set Build Command to
  `pip install markdown && python scripts/build_feature_site.py` and Output
  Directory to `apps/feature-docs-site/dist` to rebuild on push instead of
  committing `dist/`.)
- **Netlify / Cloudflare Pages / GitHub Pages**: point the publish directory at
  `apps/feature-docs-site/dist`, or drag-and-drop the folder.
- **Offline**: open `dist/index.html` directly in a browser.

## Deploying updates

`dist/` is committed, so after editing docs or assets:

```bash
python scripts/build_feature_site.py
git add apps/feature-docs-site && git commit -m "Rebuild feature-docs site"
```
