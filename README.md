# openclaw-custom

Custom [OpenClaw](https://github.com/openclaw/openclaw) Docker image with extended skill dependencies.

Built automatically on top of official stable [OpenClaw releases](https://github.com/openclaw/openclaw/releases), adding commonly needed binaries that many OpenClaw skills require but aren't present in the minimal official image. Tracks only non-beta releases (e.g., `2026.3.8`), never `:main`.

## What's Added

| Package / Tool | Purpose |
|----------------|---------|
| git | Version control (GitHub skills, repo operations) |
| gh | GitHub CLI (issue/PR management skills) |
| python3 + pip + venv | Python runtime (image gen, data processing skills) |
| uv | Fast Python package manager (Gemini image gen, others) |
| jq | JSON processing (API response handling skills) |
| curl | HTTP requests (web interaction skills) |
| ripgrep | Fast code search (code analysis skills) |
| ffmpeg | Media processing (audio/video conversion skills) |
| openssh-client | SSH access (remote operations) |
| procps | Process utilities (`ps`, `pkill` — used by cron helper) |
| VS Code CLI | VS Code tunnel for remote editing (`code tunnel`) |
| [Supercronic](https://github.com/aptible/supercronic) | Cron scheduler for containers (version fetched dynamically at build time) |
| [Claude Code](https://github.com/anthropics/claude-code) | `claude` CLI for the `claude-cli` backend — login with a Pro/Max subscription (version fetched dynamically at build time) |

## Startup Services

The custom entrypoint (`start-tunnel.sh`) launches two background services before handing off to the original OpenClaw entrypoint:

1. **VS Code Tunnel** — Starts `code tunnel` in the background, logging to `/home/node/openclaw-data/vscode-tunnel.log`.
2. **Supercronic Scheduler** — Reads a crontab from `/home/node/.openclaw/workspace/crontab`. If the file exists and is non-empty, `supercronic` runs in the background. Logs go to `/home/node/.openclaw/workspace/supercronic.log`.

### Crontab Usage

A placeholder crontab is created at build time. To schedule tasks, edit the file inside the running container or mount your own:

```
# /home/node/.openclaw/workspace/crontab
*/5 * * * * /usr/local/bin/python3 /home/node/.openclaw/workspace/my_script.py >> /home/node/.openclaw/workspace/my_script.log 2>&1
```

## Persisting Claude Code login

The `claude` binary is **baked into the image**, so it survives container restarts and image upgrades automatically — CI reinstalls the latest stable version on every rebuild. The binary lands at `/usr/local/bin/claude` (on `PATH`), so OpenClaw auto-detects it as the `claude-cli` backend.

Your **login is separate** and must be persisted on a volume, or you'll have to re-authenticate every time the container is recreated. Claude Code stores its OAuth token in `~/.claude` (`/home/node/.claude`). Mount a named volume there:

```yaml
services:
  openclaw:
    image: ghcr.io/bostonvip/openclaw-custom:latest
    volumes:
      - claude-creds:/home/node/.claude   # persists the login/OAuth token
      # ... your other volumes

volumes:
  claude-creds:
```

Then log in **once** from inside the running container:

```bash
docker exec -it openclaw claude   # follow the OAuth prompt, choose your Pro/Max plan
```

The token is written to `/home/node/.claude/.credentials.json` on the volume and reused across restarts and upgrades.

> If `claude` is somehow not picked up automatically, point OpenClaw at it explicitly:
> set `agents.defaults.cliBackends.claude-cli.command` to `/usr/local/bin/claude`.

### Pinning the Claude Code version

By default CI installs the latest stable release. To pin (e.g. for rollback), override the build-arg locally or trigger a build with the Dockerfile `ARG CLAUDE_CODE_VERSION` set to a specific version:

```bash
docker build --build-arg CLAUDE_CODE_VERSION=1.2.3 -t openclaw-custom .
```

## Usage

### Pull the image

```bash
docker pull ghcr.io/bostonvip/openclaw-custom:latest
```

### Use in Docker Compose (Portainer)

```yaml
services:
  openclaw:
    image: ghcr.io/bostonvip/openclaw-custom:latest
    # ... rest of your config
```

### Pin to a specific OpenClaw version

```bash
docker pull ghcr.io/bostonvip/openclaw-custom:2026.3.8
```

## Build Schedule

- **Automatic:** Checks daily at 06:00 UTC for new stable OpenClaw releases via the GitHub API. Only rebuilds when a new version is published (e.g., `2026.3.7` → `2026.3.8`). Pre-releases and betas are ignored.
- **On Dockerfile change:** Rebuilds when the Dockerfile is updated on `main`.
- **On demand:** Trigger manually from the Actions tab with optional force rebuild or version override (e.g., pin to `2026.3.7` for rollback).

### Dynamic Versioning

Both the OpenClaw base image version and the Supercronic version are resolved dynamically at CI/CD time by querying the GitHub Releases API. No hardcoded versions in the workflow — the Dockerfile `ARG` defaults serve only as fallbacks for local builds.

## Image Labels

Each built image includes OCI labels for traceability:

| Label | Description |
|-------|-------------|
| `org.openclaw.base-version` | OpenClaw upstream version used |
| `org.openclaw.build-reason` | Why the build was triggered |
| `org.openclaw.build-date` | Timestamp of the CI run |
| `org.openclaw.supercronic-version` | Supercronic version installed |
| `org.openclaw.claude-code-version` | Claude Code CLI version installed |
| `org.openclaw.includes-vscode-tunnel` | Whether VS Code tunnel is enabled |
| `org.openclaw.includes-cron` | Whether cron scheduling is enabled |
| `org.openclaw.baked-entrypoint` | Original entrypoint from the base image |
| `org.openclaw.baked-cmd` | Original CMD from the base image |

## Updating in Docker

```bash
docker pull ghcr.io/bostonvip/openclaw-custom:latest
docker restart openclaw
```

## Security

- All packages installed from official Debian and GitHub repositories
- Runs as non-root user (UID 1000)
- No secrets or credentials in the image
- Build is transparent via GitHub Actions logs

## Customizing

Edit the `Dockerfile` to add or remove packages. The workflow will automatically rebuild on push to `main`.

To remove packages you don't need (e.g., `ffmpeg` saves ~100MB), simply delete the line from the `apt-get install` block.
