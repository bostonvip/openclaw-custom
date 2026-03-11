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

# Drop back to non-root user
USER 1000
