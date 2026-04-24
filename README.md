# autopilot

Issue-driven coding agent orchestration: GitHub Actions workflows, composite actions, and the ansible playbook for the self-hosted runner. Pairs with the `-ws` workspace repo that provides the Docker image where the agent runs.

## Contents

- [Issue-driven coding agent (self-hosted runner)](#issue-driven-coding-agent-self-hosted-runner)
- [Private repositories](#private-repositories)
- [Runner PAT setup](#runner-pat-setup)
  - [Why this needs a PAT, not `GITHUB_TOKEN`](#why-this-needs-a-pat-not-github_token)
  - [One-time setup](#one-time-setup)
- [Installing extra dependencies](#installing-extra-dependencies)
  - [Write a Dockerfile](#write-a-dockerfile)
  - [Use it from the caller workflow](#use-it-from-the-caller-workflow)
  - [Properties](#properties)
  - [When to publish to a registry instead](#when-to-publish-to-a-registry-instead)
- [Opening PRs against the upstream repo (optional)](#opening-prs-against-the-upstream-repo-optional)
  - [Why a token is needed here but not in the browser](#why-a-token-is-needed-here-but-not-in-the-browser)
  - [One-time setup](#one-time-setup-1)
  - [Why an environment (not a repo secret)?](#why-an-environment-not-a-repo-secret)

# Issue-driven coding agent (self-hosted runner)

You can wire your fork so that applying an `agent-run` label to any GitHub issue kicks off the coding agent against a dedicated branch, opens a PR, and posts a constraints report back as an issue comment.

Flow overview:

1. **Pick a target repo** you own (a fork or a greenfield repo — both work). The agent flow, label triggers, PR creation, and constraints-driven contract are all repo-agnostic; only `spec.k.json` and the `features_and_constraints` skill tie a repo into the constraint-driven loop, and both are opt-in. Copy the workflow files (`.github/workflows/coding-agent.yml`, `issue-trigger.yml`, and optionally `check-constraints.yml`) into the target repo and pass `-e runner_repo=<github-username>/<your-repo>` when running the ansible playbook.
2. **Install a local self-hosted runner** against your fork — see [`ansible/README.md`](ansible/README.md) for the one-command ansible playbook. The runner registers with your GitHub login as a label.
3. **Perform one-time Docker setup** before running workflows — manually execute `./run-docker-workspace.sh` locally with your `PROJECT_ROOT` set to initialize the Docker environment. This one-time setup ensures that when workflows execute on the self-hosted runner, the Docker container is already properly configured and ready to work.
4. **Open an issue** in your fork describing the feature you want added. The agent follows the `features_and_constraints` skill: it patches `spec.k.json` with a new feature whose constraints check added feature; verifies each constraint first FAILS on the current code (Zero-State Rule); then implements code until every constraint PASSES via `check_spec_constraints.py`. Optionally prefix the body with YAML frontmatter:
   ```
   ---
   timeout: 20                  # optional, minutes, default 10
   model: claude-opus-4-6       # optional, default claude-haiku-4-5
   merge_into_upstream: false   # optional, default false — see note below
   ---
   <describe feature and its constraints>
   ```

   `merge_into_upstream`: when `false` (default) the agent opens a PR inside your fork; when `true` it opens a PR against the upstream (parent) repo instead. To use `true` you need:
   - a **Personal Access Token** on your user account — *classic PAT* with `public_repo` scope if you are **not** a collaborator on upstream (the typical fork contributor case), or *fine-grained PAT* with `Pull requests: write` on the upstream repo if you are a collaborator there;
   - a GitHub **environment** named `upstream-pr` in your fork (created at `https://github.com/<you>/<fork>/settings/environments`), restricted to the `main` deployment branch;
   - the PAT stored as environment secret **`UPSTREAM_PR_TOKEN`** inside that environment (not as a repo-level secret).

   Step-by-step walkthrough (including why classic vs fine-grained): see [Opening PRs against the upstream repo](#opening-prs-against-the-upstream-repo-optional) below.
   See `claude-plugin/skills/features_and_constraints/SKILL.md` for the full contract (ConstraintBash schema, `$PROJECT_ROOT`, Exit-Code Rule, Zero-State Rule, unverified-constraint blocking).

   **Note:** feature constraints are executable checks, not docstrings — they are the only thing standing between the agent and a lazy implementation. Write them to probe real payloads, exit codes, and side effects so they cannot be satisfied by stubs, hardcoded fixtures, or `echo "success"`. A constraint that the agent can shortcut is worse than no constraint: it gives false confidence. Design each one to make cheating harder than actually implementing the feature.
5. **Click the `agent-run` label** on the issue. `issue-trigger.yml` removes the label (so it's re-triggerable), verifies an online runner is labeled with your username, and dispatches `coding-agent.yml`.
6. The runner checks out your fork in isolation, runs Claude against the issue in a docker container, and — on success — asks Claude to commit, runs constraint checks, pushes an `agent/<issue>-<slug>` branch, opens a PR `[AGENT] <issue title>`, and comments the constraints report on the issue.
7. Re-applying the label on the same issue resumes the existing agent branch rather than starting over.

## Private repositories

Autopilot is designed for private repos on self-hosted runners — that is the recommended deployment shape. The public-fork walkthrough above works identically; only a few points are worth calling out for a private setup.

**What runs where.** `coding-agent.yml` splits jobs by `runs-on`:
- The agent execution jobs (the ones that actually run Claude inside the workspace container) land on `[self-hosted, <runner_label>]` — your runner, your hardware, your minutes.
- Orchestration jobs (checkout, parse-issue, choose-branch, open-pr, comment-agent-result) run on `ubuntu-latest` and consume GitHub-hosted Actions minutes. A private repo on a Free/Team plan has a monthly minutes budget; orchestration is cheap (seconds per job) but not free. Enterprise plans with unlimited private minutes or a dedicated larger runner make this a non-issue.

**`runner_label` routing.** `issue-trigger.yml` sets `runner_label = github.event.sender.login`, so the agent lands on a self-hosted runner whose label matches the GitHub username of whoever applied the `agent-run` label. Register one runner per user who should be allowed to trigger runs, each labeled with that user's login (case-sensitive). The preflight step in `issue-trigger.yml` uses `RUNNERS_PAT` to verify an online runner with that label exists, and fails fast with a clear message if not — see [Runner PAT setup](#runner-pat-setup).

**Self-hosted runners and private vs. public repos.** GitHub explicitly recommends against self-hosted runners on **public** repos, because a fork's PR can execute arbitrary code on your runner. On **private** repos this risk disappears — only collaborators can push branches or open PRs, so self-hosted is the intended configuration and no warning applies.

**Actions permissions.** Private-repo workflows need `Settings → Actions → General` to allow running workflows (default on) and, for the issue-label → dispatch chain, the default `GITHUB_TOKEN` permissions must be at least read/write for contents and pull-requests. `workflow_dispatch` between workflows in the same repo works without extra configuration.

**Checkout of private sources.** `actions/checkout` uses the auto-minted `GITHUB_TOKEN`, which has access to the private repo by default — nothing extra to configure for the agent's own checkout. If your agent needs to clone *other* private repos (dependencies, vendored tooling), add the credential handling to your custom Dockerfile (see [Installing extra dependencies](#installing-extra-dependencies)) or mount a git credential helper inside the container.

**`merge_into_upstream` on private repos.** The upstream PR flow still works across private repos, but the PAT scope depends on both repos being visible to the token: use a classic PAT with `repo` scope (not `public_repo`) if either the fork or upstream is private, or a fine-grained PAT with `Pull requests: write` on the private upstream (requires you to be a collaborator there). See [Opening PRs against the upstream repo](#opening-prs-against-the-upstream-repo-optional).

## Runner PAT setup

`issue-trigger.yml` needs to confirm an online self-hosted runner exists for the user who applied the label — before dispatching `coding-agent.yml`. This is what lets the workflow post a clear "no runner found for **@you**" comment on the issue instead of queuing a job that silently waits forever for a runner that isn't there. That check calls `GET /repos/{repo}/actions/runners`.

### Why this needs a PAT, not `GITHUB_TOKEN`

GitHub's permission model puts the self-hosted runner listing endpoint under the `Administration` permission — the same umbrella as renaming the repo or editing branch protection. The naming is unfortunate, but the scope granted here is narrow: **`Administration: Read-only`** on a fine-grained PAT allows reading repo metadata and runner registrations, and nothing write-side. It does not allow deleting the repo, changing settings, or modifying runners.

The auto-minted `GITHUB_TOKEN` cannot be elevated to this permission from inside a workflow (`permissions:` only exposes a subset of scopes, and `administration` isn't one of them), so this one API call has to go through a user-issued PAT. The PAT is stored as the **`RUNNERS_PAT`** repo secret and is used only by the runner-check step.

If `RUNNERS_PAT` is missing, the workflow fails fast with a pointer to this section rather than masquerading as "no runner found".

### One-time setup

1. Open <https://github.com/settings/personal-access-tokens/new> and fill in:

   | Field | Value |
   |---|---|
   | *Token name* | e.g. `autopilot runner lookup` |
   | *Expiration* | 90 days (shortest practical — calendar the rotation) |
   | *Resource owner* | your user account |
   | *Repository access* | *Only select repositories* → pick **only** the fork that runs the workflow |
   | *Repository permissions* → `Administration` | **Read-only** |

   Leave every other permission at *No access*. Click **Generate token** and copy the `github_pat_…` string — GitHub shows it once.

2. Store the copied value as a repo secret in your fork:

   1. Navigate to `https://github.com/<you>/<fork>` in your browser.
   2. Click the **Settings** tab (top-right of the repo header — requires admin access on the repo, which you have as the fork owner).
   3. In the left-hand sidebar, expand **Secrets and variables** and click **Actions**. You'll land on the *Actions secrets and variables* page, on the *Secrets* tab.
   4. Make sure you're on the *Repository secrets* section (not *Environment secrets* or *Organization secrets*) and click the green **New repository secret** button on the right.
   5. In the *Name* field, enter exactly `RUNNERS_PAT` — case-sensitive, no spaces, no leading/trailing whitespace. This must match the secret name referenced in `.github/workflows/issue-trigger.yml`.
   6. In the *Secret* field, paste the `github_pat_…` string you copied in step 1. Paste only the token itself — no quotes, no `Bearer ` prefix, no surrounding whitespace.
   7. Click **Add secret**. The page reloads and `RUNNERS_PAT` now appears in the *Repository secrets* list. GitHub does not show the value back to you; if you lose it, you'll have to regenerate the PAT and update the secret.

3. Verify the wiring end-to-end by opening a test issue in your fork and applying the `agent-run` label. The *Issue Trigger* workflow should advance past the "Ensure RUNNERS_PAT is configured" step; if it fails there, the secret is missing, misnamed, or empty. If it fails at "Check runner exists for actor" with a `403` or `Resource not accessible`, the PAT is set but lacks `Administration: Read-only` — regenerate it with the correct permission.

4. Calendar the expiration. A fine-grained PAT with a 90-day expiry stops working silently on day 91 — the workflow will start failing at the ensure-step again. When you rotate, repeat steps 1 and 2 (edit the existing `RUNNERS_PAT` secret rather than creating a new one, so the name stays stable).

The resulting token is scoped to one repo, read-only, and touches one endpoint — strictly less power than the classic `repo` scope most GitHub tutorials reach for.

## Installing extra dependencies

The agent runs inside `ghcr.io/clockwork-pilot/autopilot-ws`, which ships a general-purpose toolchain. If your repo needs packages that aren't in the base image (e.g. `ffmpeg`, a specific Python/Rust version, a vendored CLI), add a Dockerfile to your fork and pass its path to the agent workflow. Image preparation (pull or build, cache, tag) is handled by the [`ensure-docker-image`](.github/actions/ensure-docker-image/README.md) composite action — a generic Buildx wrapper with unified caching for GitHub-hosted and self-hosted runners.

### Write a Dockerfile

```dockerfile
# your fork: Dockerfile.agent
FROM ghcr.io/clockwork-pilot/autopilot-ws:latest
USER 0
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg libsndfile1 \
    && rm -rf /var/lib/apt/lists/*
USER node
```

The Dockerfile must satisfy the `autopilot-ws` runtime contract:
- `FROM ghcr.io/clockwork-pilot/autopilot-ws:<tag>` (or an ABI-compatible derivative).
- Final `USER node`.
- Tools on `node`'s `PATH`.

### Use it from the caller workflow

Two shapes, pick whichever fits:

**Inline (simple):** pass `dockerfile:` to `coding-agent.yml` directly; image preparation runs inside its `prepare-image` job.

```yaml
# your fork: .github/workflows/agent.yml
jobs:
  agent:
    uses: clockwork-pilot/autopilot/.github/workflows/coding-agent.yml@v1
    with:
      runner_label:     ${{ github.actor }}
      issue_number:     ${{ github.event.issue.number }}
      dockerfile:       Dockerfile.agent
      cache_key_prefix: ${{ github.repository }}-agent-img
```

**Hoisted (visible image job):** call `ensure-docker-image.yml` first, hand its output to `coding-agent.yml` via `docker_image:`. Preferred when you want the image-prep cache hit/miss visible at the caller level, or when you want to insert consumer-owned steps around it. Both jobs must land on the same self-hosted runner (single runner per `runner_label` — the default single-user setup).

```yaml
jobs:
  image:
    uses: clockwork-pilot/autopilot/.github/workflows/ensure-docker-image.yml@v1
    with:
      runner_label:     ${{ github.actor }}
      base_image:       ghcr.io/clockwork-pilot/autopilot-ws:latest
      dockerfile:       Dockerfile.agent
      tag:              autopilot-agent
      cache_key_prefix: ${{ github.repository }}-agent-img

  agent:
    needs: image
    uses: clockwork-pilot/autopilot/.github/workflows/coding-agent.yml@v1
    with:
      runner_label: ${{ github.actor }}
      issue_number: ${{ github.event.issue.number }}
      docker_image: ${{ needs.image.outputs.docker_image }}
```

See `autopilot-selftest` for both shapes dogfooded against this repo.

### Overriding the base image

Both reusable workflows accept a `base_image:` input (default `ghcr.io/clockwork-pilot/autopilot-ws:latest`). Set it when you want to point at a fork, a private mirror, or a pinned digest:

```yaml
uses: clockwork-pilot/autopilot/.github/workflows/coding-agent.yml@v1
with:
  base_image:       ghcr.io/your-org/autopilot-ws-mirror:v1.2.3
  dockerfile:       Dockerfile.agent
  cache_key_prefix: ${{ github.repository }}-agent-img
  ...
```

`base_image` is used both as the FROM contract when a Dockerfile is supplied, and as the image that gets pulled when no Dockerfile is supplied. The only built-in reference to `ghcr.io/clockwork-pilot/autopilot-ws` lives in this input's default — change it once per caller and the whole pipeline follows.

### Properties

- **Runs as root** at image-build time — `apt-get`, `pip install` system-wide, `/usr/local/bin` writes all work.
- **Build context** is the caller's checkout, so `COPY` from `pyproject.toml` / `package.json` works if you need dep manifests at build time.
- **Caching** is unified:
  - GitHub-hosted: Buildx GHA layer cache (`type=gha`), scoped by `cache_key_prefix`.
  - Self-hosted: docker daemon's local layer cache (persistent).
  - Fast-path: if the content-hashed local tag already exists, build is skipped entirely.
- **No registry required** in either shape — images live as local docker tags on the self-hosted runner. See [`ensure-docker-image/README.md`](.github/actions/ensure-docker-image/README.md) for cache-key guidelines.

### When to publish to a registry instead

If you want an image shared across many repos, pinned by digest, or available to pooled/ephemeral self-hosted runners, build and push to your own registry. [`templates/user-image/`](templates/user-image/) has a ready-to-copy `Dockerfile` and `build-and-push.yml` workflow that pushes to `ghcr.io/<you>/autopilot-ws-custom:latest`. Then in the caller set `agent_image:` (instead of `dockerfile:`) to the pushed ref; `coding-agent.yml` will pull it instead of building. Private images need a `docker login ghcr.io` step in the caller before the `uses:` line, or make the package public.

## Opening PRs against the upstream repo (optional)

By default the agent opens a PR inside your fork. To have it open a PR against the upstream (parent) repo instead, set `merge_into_upstream: true` in the issue frontmatter.

### Why a token is needed here but not in the browser

When *you* click "Create pull request" in the GitHub web UI, the request goes out as **your user account** — an identity that, by default, can open a PR from any fork you push to against any public upstream repo. You never think about a token because the browser session is your token.

A GitHub Actions workflow runs as a **different identity**. The auto-minted `secrets.GITHUB_TOKEN` is an installation token for the GitHub Actions GitHub App, issued as `github-actions[bot]` and scoped to exactly one repository — the repo where the workflow is defined (your fork). It has no presence on the upstream repo and cannot create PRs there, no matter what `permissions:` the workflow declares. That is why a same-repo PR works out of the box, and a cross-repo PR returns `Resource not accessible by integration (createPullRequest)`.

A Personal Access Token stored as `UPSTREAM_PR_TOKEN` solves this by giving the workflow a **user-scoped** identity for the one API call that needs it. The PAT acts as you, so the resulting PR is attributed to your user account — the same outcome as clicking the button in the UI, just initiated from CI.

Two PAT flavors exist — **classic** and **fine-grained** — and the choice is not cosmetic:
- **Classic PAT** (with `public_repo` or `repo` scope) acts with your full user permissions. Any authenticated user can open a PR from their fork to a public upstream, so a classic PAT works even when you have no write access on upstream. This is the right pick for the typical "contributor on a fork" case.
- **Fine-grained PAT** is repo-scoped and requires `Pull requests: write` on the *target* repo (upstream). GitHub's creation form only lets you grant write permissions on repos where you already have write access, so a fine-grained PAT only works if you are a collaborator/maintainer on upstream. Selecting just the fork is **not** enough — the `POST /repos/{upstream}/pulls` check runs against the upstream repo.

### One-time setup

`UPSTREAM_PR_TOKEN` is **the value of a Personal Access Token** that you generate on your user account. GitHub does not issue this token automatically — you create it in your user settings, copy the string, and paste it into your fork as an environment secret named `UPSTREAM_PR_TOKEN`. The three steps below do exactly that.

1. **Generate the token value** (this string will become `UPSTREAM_PR_TOKEN`).

   Pick the token type that matches your access level on upstream:

   #### Option A — Classic PAT (typical case: you are NOT a collaborator on upstream)

   This is the equivalent of what happens when you click "Create pull request" in the browser: the token carries your full user identity, and any authenticated user can open a PR from their fork to a public upstream. No upstream write access is required.

   Sign in as the user whose fork runs the workflow, then open <https://github.com/settings/tokens/new> and fill in:

   | Field | Value |
   |---|---|
   | *Note* | e.g. `autopilot upstream PRs` |
   | *Expiration* | 90 days (shortest practical — calendar the rotation) |
   | *Select scopes* | `public_repo` (if upstream is public) **or** `repo` (if upstream is private) |

   Click **Generate token**. GitHub shows the `ghp_…` string **once** — copy it now.

   #### Option B — Fine-grained PAT (only if you have write access on upstream)

   Tighter scope, but only usable when you are a collaborator/maintainer on upstream, because `POST /repos/{upstream}/pulls` checks the token's permissions against the upstream repo — not the fork — and you cannot grant `Pull requests: write` on a repo you don't already have write access to. Selecting only the fork does **not** work.

   Open <https://github.com/settings/personal-access-tokens/new> and fill in:

   | Field | Value |
   |---|---|
   | *Token name* | e.g. `autopilot upstream PRs` |
   | *Expiration* | 90 days |
   | *Resource owner* | your user account |
   | *Repository access* | *Only select repositories* → pick the **upstream** repo |
   | *Repository permissions* → `Pull requests` | **Read and write** |
   | *Repository permissions* → `Contents` | **Read-only** |

   Click **Generate token**. Copy the `github_pat_…` string — it's shown only once.

   The copied string (from A or B) is the value you will paste in step 3.

2. **Create a GitHub environment in your fork** at `https://github.com/<you>/<fork>/settings/environments` → *New environment*:
   - Name: `upstream-pr`.
   - *Deployment branches and tags* → *Selected branches and tags* → add rule for `main` only. This prevents a PR that edits the workflow file from exfiltrating the token.
   - (Optional) *Required reviewers*: add yourself if you want manual approval per run.

3. **Store the token as an environment secret** (scoped to `upstream-pr`, not as a repo-level secret):
   - Inside the `upstream-pr` environment → *Environment secrets* → *Add environment secret*.
   - *Name*: `UPSTREAM_PR_TOKEN` (exactly this — the workflow looks it up by name).
   - *Value*: paste the token string you copied in step 1 (`ghp_…` for a classic PAT, or `github_pat_…` for a fine-grained PAT).
   - Click *Add secret*.

4. **Verify**: open an issue in your fork with `merge_into_upstream: true` in the frontmatter, apply the `agent-run` label, and check that the resulting PR appears on the upstream repo, authored by your user account.

If you lose the token string before saving it in step 3, you cannot recover it — regenerate a new one (same form) and use the new value. Classic PATs can be revoked at <https://github.com/settings/tokens>; fine-grained PATs at <https://github.com/settings/tokens?type=beta>.

### Why an environment (not a repo secret)?

A repo-level secret is readable by every workflow and every branch in your fork — on a public fork, that is a soft credential-leak surface. An environment secret is loaded only into jobs that explicitly declare `environment: upstream-pr`, and the branch restriction ensures that a malicious PR editing the workflow file cannot reach the token. Only the tiny cross-repo-PR job opts into the environment, so the PAT never enters the self-hosted runner where the Claude agent executes.
