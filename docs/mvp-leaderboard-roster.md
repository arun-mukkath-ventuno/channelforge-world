# MVP / showcase leaderboard — model roster research

Research note, 2026-09-05. Downstream of the POC — not something to act on until the POC
(`docs/poc-scope.md`) actually finishes and validates the harness/tasks. Kept here so the
reasoning and the live-catalog data aren't lost before then.

## How real agentic-coding leaderboards build their roster

Looking at how Terminal-Bench, SWE-bench Verified, and METR-style benchmarks structure their
comparisons, five principles recur:

1. **Cross-lab coverage, not cross-model coverage.** Credibility comes from having every major
   lab's flagship represented, not five variants from one vendor. A leaderboard with 4 OpenAI
   models and nothing else reads as a vendor benchmark, not a world.
2. **Tiering by cost/capability, shown side by side.** Frontier (can this be solved at all),
   mid/cost-efficient (what a real team would actually deploy), and small/fast (latency baseline)
   — real leaderboards report cost-per-task next to the score for exactly this reason.
3. **Open-weight representation is now expected**, not optional — it's what lets someone outside
   the benchmark's own infra reproduce a result.
4. **A stable reference model, pinned and re-run every release** — isolates "the task/verifier
   changed" from "the model changed" when scores move over time.
5. **A deliberately weak control** — confirms tasks actually discriminate difficulty. This is
   literally milestone 3 in `docs/world-blueprint-assessment.md`: reject near-0%/near-100% tasks,
   target ~30-70% pass rate on a strong agent — you need a weak model in the mix to see the floor,
   not just the ceiling.

## What's actually available, with zero new keys

Checked both live catalogs against the keys already in `.env` (2026-09-05). This mattered more
than expected: **`OPENROUTER_API_KEY` alone already routes to every major lab** — OpenAI,
Anthropic, Google, xAI, DeepSeek, Qwen, Moonshot (Kimi), Z-AI (GLM), Mistral, Meta-Llama, MiniMax.
A full cross-lab MVP roster needs no new signups, unlike the POC where picks were constrained by
free-tier limits.

Current flagships per lab (checked live via each provider's `/v1/models`):

| Lab | Flagship | Notes |
|---|---|---|
| OpenAI | `gpt-6-astra` (`-pro` variant exists above it) | Newest generation; reachable direct via `OPENAI_API_KEY` too, not just OpenRouter |
| Anthropic | `claude-opus-5` | `claude-sonnet-5` one step down, `claude-haiku-4.5` for the small tier |
| Google | `gemini-3.8-flash` | No `-pro` tier currently listed — this generation's ceiling is the flash line |
| xAI | `grok-4.6` | `grok-4.20-multi-agent` also exists (2M ctx, agent-orchestration-flavored) |
| DeepSeek | `deepseek-v4-pro` | Open-weight, API-served |
| Moonshot | `kimi-k3` | `kimi-k2-thinking` if an extended-reasoning entry is wanted |
| Z-AI | `glm-5.3` | `glm-5.2:free` still exists but is the congested pool already hit once (see `docs/model-providers.md`) |
| Qwen | `qwen3.8-max-0902` | Alibaba's frontier line |

## Proposed MVP/showcase roster — 10 models, 4 tiers

| Tier | Purpose | Models |
|---|---|---|
| Frontier | The ceiling — proves the task is solvable at all | `openai/gpt-6-astra`, `anthropic/claude-opus-5` |
| Frontier, other labs | Cross-lab credibility — the thing a single-vendor roster can't claim | `google/gemini-3.8-flash`, `x-ai/grok-4.6` |
| Mid/cost-efficient | What a real team would actually run day to day; also stable reference points | `openai/gpt-5.6-luna` (already deeply characterized in this repo — keep as the pinned reference model), `anthropic/claude-sonnet-5` |
| Open-weight | Reproducibility outside our own infra | `deepseek/deepseek-v4-pro`, `moonshotai/kimi-k3`, `z-ai/glm-5.3` |
| Weak control | Confirms tasks discriminate difficulty, not just pass/fail on anything competent | `anthropic/claude-haiku-4.5` or `openai/gpt-5.4-nano` — pick whichever is cheaper per token, since this one's only job is to fail informatively |

This intentionally drops the `:free` OpenRouter models used in the POC roster (`docs/model-
providers.md`) — those were a POC-only workaround for not wanting to spend on the pilot. For a
showcase leaderboard, paid access to the same labs is more defensible: no shared-pool congestion
risk (the pattern already hit with `glm-5.2:free`/Nemotron), and no free-tier request caps forcing
artificially low concurrency.

## Operational math this roster implies

At the blueprint's target scale (10 attempts × 5 tasks), 10 models is **500 trials** instead of
the POC's 200 — and every model here is paid, so this is a real budget decision, not just a time
one. Two things to decide before committing:

- **Pin exact model strings with dates/snapshots where the provider offers them** (e.g. a dated
  snapshot of `gpt-6-astra`) so a leaderboard number doesn't silently shift when a lab updates a
  model behind a stable name.
- **Refresh cadence policy**: labs ship new versions monthly at this pace — this project alone has
  already watched `gpt-5.6` iterate through `-luna`/`-sol`/`-terra` and `gpt-6-astra` appear
  mid-project. A showcase leaderboard needs a stated "as of" pin and a re-run trigger, or the
  numbers go stale within weeks.

## Status

Research only — not started. Gated on the POC (`docs/poc-scope.md`) actually completing its pilot
and validating the harness/tasks/model-roster approach at small scale first.
