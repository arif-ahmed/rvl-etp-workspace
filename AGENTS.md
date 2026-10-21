# rvl-etp-workspace: agent guide

Orchestrator repo for the ETP (Event Ticketing Platform). Submodules are stable code; wiring and docs live here. See `README.md` for local setup.

## Ground rules (strict)

- **Never modify anything inside a submodule** (`rvl-gobcb-backend`, `rvl-gobcb-admin-portal`, `rvl-gobcb-user-portal`, `rvl-gobcb-checker-app`, `rvl-gobcb-user-app`) — not even temporary or test edits, and never commit to a submodule from this workspace. Submodule changes (bug fixes, features) belong in the submodule's own repository via a proper PR.
- Local experiments and overrides must stay **outside** submodules: user-secrets, environment variables, or workspace-level files (`aspire/`, `floci/`, `docs/`, scripts).
- Before finishing any task, verify `git status --porcelain` inside every submodule is empty; if anything changed, revert it (`git checkout -- <path>`) and rebuild so `bin`/`obj` match the original source.

## Architecture

- For how the platform is hosted on AWS, read `docs/architecture/gobcb-aws-architecture.md`. It is the text equivalent of `gobcb_architecture_diagram.png` (from bs23), with a high-level overview and per-area sections.
- Do **not** open `gobcb_architecture_diagram.png`. It is large and token-expensive, and the markdown carries the same information.
- Items marked `[UNCONFIRMED]` in that doc are open questions for bs23. Do not treat them as fact.
- If the PNG and the doc disagree, tell the user rather than silently changing either.
