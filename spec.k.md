# Specification

## Overview

Workflow structure constraints for .github/workflows

## Table of Contents

- [Overview](#overview)
- [Features](#features)
    - [Feature: coding_agent_steps](#feature-coding_agent_steps)
      - [dispatcher_fails_on_missing_step](#dispatcher_fails_on_missing_step)
    - [Feature: docker_environment](#feature-docker_environment)
      - [docker_required](#docker_required)
    - [Feature: step_output_checks](#feature-step_output_checks)
      - [choose_branch_via_action](#choose_branch_via_action)
      - [fixtures_colocated_with_actions](#fixtures_colocated_with_actions)
      - [no_legacy_centralized_fixtures](#no_legacy_centralized_fixtures)
      - [parse_digest_via_action](#parse_digest_via_action)
      - [parse_issue_via_action](#parse_issue_via_action)
    - [Feature: upstream_pr_isolation](#feature-upstream_pr_isolation)
      - [open_upstream_pr_job_shape](#open_upstream_pr_job_shape)
      - [run_agent_is_self_hosted](#run_agent_is_self_hosted)
      - [same_repo_pr_excludes_upstream_mode](#same_repo_pr_excludes_upstream_mode)
      - [upstream_environment_scoped_to_one_job](#upstream_environment_scoped_to_one_job)
      - [upstream_pr_token_scoped_to_one_job](#upstream_pr_token_scoped_to_one_job)
    - [Feature: workflow_hygiene](#feature-workflow_hygiene)
      - [actionlint_passes](#actionlint_passes)
      - [build_push_action_pinned_via_env](#build_push_action_pinned_via_env)
      - [checkout_pinned_via_env](#checkout_pinned_via_env)
      - [no_checkout_v4_in_workflows](#no_checkout_v4_in_workflows)
      - [no_hardcoded_base_image](#no_hardcoded_base_image)
      - [setup_buildx_action_pinned_via_env](#setup_buildx_action_pinned_via_env)

## Features

### Feature: coding_agent_steps
**Coding agent steps for workflow automation**

**Goals:**
- Entry point called identically by workflow and constraint

#### dispatcher_fails_on_missing_step
**Description:** Negative: act-step-dispatch.sh must exit non-zero AND emit the missing-step error to stderr (not stdout) when the requested step does not exist

### Feature: docker_environment
**Constraint checks must run inside Docker container**

**Goals:**
- Ensure constraint checker only runs in Docker environment, not on bare host

#### docker_required
**Description:** Verify constraints are running inside an existing Docker container (/.dockerenv present). We are already in Docker — do not nest another container layer.

### Feature: step_output_checks
**Behavioral checks: dispatch a workflow step with a fixture input and assert its $GITHUB_OUTPUT matches fixture.**

**Goals:**
- One behavioral constraint per dispatchable step, using mktemp -d for isolation

#### choose_branch_via_action
**Description:** Behavioral: choose-branch fixtures pass against the act-step-runner.yml wrapper. Replaces choose_branch_cases.

#### fixtures_colocated_with_actions
**Description:** Structural: each behaviorally tested composite action must own its fixtures under .github/actions/<step>/fixtures/. Co-locating fixtures next to action.yml/script.sh keeps them discoverable when modifying the action and prevents drift back to a centralized scripts/test tree.

#### no_legacy_centralized_fixtures
**Description:** Negative: the legacy .github/scripts/test/fixtures/ tree must not exist. Fixtures live under .github/actions/<step>/fixtures/; this guards against partial reverts that would split fixtures across two locations.

#### parse_digest_via_action
**Description:** Behavioral: parse-digest fixtures pass against the act-step-runner.yml wrapper. Replaces parse_digest_cases.

#### parse_issue_via_action
**Description:** Behavioral: parse-issue fixtures pass against the act-step-runner.yml wrapper which invokes .github/actions/parse-issue/script.sh. Replaces parse_issue_cases after refactor to composite action.

### Feature: upstream_pr_isolation
**Cross-repo PR creation is isolated from the self-hosted agent runner**

**Goals:**
- UPSTREAM_PR_TOKEN (PAT) is never available on the self-hosted runner where the agent executes code
- The upstream-pr environment and its secret are scoped to a single, minimal job

#### open_upstream_pr_job_shape
**Description:** Structural: open-upstream-pr must declare environment: upstream-pr, run on ubuntu-latest (never self-hosted), and gate its if: on BOTH has_new_commit and merge_into_upstream being 'true'.

#### run_agent_is_self_hosted
**Description:** Structural: run-agent must include the self-hosted label in runs-on. The agent executes untrusted code; running it on a shared ubuntu-latest runner would co-locate that code with other GitHub-hosted jobs and violate the isolation model the PAT scoping depends on.

#### same_repo_pr_excludes_upstream_mode
**Description:** Structural: any step outside the open-upstream-pr job that calls 'gh pr create' must be guarded by merge_into_upstream != 'true' in its if:. Prevents double-opening when upstream mode is active, regardless of which job hosts the fork-PR step.

#### upstream_environment_scoped_to_one_job
**Description:** Structural: exactly one job in coding-agent.yml may declare environment: upstream-pr. Adding the environment to the self-hosted agent job would re-expose the PAT.

#### upstream_pr_token_scoped_to_one_job
**Description:** Structural: secrets.UPSTREAM_PR_TOKEN must appear in exactly the open-upstream-pr job and no other. Keeps the PAT out of the self-hosted runner.

### Feature: workflow_hygiene
**Workflows use SHA-pinned actions**

**Goals:**
- All action references must be pinned to full commit SHAs for reproducibility and security

#### actionlint_passes
**Description:** Static: actionlint (https://github.com/rhysd/actionlint) must report zero issues across all .github/workflows/*.yml files. Catches typos in ${{ needs.<job> }} references, mismatched composite action inputs, invalid context usage, and other structural issues that yq-only checks miss.

#### build_push_action_pinned_via_env
**Description:** Security: every docker/build-push-action reference across .github/workflows/*.yml and .github/actions/**/*.yml must match $BUILD_PUSH_ACTION_VER (defined in project.k.json → specs.autopilot.envs). Single source of truth for the approved build-push-action pin; update there to rotate.

#### checkout_pinned_via_env
**Description:** Security: every actions/checkout reference in workflows must match $CHECKOUT_VER (defined in project.k.json → specs.autopilot.envs). Single source of truth for the approved checkout pin; update there to rotate.

#### no_checkout_v4_in_workflows
**Description:** Negative: no .github/workflows/*.yml file may reference actions/checkout@v4

#### no_hardcoded_base_image
**Description:** Architectural: the autopilot-ws image reference must not appear in any workflow yml file — not as a default, not in a comment, not anywhere. The image must be supplied purely via a workflow/action input (base_image) by the consumer caller, so autopilot itself has no built-in coupling to any specific ghcr/registry ref.

#### setup_buildx_action_pinned_via_env
**Description:** Security: every docker/setup-buildx-action reference across .github/workflows/*.yml and .github/actions/**/*.yml must match $SETUP_BUILDX_ACTION_VER (defined in project.k.json → specs.autopilot.envs). Single source of truth for the approved setup-buildx-action pin; update there to rotate.