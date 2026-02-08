# openclaw-custom

Custom [OpenClaw](https://github.com/openclaw/openclaw) Docker image with extended skill dependencies.

Built automatically on top of the official `ghcr.io/openclaw/openclaw:main` image, adding commonly needed binaries that many OpenClaw skills require but aren't present in the minimal official image.

## What's Added

| Package | Purpose |
|---------|---------|
| git | Version control (GitHub skills, repo operations) |
| gh | GitHub CLI (issue/PR management skills) |
| python3 + pip + venv | Python runtime (image gen, data processing skills) |
| uv | Fast Python package manager (Gemini image gen, others) |
| jq | JSON processing (API response handling skills) |
| curl | HTTP requests (web interaction skills) |
| ripgrep | Fast code search (code analysis skills) |
| ffmpeg | Media processing (audio/video conversion skills) |

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

## Build Schedule

- **Automatic:** Checks daily at 06:00 UTC for updates to the official OpenClaw base image. Only rebuilds if the base image has changed.
- **On Dockerfile change:** Rebuilds when the Dockerfile is updated on `main`.
- **On demand:** Trigger manually from the Actions tab with optional force rebuild.

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
