# Can a Horizon task be migrated to run under plain Harbor?

**Question:** a real task built for Bespoke Labs' hosted **Horizon** platform
(`~/Work/horizon/tasks/arun-mukkath/device-listing-remote-sign-out`) — targeting the legacy
Ventuno PHP platform image (`ventuno-world:0.2.0`, the same image referenced throughout this
POC's "Ventuno World" precedent) — is labeled `"format": "harbor"` in its `.horizon/metadata.json`.
Does that mean it can run directly under open-source Harbor?

**Answer: not directly, but with a small, mechanical `task.toml` rewrite, yes** — verified by
actually running it, not just comparing schemas on paper. See
`~/Work/ventuno-labs/horizon-test/` for the migrated copy and
[`harbor-commands.md`](harbor-commands.md) for command syntax.

## Why "not directly"

`horizon` turned out to be a **separate product**, not a nickname for Harbor: Bespoke Labs' hosted
platform (`horizon.bespokelabs.ai`), with its own CLI (`horizon`, distinct from `harbor`) and its
own `task.toml` schema. The `"format": "harbor"` tag is Horizon's own internal label (probably
"follows the Harbor-style directory layout convention"), not a literal compatibility guarantee.

Confirmed empirically: `harbor run` against the *original*, unmodified task directory does not
parse — its `task.toml` uses field names vanilla Harbor's `TaskConfig` model doesn't recognize.

## The field mapping that made it work

Only `task.toml` needed changes. Every other file (`instruction.md`, `environment/Dockerfile`,
`solution/solve.sh`, `tests/test.sh`, `tests/test_solution.py`) was copied over **byte-for-byte
unmodified** and worked as-is.

| Horizon's `task.toml` | Harbor's real `task.toml` (verified against harbor 0.22.0's `TaskConfig`) |
|---|---|
| *(no `schema_version`)* | add `schema_version = "1.4"` |
| `[task.grading] method = "tests"` | delete — no equivalent; Harbor always runs `tests/test.sh` |
| `[task.metadata] {difficulty, tags, ...}` | move up one level to `[metadata]` (not nested under `[task]`) |
| `[task.limits] timeout_sec = 2000` | becomes `[agent] timeout_sec` |
| `[task.limits] memory_mb`, `build_timeout_sec` | become `[environment] memory_mb`, `build_timeout_sec` |
| *(no `[environment]` section)* | add `os = "linux"`, `network_mode` |

**What needed zero changes**, and why — these already matched Harbor's real conventions:
- `environment/Dockerfile` alone, no compose file — a fully valid, simplest-case Harbor
  environment (no `main`-service-naming requirement, since that only applies when a
  `docker-compose.yaml` is present).
- `tests/test.sh` writes `/logs/verifier/reward.txt` — exactly the path Harbor reads.
- `solution/solve.sh` is a plain bash script — no Horizon-specific syntax anywhere in it.

## Verified results (2026-08-27)

Run from `channelforge-world`'s own Harbor install (0.22.0), pointed at the migrated task
elsewhere on disk — no special wiring needed:

```
harbor run -p ~/Work/ventuno-labs/horizon-test/device-listing-remote-sign-out -a nop    -e docker -y
  → Mean: 0.0   (correctly fails — endpoints don't exist yet)

harbor run -p ~/Work/ventuno-labs/horizon-test/device-listing-remote-sign-out -a oracle -e docker -y
  → Mean: 1.0   (correctly passes)
```

The oracle run's verifier output confirms all 6 real assertions in `test_solution.py` genuinely
ran and passed against a live PHP/MySQL/memcached stack — not a trivial or vacuous pass:
`test_session_listing`, `test_targeted_revocation`, `test_self_revocation`,
`test_listing_and_revoke_are_scoped_to_session_owner`,
`test_same_partner_other_app_session_is_listed_and_revocable`,
`test_revoke_rejects_missing_and_inactive_sessions`.

One platform note carried over unchanged: the Dockerfile pins `--platform=linux/amd64` because the
image genuinely only ships amd64 binaries (`docker image inspect` confirms `Architecture: amd64`)
— not a Horizon-specific requirement, so it stays regardless of what runs the task.

## What this implies for the POC

- **Task portability across formats is real, not theoretical** — a task built for a different
  platform, targeting a completely different codebase (legacy PHP, not ChannelForge) and a
  completely different image (`ventuno-world`, not `channelforge-world`), migrated with a
  mechanical field rename and ran correctly on the first try.
- This is independent evidence for the same mechanism task-01 already validated — two unrelated
  tasks, two unrelated codebases, same `nop`-fails/`oracle`-passes proof pattern, same Harbor
  install.
- Reinforces that `task.toml`'s real shape (not the version we originally guessed) is now
  well-understood enough to write correctly on the first attempt for a brand new task, not just
  fix reactively after an error — this migration's `task.toml` parsed and ran clean on the first
  `harbor run`, no trial and error.
