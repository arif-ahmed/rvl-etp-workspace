# rvl-etp-workspace

Orchestrator repo for the ETP (Event Ticketing Platform) system. It pins the 5 stable
product repos as git submodules and holds the local-development glue (Aspire, Floci,
guides) that must never be committed into those repos.

> The submodules are **stable code**. All wiring, ports, emulation and docs live here in
> the orchestrator, so none of the 5 repos need to be modified for local development.

## Structure

| Path | Contents |
|---|---|
| `rvl-gobcb-backend/` | backend microservices (11 .NET services) — git submodule |
| `rvl-gobcb-admin-portal/` | Angular admin portal — git submodule |
| `rvl-gobcb-user-portal/` | Angular user portal — git submodule |
| `rvl-gobcb-user-app/` | user mobile app — git submodule |
| `rvl-gobcb-checker-app/` | ticket checker mobile app — git submodule |
| `aspire/` | run the whole backend locally with .NET Aspire: **[aspire/README.md](aspire/README.md)** |
| `floci/` | local AWS emulation (S3, SQS, SES, Cognito): **[floci/README.md](floci/README.md)** |
| `docs/` | guides (`local-development-guide.bn.md`) |

## Quick start

```powershell
git clone --recurse-submodules https://github.com/Relief-Validation/rvl-etp-workspace.git
# or, in an already cloned workspace:
git submodule update --init
```

Then:

1. Local AWS emulation: `cd floci && docker compose up -d && ./seed.ps1` (see [floci/README.md](floci/README.md))
2. Start the backend: `dotnet run --project aspire/Etp.AppHost` (see [aspire/README.md](aspire/README.md))

## Submodule workflow

Each submodule is **pinned to a commit**, not auto-synced to `main`. `branch = main` in
`.gitmodules` only matters when deliberately refreshing a pin.

- After cloning/fetching: `git submodule update --init` (restores the pinned commits)
- Check pins vs. remote `main`: `./status.ps1` (or `git submodule foreach 'git log -1 --oneline'`)
- **Deliberately** advance a pin (e.g. after an upstream fix):

  ```powershell
  git submodule update --remote rvl-gobcb-backend   # one repo only
  git commit -m "Bump rvl-gobcb-backend"            # commit the pin immediately
  ```

- Recommended once per clone: `git config submodule.recurse true` — makes
  `git pull` / `git checkout` move submodules along automatically.

Rules of thumb:

- Never commit inside a submodule directory from this workspace; work in the upstream
  repos (or their forks) and bump the pin here afterwards.
- A `git status` in this repo should normally be clean. A modified submodule line
  (`rvl-gobcb-*`) means a pin moved — commit it or discard it, never leave it hanging.
