# rvl-etp-workspace: agent guide

Orchestrator repo for the ETP (Event Ticketing Platform). Submodules are stable code; wiring and docs live here. See `README.md` for local setup.

## Architecture

- For how the platform is hosted on AWS, read `docs/architecture/gobcb-aws-architecture.md`. It is the text equivalent of `gobcb_architecture_diagram.png` (from bs23), with a high-level overview and per-area sections.
- Do **not** open `gobcb_architecture_diagram.png`. It is large and token-expensive, and the markdown carries the same information.
- Items marked `[UNCONFIRMED]` in that doc are open questions for bs23. Do not treat them as fact.
- If the PNG and the doc disagree, tell the user rather than silently changing either.
