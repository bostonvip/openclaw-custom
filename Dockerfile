# Custom OpenClaw image with extended skill dependencies
# Extends the official image with commonly needed binaries
FROM ghcr.io/openclaw/openclaw:main

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
    && rm -rf /var/lib/apt/lists/*

# Install uv (fast Python package manager — used by Gemini image gen and other skills)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    mv /root/.local/bin/uv /usr/local/bin/uv && \
    mv /root/.local/bin/uvx /usr/local/bin/uvx

# Drop back to non-root user
USER 1000
