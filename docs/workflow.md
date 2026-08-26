# Task-authoring workflow

This walks through building a new task, using `tasks/task-01-rights-window-bugfix` as the worked
example. Read [`AGENTS.md`](../AGENTS.md) first — the prime directives there (write boundary, no
auto-reload, determinism, pristine images, hidden Oracle/verifier) aren't optional style points,
they're what makes a task valid.

## 1. Pick a real defect or missing behavior

Prefer a real, narrow piece of ChannelForge logic with an existing, focused test file — that test
file becomes your verifier for free, and "does the real test suite pass" is a much stronger ground
truth than a bespoke check you write yourself. `services/rights.py::covers_window` +
`tests/test_rights_enforcement.py` is the model: one small function, one small test file, several
real call sites.

Grep the target repo for a candidate:

```
find ../channelforge/apps/api/tests -iname "*<topic>*"
```

## 2. Write the regression

Introduce a small, plausible bug — the kind a real PR review might miss, not an obviously broken
change. Validate it in isolation before wiring anything else:

```
cd vendor/apps/api          # after scripts/vendor-source.sh
patch --dry-run -p1 < ../../../tasks/<task-id>/setup/regression.patch
patch -p1 < ../../../tasks/<task-id>/setup/regression.patch
python3 -m pytest tests/<the_test_file>.py -q     # confirm it breaks exactly what you expect
patch -p1 -R < ../../../tasks/<task-id>/setup/regression.patch
diff <(cat app/<path>.py) <(git -C ../../../../channelforge show $(cat ../../../PINNED_COMMIT):apps/api/app/<path>.py)
# should be empty — the reversed patch must restore a byte-identical original
```

If the patch header's line-count numbers (`@@ -N,M +N,M @@`) don't match the actual hunk, `patch`
will apply with fuzz warnings instead of failing outright — don't ignore that warning, fix the
header so it's exact.

## 3. Lay out the task directory

There is no Harbor-recognized "run this before the agent's turn" hook — a task's environment is
fully defined by what its own Dockerfile (or docker-compose services) build. The regression gets
baked in at *build* time, not applied at *container start*:

```
tasks/<task-id>/
  instruction.md               # bug report or feature request — no file/function names, no hints
  task.toml                    # schema 1.4 (verify against a fresh `harbor init` scaffold, not
                                # against an older task.toml you find lying around)
  environment/
    Dockerfile                 # pristine vendored source + `RUN patch -p1 < .../regression.patch`
    docker-compose.yaml        # service MUST be named `main` (Harbor's own overlays require it);
                                # add postgres/redis here too unless the task needs its own variant
  setup/
    regression.patch           # COPYed into the image and applied by Dockerfile's RUN step
  solution/
    solve.sh                   # the Oracle — reverses regression.patch at runtime, never shown to
                                # the agent
  tests/
    test.sh                    # verifier — runs the real test(s), writes reward.txt + reward.json
```

`instruction.md` should read like something a real user or rights-holder would actually say —
describe the *symptom*, not the defect. If you can point at the file/function from the instruction
text alone, it's too specific.

## 4. `tests/test.sh` contract

- Runs the real, relevant test file(s) inside the container.
- Writes both `/logs/verifier/reward.txt` (bare `0`/`1`) and `/logs/verifier/reward.json` (richer:
  `task_success`, `correct_diagnosis`, `policy_compliance`, `side_effect_safety`) — both are real,
  supported Harbor outputs. If you haven't built real side-effect-safety scoring yet (e.g. "did the
  agent touch only the files it should have"), say so with a fixed placeholder and a comment —
  don't silently claim a check that doesn't exist.
- Must fail on a no-op (agent makes no change).

## 5. Validate end to end before calling it done

Prefer real Harbor commands over a hand-simulated substitute — they exercise the actual mechanism
(image build from `environment/Dockerfile`, the `main` service name requirement, reward-file
parsing) rather than something that merely resembles it:

```
scripts/vendor-source.sh
harbor run -p tasks/<task-id> -a oracle -e docker -y --jobs-dir /tmp/jobs   # expect task_success: 1
harbor run -p tasks/<task-id> -a nop -e docker -y --jobs-dir /tmp/jobs      # expect task_success: 0
```

If either doesn't come back as expected, `harbor task start-env -p tasks/<task-id> -i` drops you
into a shell in the actual built environment to debug interactively. See
[`docs/harbor-install.md`](harbor-install.md) for the full command reference and known gaps (in
particular: `network_mode = "no-network"` isn't enforced yet under local Docker).

## 6. Update tracking

Reflect the new task in the POC Task Tracker (Notion) and, if it changes the shape of the plan, in
POC Scope/POC Plan.
