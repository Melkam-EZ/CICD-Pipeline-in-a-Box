# CI/CD Pipeline in a Box

A complete CI/CD system that runs on **one EC2 instance**: a self-hosted Git server, a CI runner, a private Docker registry and an app that is tested, built, pushed and deployed automatically on every `git push`. A bad commit is stopped by the tests, and a commit that passes the tests but breaks the container is stopped by a health gate, so the live app is never taken down.

**Start with [STEPS.md](STEPS.md)**: prerequisites first (including the exact security group rules and every `chmod`), then copy-paste commands.

```
 you (laptop)                          one EC2 instance (Docker Compose)
 ───────────                           ─────────────────────────────────────────────────
  git push  ──── SSH tunnel ────▶  Gitea :3000  ──queues job──▶  Runner (Gitea Actions)
  browser   ─────────────────────▶  (git + UI)                      │ host network + docker.sock
                                                                    ▼
                                      pipeline.yaml steps on the instance's Docker daemon:
                                      1 checkout ▶ 2 unit tests ▶ 3 build ▶ 4 push ──▶ Registry :5000
                                                                    │
                                      5 deploy.sh: start candidate :8082 ▶ health check
                                           ├─ healthy   ▶ replace live container :8081
                                           └─ unhealthy ▶ delete candidate, old version keeps serving
```

## What's in it

| Piece | What it demonstrates |
|---|---|
| `docker-compose.yml` | The whole platform as code: Gitea, registry and runner, with memory limits and localhost-only ports |
| Gitea + Gitea Actions | Self-hosted Git with a GitHub-Actions-style pipeline engine (stands in for GitHub/GitLab CI) |
| `runner/` | A CI runner image that can drive the host's Docker daemon (build, push, run) |
| Local registry (`registry:2`) | A private image registry (stands in for ECR / Docker Hub) |
| `sample-app/` | A tiny Python service with unit tests and a multi-stage Dockerfile |
| `sample-app/.gitea/workflows/pipeline.yaml` | The pipeline: checkout, test, build, push, deploy, verify |
| `sample-app/deploy/deploy.sh` | Health-gated deploy with automatic rollback |
| `scripts/` | `setup`, `preflight`, `up`, `smoke`, `demo`, `destroy` |

## The demo scenarios (`./scripts/demo.sh`)

| Scenario | Change pushed | Expected result |
|---|---|---|
| `good` | Version bumped to 1.1.0 | All steps green, `:8081` now reports 1.1.0 |
| `bad-test` | Greeting text changed, a unit test breaks | Pipeline fails at step 2, nothing is deployed, old version still live |
| `bad-health` | App listens on loopback only (tests can't see this) | Tests pass, image is built and pushed, deploy is blocked at step 5, old version still live |

After each bad scenario a revert commit is pushed and the pipeline goes green again.

## Key ideas to be able to explain

- **CI vs CD:** CI proves every commit builds and passes tests. CD ships it automatically.
- **Pipeline as code:** the pipeline is a YAML file in the repo, versioned and reviewed like any other code.
- **Immutable, traceable artifacts:** every image is tagged with the commit SHA (`hello-app:<sha>`), so you can always tell what is running and which commit produced it.
- **Tests in the build:** unit tests run in a Docker build stage (`--target test`), so the runner needs no language toolchain and tests run in the same base image as production.
- **Gates:** two gates protect production, the tests and the post-start health check. The `bad-health` scenario shows why tests alone are not enough.
- **Rollback safety:** the candidate runs beside the live container first, so a bad release never replaces a good one. If the swap itself fails, the previous image is restarted.
- **Simulating a cloud service:** the local registry replaces ECR, Gitea replaces GitHub, so nothing outside the one instance is needed.

## Repo layout

```
README.md  STEPS.md  DIAGRAM_PROMPT.md  .env.example  docker-compose.yml
runner/            Dockerfile, config.yaml          CI runner image and settings
sample-app/        the app that gets deployed (pushed to Gitea by up.sh)
  app/             main.py (stdlib only)
  tests/           unit tests
  deploy/          deploy.sh (health-gated deploy + rollback)
  .gitea/workflows/pipeline.yaml
  Dockerfile       multi-stage: base, test, runtime
scripts/           lib.sh setup.sh preflight.sh up.sh smoke.sh demo.sh destroy.sh
tests/             sanity tests for this repo
```

## Limitations (kept simple on purpose)

- **Not zero-downtime:** the swap from old to new container takes about a second. Project 2 in this series covers zero-downtime deploys.
- **The runner has root-equivalent power** on the instance (it uses the Docker socket). Fine for a private demo box, not for running other people's code.
- **Plain `git clone` instead of `actions/checkout`**, so the pipeline never depends on github.com. The Gitea instance is public-read inside the box, protected by the localhost-only binding.
- **SQLite, single runner, no HA.** Everything is bound to `127.0.0.1` and reached through an SSH tunnel.
- **No notifications, approvals, staging environment or image scanning.** A DevSecOps scanning pipeline is a later project in this series.
- **Pinned image versions** (Gitea 1.22.6, act_runner 0.2.11, registry:2, docker:27-cli, python:3.12-slim) can be changed in `.env` if one is ever withdrawn.
