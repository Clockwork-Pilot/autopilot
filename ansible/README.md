# GitHub Actions Self-Hosted Runner

Ansible playbook to install a GitHub Actions self-hosted runner on your local machine, targeting any GitHub repo you own. The runner is registered at the repo level and runs as a systemd user service.

## Prerequisites

- Python deps: `pip install ansible yq`
- System deps: Docker (used by workflows) and `jq` (required by `yq` to parse issue frontmatter) — e.g. `sudo apt install docker.io jq`

## Usage

You work against any GitHub repo you own. Replace `<github-username>` with your GitHub login and `<your-repo>` with the target repo name.

1. Get a registration token for the target repo:
   ```
   https://github.com/<github-username>/<your-repo>/settings/actions/runners/new
   ```
   Copy the token from the `--token ...` line on that page.

2. Run the playbook:
   ```bash
   cd ansible
   ansible-playbook -i inventory.ini playbook.yml \
       -e runner_token=XXXXXXXXXXXXXXXXXXXXXXXXXXXXX \
       -e runner_repo=<github-username>/<your-repo> \
       -e runner_github_username=<github-username> \
       -e docker_files=/abs/path/to/docker-files
   ```

   All four `-e` vars are mandatory; the playbook aborts at its first task if any is missing.

## Configuration

Override any of these via `-e` or by editing `vars.yml`:

| Variable | Default | Description |
|---|---|---|
| `runner_repo` | **required** | GitHub repo the runner is registered to, e.g. `<github-username>/<your-repo>` |
| `runner_token` | **required** | One-shot registration token from the GitHub runner setup page |
| `docker_files` | **required** | Absolute host path for persistent dirs (cargo, claude credentials) mounted into the coding-agent container |
| `runner_github_username` | `git config user.username` | Must match the runner label that `issue-trigger.yml` checks for |
| `runner_name` | hostname | Runner name shown in GitHub UI |
| `runner_labels` | `coding-agent,<username>` | Labels used in `runs-on` |
| `runner_install_dir` | `~/.local/share/github-runner` | Install path |
| `runner_version` | `2.333.1` | Runner binary version |
| `claude_extra_docker_args` | `""` | Extra `docker run` args, e.g. `"-v /mydata:/mydata"` |

## Service management

Replace `<user>.<repo>` with your runner's `{runner_repo | replace('/', '.')}`:

```bash
# Status
systemctl --user status 'actions.runner.<user>.<repo>.*'

# Stop / start
systemctl --user stop   'actions.runner.<user>.<repo>.*'
systemctl --user start  'actions.runner.<user>.<repo>.*'

# Logs
journalctl --user -u 'actions.runner.<user>.<repo>.*' -f
```

## Using the runner in a workflow

```yaml
jobs:
  my-job:
    runs-on: [self-hosted, coding-agent]
```
