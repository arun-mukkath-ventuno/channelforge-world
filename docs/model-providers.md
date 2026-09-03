# Testing tasks against other models

`harbor run -a terminus-2 -m <model>` (the pattern used to validate task-02/03/04 against a real
non-oracle agent, see `docs/ecosystem.md`) is not tied to one model or vendor. `terminus-2` runs
on [LiteLLM](https://docs.litellm.ai/docs/providers) internally, so `-m` accepts any
`<provider>/<model>` string LiteLLM supports (140+ providers) — no code changes, just an API key
in `.env` (loaded via `--env-file .env`) and the right prefix on the model string.

## What's already configured

`.env` currently holds `OPENAI_API_KEY` + `OPENAI_API_MODEL`, used for every real-agent run so far
(`openai/gpt-5.6-luna`, via `terminus-2`).

## Free / low-friction providers for open-weight models

Researched 2026-09-03 (web search — verify current rate limits before relying on them, they
change often). Each row is one env var to add to `.env`, no other setup:

| Provider | Env var | Model string example | Free tier (no card) |
|---|---|---|---|
| **Groq** | `GROQ_API_KEY` | `groq/moonshotai/kimi-k2-instruct-0905`, `groq/qwen/qwen3-32b`, `groq/llama-3.3-70b-versatile` | 30 req/min, 1,000/day |
| **OpenRouter** | `OPENROUTER_API_KEY` | `openrouter/qwen/qwen3-coder:free`, `openrouter/deepseek/deepseek-chat:free` (check current `:free`-suffixed catalog at openrouter.ai/models) | 20 req/min, 50/day baseline |
| **Cerebras** | `CEREBRAS_API_KEY` | `cerebras/llama-3.3-70b` | 30 req/min, ~1M tokens/day |
| **Google AI Studio** | `GEMINI_API_KEY` | `gemini/gemini-2.5-flash` | up to 1,500/day (not open-weight, useful as a baseline) |
| **Mistral** | `MISTRAL_API_KEY` | `mistral/codestral-latest` | ~1B tokens/month (opts into data training) |

Groq and Cerebras run on dedicated inference hardware (LPU / wafer-scale) and are noticeably
faster per-turn than a typical hosted endpoint — matters for a 30-150-turn trajectory, since each
turn is a round trip.

## Which open-weight models are actually good at this

Current (2026) write-ups on agentic coding converge on **Qwen3-Coder**, **Kimi K2/K2.6**,
**DeepSeek V3/V4**, and **GLM-4.5-Air/5.1** as the strongest open-weight models for tool-using
coding agents — closing in on closed-source frontier models on agentic benchmarks. Groq and
OpenRouter both serve Kimi K2 and Qwen3 variants, which is the best overlap of "actually free"
and "actually good at this."

## Running a task against a new provider

1. Add the provider's key to `.env`: `<PROVIDER>_API_KEY=...`
2. Run exactly as before, swapping `-m`:
   ```
   harbor run -p tasks/task-0N-... -a terminus-2 -m <provider>/<model> -e docker -y \
     --env-file .env --jobs-dir /tmp/harbor-jobs
   ```
3. Pull the real turn/tool-call count from the run's `agent/trajectory.json` (same method used
   for every real-agent run recorded in `docs/ecosystem.md`):
   ```python
   import json
   d = json.load(open("<job-dir>/.../agent/trajectory.json"))
   turns = [s for s in d["steps"] if s.get("tool_calls")]
   print(len(turns), sum(len(s.get("tool_calls") or []) for s in d["steps"]))
   ```
4. If `task_success` comes back 0.0, diagnose the actual trajectory before assuming a model
   limitation — task-03's history (`docs/ecosystem.md`) shows a 0.0 can be a genuine
   instruction-ambiguity bug in the task itself, not the model.

## Status

Not yet run against anything but `openai/gpt-5.6-luna`. Groq is next (key setup in progress as of
2026-09-03) — results and turn counts to be added here or to `docs/ecosystem.md` once available.
