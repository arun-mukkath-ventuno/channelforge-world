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

```
tasks/<task-id>/
  instruction.md              # bug report or feature request — no file/function names, no hints
  task.toml                   # schema 1.4 + a [task.setup] hook pointing at setup/apply.sh
  environment/
    docker-compose.yaml       # `include: [path: ../../../world/docker-compose.yaml]` unless this
                               # task needs its own DB variant
  setup/
    regression.patch
    apply.sh                  # `cd /app && patch -p1 < /task/setup/regression.patch`
  solution/
    solve.sh                  # the Oracle — reference fix, never shown to the agent
  tests/
    test.sh                   # verifier — runs the real test(s), writes /logs/verifier/reward.json
```

`instruction.md` should read like something a real user or rights-holder would actually say —
describe the *symptom*, not the defect. If you can point at the file/function from the instruction
text alone, it's too specific.

## 4. `tests/test.sh` contract

- Runs the real, relevant test file(s) inside the container.
- Writes `/logs/verifier/reward.json` with at least `task_success`, `correct_diagnosis`,
  `policy_compliance`, `side_effect_safety`. If you haven't built real side-effect-safety scoring
  yet (e.g. "did the agent touch only the files it should have"), say so with a fixed placeholder
  and a comment — don't silently claim a check that doesn't exist.
- Must fail on a no-op (agent makes no change) and on the unpatched-but-unfixed state.

## 5. Validate end to end before calling it done

```
scripts/vendor-source.sh
cd world && docker compose up -d --build
```

Then, in order, confirming each step:

1. `curl localhost:8000/docs` → healthy.
2. Copy in `setup/regression.patch`, apply it inside `app` → bug present.
3. Copy in `tests/test.sh`, run it → verifier fails, `reward.json` shows `task_success: 0`.
4. Make the fix by hand (or apply `solution/solve.sh`'s reverse patch), `restart-api` inside the
   container.
5. `curl localhost:8000/docs` again → still healthy (this is the step that catches a broken
   `restart-api`/PID 1 lifecycle — it's happened once already, see `docs/setup.md`
   Troubleshooting).
6. Re-run `tests/test.sh` → passes, `reward.json` shows `task_success: 1`.

Only once all six steps are green does `harbor run` wiring (still unconfirmed — see `task.toml`'s
comments) become worth debugging; don't chase Harbor-specific failures before the mechanism itself
is proven manually.

## 6. Update tracking

Reflect the new task in the POC Task Tracker (Notion) and, if it changes the shape of the plan, in
POC Scope/POC Plan.
