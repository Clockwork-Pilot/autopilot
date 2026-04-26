# autopilot

Issue-driven coding agent orchestration: GitHub Actions workflows and composite actions. Pairs with the `autopilot-ws` workspace repo, which provides the Docker image where the agent runs and the ansible playbook that installs the self-hosted runner.

## Contents

- [autopilot](#autopilot)
  - [Contents](#contents)
  - [Flow](#flow)
  - [Safety model (private vs. public)](#safety-model-private-vs-public)
  - [Runner PAT setup](#runner-pat-setup)
  - [Installing extra dependencies](#installing-extra-dependencies)
  - [Opening PRs against the upstream repo (optional)](#opening-prs-against-the-upstream-repo-optional)
      - [Option A — Classic PAT (typical: you are NOT a collaborator on upstream)](#option-a--classic-pat-typical-you-are-not-a-collaborator-on-upstream)
      - [Option B — Fine-grained PAT (only if you have write access on upstream)](#option-b--fine-grained-pat-only-if-you-have-write-access-on-upstream)

## Flow

Apply an `agent-run` label to a GitHub issue → the agent runs against a dedicated branch, opens a PR, and posts a constraints report back as an issue comment.

1. **Pick a target repo.** Fork or greenfield, public or private. Copy `.github/workflows/{coding-agent,issue-trigger}.yml` (and optionally `check-constraints.yml`) into it. `spec.k.json` ties a repo into the constraint loop and is opt-in.
2. **Install a self-hosted runner on your own machine.** Follow the [autopilot-ws](https://github.com/Clockwork-Pilot/autopilot-ws) README — you run its ansible playbook locally to provision the runner, registering it with your GitHub login as its label.
3. **One-time docker bootstrap:** run `./run-docker-workspace.sh` locally with `PROJECT_ROOT` set, so the runner's docker is primed.
4. **Open an issue** describing the feature. The agent runs a constraint-driven loop: patch `spec.k.json`, watch each new constraint FAIL on current code (Zero-State Rule), then implement until every constraint PASSES. Optional YAML frontmatter:
   ```
   ---
   timeout: 20                  # minutes, default 10
   model: <model-id>            # default claude-haiku-4-5
   merge_into_upstream: false   # default false — see below
   pr_branch: <branch>          # default agent/<issue-number>-<title-slug>
   base_branch: <branch>        # default repo's default branch
   ---
   <describe feature and its constraints>
   ```
5. **Click `agent-run`.** `issue-trigger.yml` strips the label (re-triggerable), preflights the runner, and dispatches `coding-agent.yml`. Re-applying the label resumes an existing `agent/<issue>-<slug>` branch.

`merge_into_upstream: true` opens the PR against the parent repo instead of your fork — see [Opening PRs against the upstream repo](#opening-prs-against-the-upstream-repo-optional).

## Safety model (private vs. public)

GitHub recommends against self-hosted runners on **public** repos because a fork's PR can run arbitrary code on your runner. Autopilot blunts this two ways:

- **Per-user runner routing.** `issue-trigger.yml` sets `runner_label = github.event.sender.login`, so a job only lands on a runner labeled with the *triggering* user's GitHub login. Since you only register a runner under your own username, a stranger applying the label targets a runner under *their* login (which doesn't exist on your hardware) and the preflight fails fast.
- **Cross-repo PAT isolation.** The upstream-PR job declares `environment: upstream-pr`, branch-restricted to `main`. The PAT (`UPSTREAM_PR_TOKEN`) is loaded only into that one job and never reaches the self-hosted runner where the agent executes.

On private repos this is moot — only collaborators can push branches or open PRs.

**What runs where.** `coding-agent.yml` splits jobs by `runs-on`:
- Self-hosted (`[self-hosted, <runner_label>]`): the agent execution + constraint check jobs (your runner, your hardware, your minutes).
- `ubuntu-latest` (GitHub-hosted minutes): orchestration jobs — fetch-issue, parse-issue, choose-branch, open-pr, comment-agent-result. Cheap (seconds each) but counts against your private-repo minutes budget on Free/Team.

**Permissions checklist (private repos):** `Settings → Actions → General` allows running workflows; default `GITHUB_TOKEN` has at least read/write for contents + pull-requests. `actions/checkout` works for the agent's own checkout out of the box; cloning *other* private repos needs credential handling baked into your custom Dockerfile (see below) or a mounted git credential helper.

## Runner PAT setup

`issue-trigger.yml` calls `GET /repos/{repo}/actions/runners` to confirm an online runner exists for the triggering user — so a missing runner produces a clear "no runner found for **@you**" comment instead of a job that queues forever.

That endpoint sits under `Administration`, which `secrets.GITHUB_TOKEN` cannot grant from inside a workflow. Hence one user-scoped PAT, stored as the `RUNNERS_PAT` repo secret, scoped to a single repo with `Administration: Read-only` — strictly less power than the classic `repo` scope most tutorials reach for.

**Generate** at <https://github.com/settings/personal-access-tokens/new>:

| Field | Value |
|---|---|
| *Token name* | e.g. `autopilot runner lookup` |
| *Expiration* | 90 days (calendar the rotation) |
| *Resource owner* | your user account |
| *Repository access* | *Only select repositories* → only the fork running the workflow |
| *Repository permissions* → `Administration` | **Read-only** |

Leave everything else at *No access*. Copy the `github_pat_…` string (shown once).

**Store** at `https://github.com/<you>/<fork>` → *Settings* → *Secrets and variables* → *Actions* → *New repository secret*:
- *Name*: `RUNNERS_PAT` (case-sensitive, no whitespace).
- *Secret*: paste the token (no quotes, no `Bearer` prefix).

**Verify** by labeling a test issue. The *Issue Trigger* workflow should pass *Ensure RUNNERS_PAT*. A `403`/`Resource not accessible` at *Check runner exists for actor* means the PAT lacks `Administration: Read-only` — regenerate.

A 90-day fine-grained PAT goes silently dead on day 91; rotate by editing the same secret (don't recreate, the name has to stay stable).

## Installing extra dependencies

The agent runs inside `ghcr.io/clockwork-pilot/autopilot-ws`, a general-purpose toolchain. Need extras (`ffmpeg`, a specific Python/Rust, a vendored CLI)? Add a Dockerfile to your project repo and pass its path to image preparation. Image build/cache/tag is handled by [`ensure-docker-image`](.github/actions/ensure-docker-image/README.md) — a Buildx wrapper with unified caching across GitHub-hosted and self-hosted runners.

A working example to copy and adapt: [`autopilot-selftest/Dockerfile.agent-sample`](https://github.com/Clockwork-Pilot/autopilot-selftest/blob/main/Dockerfile.agent-sample).

```dockerfile
ARG BASE_IMAGE=ghcr.io/clockwork-pilot/autopilot-ws:latest
FROM ${BASE_IMAGE}

RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg libsndfile1 \
    && rm -rf /var/lib/apt/lists/*
```

Contract: `FROM ghcr.io/clockwork-pilot/autopilot-ws:<tag>` (or ABI-compatible derivative), final `USER node`, tools on `node`'s `PATH`.

Hoist image prep into its own job and hand its tag to `coding-agent.yml`. Both jobs must land on the same self-hosted runner — local docker tags don't cross daemons.

```yaml
# your repo: .github/workflows/agent.yml
jobs:
  image:
    uses: clockwork-pilot/autopilot/.github/workflows/ensure-docker-image.yml@v1
    with:
      runner_label: ${{ github.actor }}
      base_image:   ghcr.io/clockwork-pilot/autopilot-ws:latest
      dockerfile:   Dockerfile.agent
      tag_prefix:   agent-img

  agent:
    needs: image
    uses: clockwork-pilot/autopilot/.github/workflows/coding-agent.yml@v1
    with:
      runner_label: ${{ github.actor }}
      issue_number: ${{ github.event.issue.number }}
      docker_image: ${{ needs.image.outputs.docker_image }}
```

`dockerfile:` is **optional** — set it only when you want custom packages on top of the base image. Omit it and `ensure-docker-image` pulls `base_image:` as-is. Override `base_image:` to point at a fork or pinned digest — it's the only built-in registry reference, change it once per caller and the rest follows. See [`autopilot-selftest`](https://github.com/Clockwork-Pilot/autopilot-selftest) for this shape dogfooded.

**Properties.** Build runs as root (apt/pip/`/usr/local/bin` writes work). Build context is the caller's checkout (`COPY pyproject.toml` etc. works). Caching: GHA layer cache on hosted runners (scoped by `tag_prefix`), local docker cache on self-hosted. Fast-path: if the content-hashed local tag exists, build is skipped. No registry required.

## Opening PRs against the upstream repo (optional)

Set `merge_into_upstream: true` in the issue frontmatter to open the PR against the parent repo instead of your fork.

The auto-minted `secrets.GITHUB_TOKEN` is scoped to the fork only — it cannot create PRs on a different repo regardless of declared `permissions:`, returning `Resource not accessible by integration`. So this flow needs a user-scoped PAT (`UPSTREAM_PR_TOKEN`) for the one cross-repo API call.

**Generate** the token. Pick by access level:

#### Option A — Classic PAT (typical: you are NOT a collaborator on upstream)

Acts with your full user identity (the same authority that creates a PR when you click in the browser). At <https://github.com/settings/tokens/new>:

| Field | Value |
|---|---|
| *Note* | e.g. `autopilot upstream PRs` |
| *Expiration* | 90 days |
| *Scopes* | `public_repo` (public upstream) or `repo` (private upstream) |

Generate, copy the `ghp_…` string.

#### Option B — Fine-grained PAT (only if you have write access on upstream)

`POST /repos/{upstream}/pulls` checks against the *upstream* repo, so `Pull requests: write` must be granted there — you cannot grant write on a repo where you lack write access. Selecting only the fork does **not** work. At <https://github.com/settings/personal-access-tokens/new>:

| Field | Value |
|---|---|
| *Token name* | e.g. `autopilot upstream PRs` |
| *Expiration* | 90 days |
| *Resource owner* | your user account |
| *Repository access* | *Only select repositories* → the **upstream** repo |
| *Repository permissions* → `Pull requests` | **Read and write** |
| *Repository permissions* → `Contents` | **Read-only** |

Generate, copy the `github_pat_…` string.

**Store as an environment secret** (not a repo secret — see safety model above). At `https://github.com/<you>/<fork>/settings/environments` → *New environment*:
- Name: `upstream-pr`.
- *Deployment branches* → *Selected branches* → add rule for `main` only. (Prevents a PR that edits the workflow from exfiltrating the token.)
- Inside the env → *Environment secrets* → *Add*: name `UPSTREAM_PR_TOKEN`, paste the token from step 1.

**Verify** by opening an issue with `merge_into_upstream: true`, applying `agent-run`, and checking that the PR shows up on upstream attributed to your user account.

If you lose the token before saving, regenerate. Classic PATs at <https://github.com/settings/tokens>, fine-grained at <https://github.com/settings/tokens?type=beta>.

**`merge_into_upstream` on private repos.** Use a classic PAT with `repo` (not `public_repo`) if either repo is private; or a fine-grained PAT with `Pull requests: write` on the private upstream (requires collaborator status there).
