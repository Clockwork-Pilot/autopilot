# Specification

## Overview

Workflow structure constraints for .github/workflows

## Table of Contents

- [Overview](#overview)
- [Features](#features)
    - [Feature: coding_agent_steps](#feature-coding_agent_steps)
      - [coding_agent_inputs_minimal](#coding_agent_inputs_minimal)
      - [dispatcher_fails_on_missing_step](#dispatcher_fails_on_missing_step)
    - [Feature: docker_environment](#feature-docker_environment)
      - [docker_required](#docker_required)
    - [Feature: runner_cancellation](#feature-runner_cancellation)
      - [docker_run_scripts_kill_container_on_cancel](#docker_run_scripts_kill_container_on_cancel)
    - [Feature: step_output_checks](#feature-step_output_checks)
      - [act_step_runner_choose_branch_job_uses_composite_action](#act_step_runner_choose_branch_job_uses_composite_action)
      - [act_step_runner_parse_issue_job_uses_composite_action](#act_step_runner_parse_issue_job_uses_composite_action)
      - [choose_branch_via_action](#choose_branch_via_action)
      - [composite_actions_yaml_loadable](#composite_actions_yaml_loadable)
      - [every_action_with_fixtures_has_negative_fixture](#every_action_with_fixtures_has_negative_fixture)
      - [no_legacy_centralized_fixtures](#no_legacy_centralized_fixtures)
      - [parse_issue_via_action](#parse_issue_via_action)
    - [Feature: upstream_pr_isolation](#feature-upstream_pr_isolation)
      - [open_upstream_pr_job_shape](#open_upstream_pr_job_shape)
      - [run_agent_is_self_hosted](#run_agent_is_self_hosted)
      - [same_repo_pr_excludes_upstream_mode](#same_repo_pr_excludes_upstream_mode)
      - [upstream_environment_scoped_to_one_job](#upstream_environment_scoped_to_one_job)
      - [upstream_pr_token_scoped_to_one_job](#upstream_pr_token_scoped_to_one_job)
    - [Feature: workflow_hygiene](#feature-workflow_hygiene)
      - [act_step_runner_relocated_out_of_workflows_dir](#act_step_runner_relocated_out_of_workflows_dir)
      - [actionlint_config_in_test_workflows_dir](#actionlint_config_in_test_workflows_dir)
      - [actionlint_passes](#actionlint_passes)
      - [build_push_action_pinned_via_env](#build_push_action_pinned_via_env)
      - [checkout_pinned_via_env](#checkout_pinned_via_env)
      - [ensure_docker_image_uses_tag_prefix_not_tag](#ensure_docker_image_uses_tag_prefix_not_tag)
      - [no_checkout_v4_in_workflows](#no_checkout_v4_in_workflows)
      - [no_hardcoded_base_image](#no_hardcoded_base_image)
      - [no_scripts_path_in_workflow_run_steps](#no_scripts_path_in_workflow_run_steps)
      - [setup_buildx_action_pinned_via_env](#setup_buildx_action_pinned_via_env)

## Features

### Feature: coding_agent_steps
**Coding agent steps for workflow automation**

**Goals:**
- Entry point called identically by workflow and constraint

#### coding_agent_inputs_minimal
**Description:** Architectural: coding-agent.yml workflow_call.inputs must equal exactly {runner_label, issue_number, docker_image, extra_docker_args}, with docker_image required. Locks in the post-cleanup interface and forbids the legacy internal-prep inputs (base_image, agent_image, dockerfile, build_args, tag_prefix) — callers must hoist image preparation via ensure-docker-image.yml.

#### dispatcher_fails_on_missing_step
**Description:** Negative: act-step-dispatch.sh must exit non-zero AND emit the missing-step error to stderr (not stdout) when the requested step does not exist

### Feature: docker_environment
**Constraint checks must run inside Docker container**

**Goals:**
- Ensure constraint checker only runs in Docker environment, not on bare host

#### docker_required
**Description:** Verify constraints are running inside an existing Docker container (/.dockerenv present). We are already in Docker — do not nest another container layer.

### Feature: runner_cancellation
**Self-hosted runner must propagate GitHub workflow cancellation into the docker container, not orphan it.**

**Goals:**
- When GitHub cancels a workflow, the in-flight docker container must be killed, not left running.
- Without this, `docker run --rm` orphans the container — the daemon keeps it alive after the runner step is killed, so the agent finishes its turn anyway and consumes credits/produces side effects on a cancelled run.

#### docker_run_scripts_kill_container_on_cancel
**Description:** Both run-in-docker-*.sh scripts must capture the container id via `docker run --cidfile <file>` and install a `trap '... docker kill ...' EXIT INT TERM` so GitHub workflow cancellation actually stops the container. Without --cidfile + trap, `docker run --rm` orphans the container: the docker daemon keeps it running after the runner step is killed, the agent finishes its turn anyway, and the cancelled run still consumes credits and writes side effects.

### Feature: step_output_checks
**Behavioral checks: dispatch a workflow step with a fixture input and assert its $GITHUB_OUTPUT matches fixture.**

**Goals:**
- One behavioral constraint per dispatchable step, using mktemp -d for isolation

#### act_step_runner_choose_branch_job_uses_composite_action
**Description:** Architectural: the choose-branch test job in act-step-runner.yml (relocated to .github/scripts/test/workflows/) must invoke the composite action via uses: ./.github/actions/choose-branch. Same gate as act_step_runner_parse_issue_job_uses_composite_action — keeps the harness exercising action.yml metadata. Strict equivalent of the legacy choose_branch_test_uses_composite_action constraint, updated for the new file location.

#### act_step_runner_parse_issue_job_uses_composite_action
**Description:** Architectural: the parse-issue test job in act-step-runner.yml (relocated to .github/scripts/test/workflows/) must invoke the composite action via uses: ./.github/actions/parse-issue, not by open-coding run: bash .github/actions/parse-issue/script.sh. Forces every test run to load action.yml so malformed metadata fails the suite. Strict equivalent of the legacy parse_issue_test_uses_composite_action constraint, updated for the new file location.

#### choose_branch_via_action
**Description:** Behavioral: choose-branch fixtures pass against the act-step-runner.yml wrapper. Replaces choose_branch_cases.

#### composite_actions_yaml_loadable
**Description:** Static: every .github/actions/*/action.yml must parse as valid YAML. Catches malformed flow-mapping descriptions, unclosed quotes, and similar metadata breaks that the behavioral fixture harness would miss when it bypasses action.yml.

#### every_action_with_fixtures_has_negative_fixture
**Description:** Meta: every .github/actions/<name>/fixtures/ tree must contain at least one negative-*/ case. Generalizes parse_issue_has_negative_fixture and choose_branch_has_negative_fixture: any action with positive fixtures must also carry a live demonstration that the harness diff fires on mismatch. Future actions added with fixtures will be covered automatically.

#### no_legacy_centralized_fixtures
**Description:** Negative: the legacy .github/scripts/test/fixtures/ tree must not exist. Fixtures live under .github/actions/<step>/fixtures/; this guards against partial reverts that would split fixtures across two locations.

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

#### act_step_runner_relocated_out_of_workflows_dir
**Description:** Architectural: act-step-runner.yml is a local act test harness, never triggered by GitHub. It must live under .github/scripts/test/workflows/ (not .github/workflows/) so GitHub does not register it as a real reusable workflow exposed to consumers, and so it is exempt from no_scripts_path_in_reusable_workflows (the dispatcher script lives next to it).

#### actionlint_config_in_test_workflows_dir
**Description:** Architectural: actionlint.yaml must live next to the relocated act-step-runner.yml at .github/scripts/test/workflows/, not at .github/. Its only ignore-rules block targets the test harness file, so the config belongs with the file it scopes — and keeping it out of .github/ avoids implying that the project ships an actionlint config for consumer-facing workflows.

#### actionlint_passes
**Description:** Static: actionlint (https://github.com/rhysd/actionlint) must report zero issues across all .github/workflows/*.yml files. Catches typos in ${{ needs.<job> }} references, mismatched composite action inputs, invalid context usage, and other structural issues that yq-only checks miss.

#### build_push_action_pinned_via_env
**Description:** Security: every docker/build-push-action reference across .github/workflows/*.yml and .github/actions/**/*.yml must match $BUILD_PUSH_ACTION_VER (defined in project.k.json → specs.autopilot.envs). Single source of truth for the approved build-push-action pin; update there to rotate.

#### checkout_pinned_via_env
**Description:** Security: every actions/checkout reference in workflows must match $CHECKOUT_VER (defined in project.k.json → specs.autopilot.envs). Single source of truth for the approved checkout pin; update there to rotate.

#### ensure_docker_image_uses_tag_prefix_not_tag
**Description:** ensure-docker-image.yml workflow_call.inputs must include tag_prefix and must not include tag.

#### no_checkout_v4_in_workflows
**Description:** Negative: no .github/workflows/*.yml file may reference actions/checkout@v4

#### no_hardcoded_base_image
**Description:** Architectural: the autopilot-ws image reference must not appear in any workflow yml file — not as a default, not in a comment, not anywhere. The image must be supplied purely via a workflow/action input (base_image) by the consumer caller, so autopilot itself has no built-in coupling to any specific ghcr/registry ref.

#### no_scripts_path_in_workflow_run_steps
**Description:** Negative: no `run:` step in any .github/workflows/*.yml may shell out to a `.github/scripts/...` path. The rule is not reusable-vs-not — it is about whose checkout sits at $GITHUB_WORKSPACE when `run:` executes. When a consumer invokes one of these workflows, actions/checkout pulls the consumer's repo into $GITHUB_WORKSPACE, so a relative `.github/scripts/foo.sh` resolves against the consumer's tree and fails with 'No such file or directory'. Scripts that need autopilot's own checkout must be invoked from composite actions under .github/actions/, where $GITHUB_ACTION_PATH points at the autopilot tree (e.g. `bash "$GITHUB_ACTION_PATH/../../scripts/foo.sh"`); composite actions are exempt and the regex does not match $GITHUB_ACTION_PATH usage. Past incident: coding-agent.yml's Agent commit step ran `bash .github/scripts/run-in-docker-claude.sh` and broke every consumer run.

#### setup_buildx_action_pinned_via_env
**Description:** Security: every docker/setup-buildx-action reference across .github/workflows/*.yml and .github/actions/**/*.yml must match $SETUP_BUILDX_ACTION_VER (defined in project.k.json → specs.autopilot.envs). Single source of truth for the approved setup-buildx-action pin; update there to rotate.