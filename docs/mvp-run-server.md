# ChannelForge World MVP: Harbor run server

> **Status: draft for team review.** This document defines the Phase 2 MVP server baseline and
> calibration model. Revise measured capacity after the single-image artifact exists.

## 1. Purpose

The run server is the controlled Linux host on which Harbor validates, calibrates, and benchmarks
ChannelForge World tasks. It consumes the single image produced by Phase 1; it does not rebuild the
three upstream products from moving branches.

The MVP uses model variance as the benchmark dimension. The agent harness remains fixed so a score
change is attributable primarily to the model and task, not to a different coding-agent product.

## 2. Initial server baseline

Use the following as a provisioning starting point, then revise it from observed trial data:

| Resource | Initial baseline |
|---|---|
| OS/architecture | Linux amd64, current supported Ubuntu LTS |
| CPU | 8 vCPU |
| Memory | 32 GB RAM |
| Disk | 200 GB SSD |
| Container runtime | Docker Engine with Compose v2 |
| Python | 3.12 |
| Harbor | 0.22.0 in a repository-local virtual environment |
| Environment provider | Harbor local Docker provider |

Disk sizing must cover the published image, unpacked image layers, task-derived images, concurrent
trial containers, build cache, and job output. The existing reference monolithic world demonstrates
that apparent image size differs between compressed content, shared local layers, and exported
artifacts; record actual Phase 1 measurements before setting the production minimum.

Only Harbor's local Docker provider has been validated for this repository. Daytona, E2B, Modal,
Runloop, GKE, and other providers are outside MVP scope unless separately proven.

## 3. Host preparation

Install and verify:

```bash
docker version
docker compose version
python3 --version
```

Run Docker as a dedicated benchmark operator rather than granting unrelated users access to the
daemon. Ensure the operator has enough disk space and can create containers, networks, and local
images.

Clone or copy `channelforge-world` at the benchmark release commit. Create an isolated Harbor
environment:

```bash
cd channelforge-world
python3 -m venv .venv
source .venv/bin/activate
python -m pip install "harbor==0.22.0"
harbor --version
```

Do not use an unpinned system-wide Harbor install. Before upgrading Harbor, generate a fresh task
scaffold, compare its schema with the repository's `schema_version = "1.4"` tasks, and rerun the
server acceptance test.

## 4. Acquire the world image

Google Artifact Registry is the likely publication mechanism, but its project/repository/access
policy is not selected yet. Until that decision is implemented, this section's contract is:

1. obtain the immutable image reference or an approved offline export;
2. authenticate without embedding credentials in the repository;
3. pull or load the image;
4. verify its expected tag, digest, and `linux/amd64` platform; and
5. run the Phase 1 health and sample-data preflight.

External teams do not need checkouts of ChannelForge, ssaiadserver, or fast-world-tv to consume the
published artifact.

The proposed standalone port mappings are:

```bash
docker run --name channelforge-world \
  -p 18080:8080 \
  -p 14000:4000 \
  -p 14010:4010 \
  -p 13000:3000 \
  -p 19001:9001 \
  <immutable-world-image>
```

This exposes the ChannelForge raw origin/UI, SSAI control plane, SSAI stitched stream, FAST viewer,
and optional MinIO diagnostics on collision-resistant host ports. Internal dependencies remain
unpublished and communicate over loopback.

## 5. Secrets and environment

Store model-provider credentials in a server-local `.env` that is excluded from version control:

```text
OPENAI_API_KEY=...
OPENROUTER_API_KEY=...
```

Only add provider keys required by the selected model roster. The current repository has also
exercised `GEMINI_API_KEY` and `GROQ_API_KEY`, but neither is required for the base calibration
model.

Protect the file with restrictive permissions:

```bash
chmod 600 .env
```

Never bake provider credentials into the world image, copy them into a task directory, include
them in job artifacts, or print their values in setup logs. Fixture-only in-world credentials are
not model credentials and must be clearly labeled as synthetic.

## 6. Fixed agent harness and base model

### Agent harness

Use `terminus-2` for calibration and the final model-comparison benchmark. `nop` and `oracle` are
controls, not benchmark agents. Changing to Codex or Claude Code would add agent-harness variance
and requires a separate study.

### Calibration model

Use **`openai/gpt-5.6-luna`** as the MVP base calibration model.

Reasons:

- it is already working with `terminus-2` in this repository;
- it has the deepest stable comparison history across the POC tasks;
- it represents the intended mid-level/cost-efficient tier rather than the frontier ceiling; and
- the MVP difficulty target is defined directly against it.

Record the exact provider/model identifier in every run. If the provider offers a dated immutable
snapshot, select and document that snapshot before the first official calibration batch. Do not
silently replace the base model after task calibration begins.

Frontier and open-weight models belong to the Phase 5 leaderboard roster. They do not replace Luna
as the Phase 4 calibration reference.

## 7. Task validation sequence

Before spending model tokens on a new task:

```bash
source .venv/bin/activate

harbor run -p tasks/<task> -a nop -e docker -y \
  --jobs-dir jobs/validation/<task>/nop

harbor run -p tasks/<task> -a oracle -e docker -y \
  --jobs-dir jobs/validation/<task>/oracle-1
harbor run -p tasks/<task> -a oracle -e docker -y \
  --jobs-dir jobs/validation/<task>/oracle-2
harbor run -p tasks/<task> -a oracle -e docker -y \
  --jobs-dir jobs/validation/<task>/oracle-3
```

Required results:

- no-op: `task_success = 0.0`;
- Oracle: `task_success = 1.0` on all three runs; and
- at least one documented plausible wrong fix: `task_success = 0.0`.

If any control result is wrong, stop. Do not use calibration trials to debug the task harness.

## 8. Ten-trial calibration run

After the controls and adversarial probe pass:

```bash
harbor run -p tasks/<task> \
  -a terminus-2 \
  -m openai/gpt-5.6-luna \
  -k 10 \
  -n <measured-safe-concurrency> \
  -e docker \
  -y \
  --env-file .env \
  --jobs-dir jobs/calibration/<task>/gpt-5.6-luna
```

Start with concurrency `1` while validating the single image. Increase only after observing peak
RAM, CPU, disk growth, provider rate limits, and trial interference. Do not turn the initial server
estimate into an untested concurrency promise.

The target `task_success` band is **0.1 through 0.6** across ten trials. Below the band, inspect the
verifier, specification, and failed trajectories before softening the task. Above the band, harden
the task or grader. Abandon a candidate after one or two unsuccessful adjustment rounds.

## 9. Result storage

Use a unique, durable jobs directory for every validation, calibration, and benchmark batch. Keep:

- top-level and per-trial `result.json`;
- `agent/trajectory.json`;
- verifier reward and test logs; and
- run configuration needed to reproduce the cell.

Before committing selected results, remove terminal recordings and bulky per-episode debug files
according to the established pilot procedure. Never remove the reward or trajectory evidence that
backs the published analysis.

For every batch, record:

- world image tag and digest;
- channelforge-world commit;
- task version;
- Harbor version;
- agent and exact model identifier;
- run flags, concurrency, and timeout;
- start/end timestamps; and
- input, cached, and output tokens plus cost where available.

## 10. Harbor and single-image startup interaction

Harbor 0.22.0's Docker build and prebuilt-image overlays set the `main` service command to
`sh -c "sleep infinity"`. This is useful for keeping the agent container alive, but it overrides
the single image's supervisord `CMD`.

Before the server setup is declared complete, prove one canonical task-environment bootstrap that:

1. leaves the service named `main`;
2. starts supervisord and all task-required programs;
3. preserves Harbor's ability to attach the agent shell;
4. works with a task-specific child image and regression;
5. keeps the Oracle and verifier outside the agent's readable/writable paths; and
6. survives a real Oracle/no-op run.

Do not assume a successful standalone `docker run` proves Harbor compatibility.

## 11. Network policy

Application processes communicate only over loopback inside the single container. Evaluation
trials must block live external egress from the agent/world while allowing the Harbor host to call
the chosen model provider through the agent harness.

The existing tasks use `network_mode = "public"`, and older documentation records no-network as
an open gap. The installed Harbor 0.22.0 package contains Docker egress-control and no-network
compose overlays, but their presence is not proof that this world's configuration is correct.
Validate the actual task path with positive loopback checks and a negative outbound-network test
before claiming isolation.

## 12. Operations and troubleshooting

- Use `harbor view <jobs-dir>` to inspect trajectories and rewards.
- Check `docker system df` before large calibration batches.
- Treat provider authentication, billing, rate limits, and model-format errors separately from
  task failures.
- Read failed trajectories before declaring a model incapable.
- Confirm OpenRouter credits and model availability before a paid multi-trial batch.
- Keep the host clock synchronized; fixture time itself follows the deterministic world-time rule
  defined by Phase 1.

## 13. Server acceptance gate

Phase 2 is complete only when a fresh server can:

1. install the pinned Docker/Python/Harbor toolchain from the documented procedure;
2. acquire and verify the immutable single-image release;
3. boot the image and confirm every process plus both preloaded databases;
4. play or probe both the raw Forge HLS stream on port `18080` and the SSAI-stitched stream on
   `14010`, with every referenced segment resolving locally;
5. run one retained task with `nop` and receive `task_success = 0.0`;
6. run the same task with `oracle` and receive `task_success = 1.0`;
7. run one real `terminus-2` + `openai/gpt-5.6-luna` trial;
8. demonstrate blocked runtime egress without breaking internal loopback services;
9. capture the smoke test's network activity and confirm no public hostname was contacted;
10. retain complete result evidence; and
11. repeat the procedure without undocumented manual intervention.

## 14. Deferred decisions

The following are intentionally not chosen by this draft:

- Google Artifact Registry project, repository, region, IAM model, and retention policy;
- final server provider and machine SKU;
- production concurrency;
- a dedicated run-monitoring UI; and
- the Phase 5 leaderboard roster and budget.

None blocks drafting or locally proving the Phase 1 image and Phase 2 Harbor bootstrap.
