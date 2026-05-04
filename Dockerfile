# Custom OpenClaw image with extended skill dependencies
# Extends the official image with commonly needed binaries
ARG OPENCLAW_VERSION=2026.3.8
FROM ghcr.io/openclaw/openclaw:${OPENCLAW_VERSION}

USER root

# Add GitHub CLI repository
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list

# Install system packages
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      git \
      gh \
      python3 \
      python3-pip \
      python3-venv \
      jq \
      curl \
      ripgrep \
      ffmpeg \
      openssh-client \
      procps \
      build-essential \
      unzip \
      zip \
      sqlite3 \      
    && rm -rf /var/lib/apt/lists/*

# Install uv (fast Python package manager — used by Gemini image gen and other skills)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    mv /root/.local/bin/uv /usr/local/bin/uv && \
    mv /root/.local/bin/uvx /usr/local/bin/uvx

# Install VS Code CLI — provides the 'code' binary used for the tunnel and 'code .'
# Architecture-aware: picks arm64, armhf, or x64 automatically
RUN ARCH=$(dpkg --print-architecture) && \
    if   [ "$ARCH" = "arm64" ]; then VSCODE_ARCH="cli-linux-arm64"; \
    elif [ "$ARCH" = "armhf" ]; then VSCODE_ARCH="cli-linux-armhf"; \
    else VSCODE_ARCH="cli-linux-x64"; fi && \
    curl -fsSL "https://update.code.visualstudio.com/latest/${VSCODE_ARCH}/stable" \
      -o /tmp/vscode-cli.tar.gz && \
    tar -xzf /tmp/vscode-cli.tar.gz -C /usr/local/bin && \
    chmod +x /usr/local/bin/code && \
    rm /tmp/vscode-cli.tar.gz

# ╔════════════════════════════════════════════════════════════════════════╗
# ║  BLOCK 1: Install Supercronic                                          ║
# ╚════════════════════════════════════════════════════════════════════════╝

ARG SUPERCRONIC_VERSION=v0.2.44

RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then \
      SUPERCRONIC_URL="https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-amd64"; \
    elif [ "$ARCH" = "arm64" ]; then \
      SUPERCRONIC_URL="https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-arm64"; \
    elif [ "$ARCH" = "armhf" ] || [ "$ARCH" = "arm" ]; then \
      SUPERCRONIC_URL="https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-arm"; \
    else \
      echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    echo "Downloading supercronic ${SUPERCRONIC_VERSION} for $ARCH" && \
    curl -fsSL "$SUPERCRONIC_URL" -o /usr/local/bin/supercronic && \
    chmod +x /usr/local/bin/supercronic && \
    supercronic -version

# ╔════════════════════════════════════════════════════════════════════════╗
# ║  BLOCK 2: Create Supercronic Helper Script                             ║
# ╚════════════════════════════════════════════════════════════════════════╝

RUN { \
      echo '#!/bin/bash'; \
      echo 'WORKSPACE="/home/node/.openclaw/workspace"'; \
      echo 'CRONTAB_FILE="$WORKSPACE/crontab"'; \
      echo 'SUPERCRONIC_LOG="$WORKSPACE/supercronic.log"'; \
      echo ''; \
      echo '# Kill any existing supercronic process'; \
      echo 'pkill supercronic 2>/dev/null || true'; \
      echo ''; \
      echo '# Only start if crontab exists and is non-empty'; \
      echo 'if [ -f "$CRONTAB_FILE" ] && [ -s "$CRONTAB_FILE" ]; then'; \
      echo '  echo "[$(date -Iseconds)] Starting supercronic → $CRONTAB_FILE"'; \
      echo '  nohup /usr/local/bin/supercronic "$CRONTAB_FILE" >> "$SUPERCRONIC_LOG" 2>&1 &'; \
      echo '  SCPID=$!'; \
      echo '  sleep 1'; \
      echo '  if ps -p $SCPID > /dev/null 2>&1; then'; \
      echo '    echo "[$(date -Iseconds)] Supercronic running (PID $SCPID)"'; \
      echo '  else'; \
      echo '    echo "[$(date -Iseconds)] ERROR: Supercronic failed — check $SUPERCRONIC_LOG"'; \
      echo '  fi'; \
      echo 'else'; \
      echo '  echo "[$(date -Iseconds)] No crontab at $CRONTAB_FILE or file is empty — skipping"'; \
      echo 'fi'; \
    } > /usr/local/bin/start-openclaw-cron.sh && \
    chmod +x /usr/local/bin/start-openclaw-cron.sh

# Ensure workspace exists with correct ownership
RUN mkdir -p /home/node/.openclaw/workspace && \
    chown -R 1000:1000 /home/node/.openclaw

# Create placeholder crontab so container doesn't error on first boot
RUN printf '# OpenClaw crontab — add scheduled tasks here\\n' \
      > /home/node/.openclaw/workspace/crontab && \
    printf '# Example:\\n' >> /home/node/.openclaw/workspace/crontab && \
    printf '# */5 * * * * /usr/local/bin/python3 /home/node/.openclaw/workspace/my_script.py >> /home/node/.openclaw/workspace/my_script.log 2>&1\\n' \
      >> /home/node/.openclaw/workspace/crontab && \
    chown 1000:1000 /home/node/.openclaw/workspace/crontab

# ╔════════════════════════════════════════════════════════════════════════╗
# ║  BLOCK 3: Create Master Startup Wrapper (Dynamic Entrypoint)           ║
# ╚════════════════════════════════════════════════════════════════════════╝

# CI/CD will override these defaults by inspecting the base image
ARG OPENCLAW_EP="docker-entrypoint.sh"
ARG OPENCLAW_CMD="node /app/dist/index.js"

RUN { \
      echo '#!/bin/sh'; \
      echo 'set -e'; \
      echo ''; \
      echo '# Start VS Code tunnel in background'; \
      echo 'LOG="/home/node/openclaw-data/vscode-tunnel.log"'; \
      echo 'echo "[tunnel] $(date -Iseconds): starting" >> "$LOG"'; \
      echo 'code tunnel --accept-server-license-terms --name openclaw >> "$LOG" 2>&1 &'; \
      echo 'TUNNEL_PID=$!'; \
      echo 'echo "[tunnel] PID $TUNNEL_PID" >> "$LOG"'; \
      echo ''; \
      echo '# Start supercronic scheduler in background'; \
      echo '/usr/local/bin/start-openclaw-cron.sh'; \
      echo ''; \
      echo '# Chain into original OpenClaw entrypoint'; \
      printf 'exec %s %s\n' "${OPENCLAW_EP}" "${OPENCLAW_CMD}"; \
    } > /usr/local/bin/start-tunnel.sh && \
    chmod +x /usr/local/bin/start-tunnel.sh

# ╔════════════════════════════════════════════════════════════════════════╗
# ║  BLOCK 4: Set Master Entrypoint                                        ║
# ╚════════════════════════════════════════════════════════════════════════╝

ENTRYPOINT ["/usr/local/bin/start-tunnel.sh"]

# Drop back to non-root user
USER 1000
