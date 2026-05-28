FROM mcr.microsoft.com/devcontainers/python:3.12-bullseye

# ── Extra tools ──────────────────────────────────────────────────────────────
# jq: used to pretty-print NDJSON egress logs (one object per line)
RUN apt-get update && apt-get install -y --no-install-recommends jq \
    && rm -rf /var/lib/apt/lists/*

# ── Strip sudo from the default vscode user ───────────────────────────────────
# The devcontainers base image grants passwordless sudo — remove it so developers
# cannot escalate to root and modify proxy config or CA trust.
RUN echo "" > /etc/sudoers.d/vscode \
    && chmod 440 /etc/sudoers.d/vscode

# ── Create devsecrets group ───────────────────────────────────────────────────
# Only members of this group can read /run/devuser-secrets/.
# The vscode user is added; Copilot/Claude Code run as vscode too but cannot
# access the path because it is outside their configured allowedDirectories.
RUN groupadd --system devsecrets \
    && usermod -aG devsecrets vscode

# ── Directory layout ──────────────────────────────────────────────────────────
# /run/devuser-secrets/ — bind-mounted read-only from Codespace VM secrets
RUN mkdir -p /run/devuser-secrets \
    && chown root:devsecrets /run/devuser-secrets \
    && chmod 750 /run/devuser-secrets

# /opt/mitmproxy-certs/ — proxy_certs volume is mounted here (read-only)
RUN mkdir -p /opt/mitmproxy-certs

# /etc/profile.d/proxy-settings.sh — sets proxy env for every interactive shell.
# Written by root, made read-only so vscode user cannot unset the proxy.
RUN printf '%s\n' \
    '# Managed by devcontainer — do not edit.' \
    'export HTTP_PROXY=http://proxy:7890' \
    'export HTTPS_PROXY=http://proxy:7890' \
    'export http_proxy=http://proxy:7890' \
    'export https_proxy=http://proxy:7890' \
    'export NO_PROXY=localhost,127.0.0.1,proxy' \
    'export no_proxy=localhost,127.0.0.1,proxy' \
    'export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt' \
    'export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt' \
    > /etc/profile.d/proxy-settings.sh \
    && chmod 444 /etc/profile.d/proxy-settings.sh

# ── Tools ─────────────────────────────────────────────────────────────────────
COPY devsecret /usr/local/bin/devsecret
RUN chown root:root /usr/local/bin/devsecret \
    && chmod 755 /usr/local/bin/devsecret

# ── Entrypoint ────────────────────────────────────────────────────────────────
COPY entrypoint.sh /usr/local/bin/devcontainer-entrypoint.sh
RUN chown root:root /usr/local/bin/devcontainer-entrypoint.sh \
    && chmod 755 /usr/local/bin/devcontainer-entrypoint.sh

# ── Docker ENV (inherited by all processes including VS Code extensions) ───────
ENV HTTP_PROXY=http://proxy:7890 \
    HTTPS_PROXY=http://proxy:7890 \
    http_proxy=http://proxy:7890 \
    https_proxy=http://proxy:7890 \
    NO_PROXY=localhost,127.0.0.1,proxy \
    no_proxy=localhost,127.0.0.1,proxy \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# Run as root so entrypoint can install the CA cert.
# VS Code Server connects as 'vscode' (set by remoteUser in devcontainer.json).
USER root
ENTRYPOINT ["/usr/local/bin/devcontainer-entrypoint.sh"]
CMD ["sleep", "infinity"]
