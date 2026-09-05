# RL environment / "world" builder landscape

Research note, 2026-09-05 (web search). Competitive/positioning context for `channelforge-world`
— not a task or plan, just a landscape snapshot to revisit later. Facts below are from live web
search results at the time of writing; re-verify before quoting externally, this market moves fast.

## The market is real and funded

Anthropic leadership has talked about spending **$1B+ on RL environments**. Mechanize was
reportedly offering **$500K salaries** to engineers who build them. The market splits into three
groups:
- **Human-data companies that pivoted in**: Scale AI, Surge AI, Mercor, Turing, Centific.
- **Environment-native startups**: Mechanize, Fleet AI, HUD, Veris AI, Plato, Bespoke Labs,
  AfterQuery, Datacurve, Proximal, Huzzle Labs, Vmax, Chakra Labs, Halluminate, Matrices.
- **Open ecosystems**: Prime Intellect.

## Closest peers to what this repo is doing

These build environments the same way `channelforge-world` does — wrap a real, existing,
multi-service product rather than author synthetic tasks from scratch:

- **Fleet AI** — builds high-fidelity RL "gyms" that replicate enterprise software (Salesforce,
  Excel, browser/desktop workflows) so labs/enterprises can train and evaluate computer-use
  agents. Structurally the same move as vendoring ChannelForge/ssaiadserver/fast-world-tv and
  wrapping them in Harbor.
- **Plato** — builds simulated enterprise/web "worlds," recreating real websites/software as RL
  environments with structured APIs for interaction, state tracking, and scoring. This framing
  (structured API + state tracking + scoring) is close to this repo's own `world-control`/reset/
  verifier design goals from `docs/world-blueprint-assessment.md`.
- **Veris AI** — also builds simulated enterprise/web worlds (paired with Plato in most market
  writeups; less differentiated in the search results found so far).
- **HUD** — wraps arbitrary existing software (a game, a browser, Google Sheets) in a Docker
  container to turn it into a scalable RL environment with no rebuild required — the "wrap what
  already exists" philosophy, same spirit as this world's compose-and-patch approach over
  building synthetic apps from scratch.

## Coding-specific peers (domain overlap, not approach overlap)

Single-repo/code-only, not cross-service — closer to Terminal-Bench/SWE-bench territory than to
this repo's cross-repo product-loop approach:

- **Mechanize** — highest-profile: ex-Epoch AI researchers, $9.1M raise (April 2026),
  "replication training" (agents recreate implementations from spec) for strong code-task reward
  signals.
- **AfterQuery, Datacurve, Proximal, Huzzle Labs, Vmax** — vendors building RL environments
  specifically for coding/software-engineering agents.

## Infra/tooling layer (the plumbing under environments, not environments themselves)

- **Harbor** — already in use here (`harbor run -a terminus-2 ...`). Also the official harness for
  Terminal-Bench 2.0; can evaluate arbitrary agents, build/share environments and benchmarks, run
  RL rollouts, and pull in third-party datasets like SWE-Bench and Aider Polyglot.
- **Bespoke Labs** — open-source curation/eval tooling, not environment-building itself.

## Positioning takeaway

Fleet AI / Plato / HUD are the nearest comparables in **approach** (real software, faithfully
wrapped, structured scoring). Mechanize and the coding-specific vendors are the nearest
comparables in **domain** (agentic coding tasks). `channelforge-world` sits at an intersection
none of the surveyed vendors currently occupy: a real, cross-service **media/adtech** product
turned into a world, rather than enterprise SaaS (Fleet AI/Plato/HUD's domain) or generic code
repos (Mechanize/AfterQuery/Datacurve's domain).

## Sources

- [RL Environment Companies in 2026: The Landscape | Troveo](https://www.troveo.ai/resources/rl-environment-companies)
- [RL Environment Vendors: 2026 Directory & Rankings | RL List](https://www.rl-list.com/)
- [Mechanize: RL environment vendor profile | RL List](https://www.rl-list.com/vendors/mechanize)
- [Fleet AI: RL environment vendor profile | RL List](https://www.rl-list.com/vendors/fleet-ai)
- [Best Platforms for Publishing RL Environments to Model Labs | HUD](https://www.hud.ai/resources/best-platforms-publishing-rl-environments-model-labs)
- [RL Environments and RL for Science: Data Foundries and Multi-Agent Architectures | SemiAnalysis](https://newsletter.semianalysis.com/p/rl-environments-and-rl-for-science)
- [Top 40 RL Environments Startups and Companies in 2026 | AlignList](https://alignlist.com/guides/top-40-rl-environments-startups-and-companies)

## Status

Landscape snapshot only — no action items. Revisit when the POC's pilot results are in and a
positioning/pitch conversation becomes relevant.
