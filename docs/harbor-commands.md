# Harbor command reference

Command cheatsheet. For *what these commands actually do under the hood*, see
[`how-it-works.md`](how-it-works.md). For install/version notes, see
[`harbor-install.md`](harbor-install.md).

## Setup (once per machine)

```bash
cd channelforge-world
python3 -m venv .venv
source .venv/bin/activate      # do this every time you open a new terminal
pip install harbor
harbor --version                # confirm it's installed
```

`source .venv/bin/activate` points your shell at this repo's own isolated copy of Harbor, so it
doesn't collide with any other Harbor install on the machine. It only affects your current
terminal session — run it again in any new tab.

Before running anything task-related, always refresh the vendored source:

```bash
./scripts/vendor-source.sh
```

## Scaffolding a new task

```bash
harbor init --task <org>/<name> -o <output-dir>
```
Generates a fresh, *current* `task.toml` + template files. Useful for checking the real schema
before hand-writing a `task.toml` — don't copy an old one and assume it's still right (schema has
drifted between Harbor versions before, see `harbor-install.md`).

## Running a task

The core pattern:

```bash
harbor run -p <task-dir> -a <agent> [-m <model>] -e docker -y --jobs-dir <output-dir> [--env-file .env]
```

| Flag | Meaning |
|---|---|
| `-p` | Path to the task directory (e.g. `tasks/task-01-rights-window-bugfix`) |
| `-a` | Agent to use — see table below |
| `-m` | Model, in `provider/model` form (e.g. `openai/gpt-5.6-luna`) — not needed for `nop`/`oracle` |
| `-e docker` | Run locally via Docker (the only environment provider we've validated) |
| `-y` | Auto-confirm prompts |
| `--jobs-dir` | Where results get written (we use `/tmp/harbor-jobs-*` — outside the repo, gitignored by nature) |
| `--env-file` | A `.env` file to load (needed whenever the agent calls a real model — supplies the API key) |

### The three checks that matter for validating a task

```bash
# 1. No-op — agent does nothing. Must fail.
harbor run -p tasks/task-01-rights-window-bugfix -a nop -e docker -y --jobs-dir /tmp/harbor-jobs

# 2. Oracle — runs solution/solve.sh (the reference fix). Must pass.
harbor run -p tasks/task-01-rights-window-bugfix -a oracle -e docker -y --jobs-dir /tmp/harbor-jobs

# 3. Real agent — must also pass, on its own.
harbor run -p tasks/task-01-rights-window-bugfix -a terminus-2 -m openai/gpt-5.6-luna -e docker -y \
  --env-file .env --jobs-dir /tmp/harbor-jobs
```

### Agents we've used or looked at

| Agent | Needs | Notes |
|---|---|---|
| `nop` | nothing | built-in, does nothing — the negative control |
| `oracle` | nothing | built-in, runs `solution/solve.sh` — the reference-fix control |
| `terminus-2` | a model + its API key | Harbor's general-purpose reference agent — what we've validated the demo with |
| `codex` | `OPENAI_API_KEY` | runs OpenAI's real Codex CLI inside the container; defaults to high reasoning effort (more tokens/cost than a lighter setting) |
| `claude-code` | `ANTHROPIC_API_KEY` (different from `OPENAI_API_KEY`) | not yet run against this repo |

Agent choice itself is free — you're only ever paying for model token usage, same billing
regardless of which agent harness drives the model.

## Debugging a task interactively (no agent, no verifier)

```bash
harbor task start-env -p <task-dir> -i
```
Builds the environment and drops you into a shell inside it — useful when a run isn't behaving as
expected and you want to poke around by hand before re-running.

## Browsing results

```bash
harbor view <jobs-dir>
```
Starts a local web viewer over everything in that jobs directory — trajectories, transcripts,
rewards — instead of digging through the raw job folder by hand.

## Where results actually land

Each `harbor run` writes one folder per job under `--jobs-dir`, named by timestamp:

```
<jobs-dir>/<timestamp>/<task-id>__<random>/
├── agent/
│   ├── terminus_2.pane       ← plain-text transcript of everything the agent did
│   ├── trajectory.json         structured version of the same
│   └── recording.cast          terminal recording (asciinema format)
├── verifier/
│   ├── reward.json            the sub-scores
│   ├── reward.txt              bare 0/1
│   └── pytest.log               raw test output
└── artifacts/
```

`result.json` one level up summarizes the whole job (all trials, cost, token counts).

## Costs observed so far

`terminus-2` + `gpt-5.6-luna`, one trial of task-01: **$0.0034**, 47–52 seconds. Trivial for demo
or single-task iteration; scale this by however many trials × tasks × models before a full
evaluation run (see the "30-trial evaluation matrix" tracker item).
