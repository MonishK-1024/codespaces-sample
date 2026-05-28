#!/bin/bash
# entrypoint.sh -- runs as root before VS Code Server connects.
# Responsibilities:
#   1. Wait for the mitmproxy proxy container to generate its CA certificate.
#   2. Install that CA cert into the system trust store so HTTPS works through the proxy.
#   3. Lock down .devcontainer/ so the vscode user cannot tamper with proxy config.
#   4. Install a system-level git pre-commit hook that blocks commits to .devcontainer/.
#   5. Exec the main container command (sleep infinity, replaced by VS Code Server).
set -euo pipefail

CERT_SRC="/opt/mitmproxy-certs/mitmproxy-ca-cert.pem"
CERT_DEST="/usr/local/share/ca-certificates/mitmproxy-ca.crt"

echo "[entrypoint] Waiting for proxy CA certificate (up to 90s)..."
for i in $(seq 1 30); do
    if [ -f "$CERT_SRC" ]; then
        echo "[entrypoint] Certificate found on attempt $i."
        break
    fi
    sleep 3
done

if [ -f "$CERT_SRC" ]; then
    cp "$CERT_SRC" "$CERT_DEST"
    update-ca-certificates > /dev/null 2>&1
    echo "[entrypoint] mitmproxy CA certificate installed into system trust store."
else
    echo "[entrypoint] WARNING: CA cert not found after 90s." >&2
    echo "[entrypoint] HTTPS requests through the proxy will fail certificate validation." >&2
    echo "[entrypoint] Check that the proxy container is running and healthy." >&2
fi

# Ensure proxy settings profile script cannot be modified by the vscode user.
chmod 444 /etc/profile.d/proxy-settings.sh 2>/dev/null || true

# ── Protect devcontainer config from being edited inside the container ──────
# Root cause of previous bypass: the vscode user OWNS the workspace files, so
# chmod go-w left the owner write bit intact and they could still edit them.
#
# Fix: transfer ownership to root (chown -R root:root) then strip ALL write
# bits (chmod -R a-w). Directories get +x so ls/read still works.
# Root on the Codespace VM can still modify files when legitimately needed.
for DCPATH in /workspace/.devcontainer /workspaces/*/.devcontainer; do
    if [ -d "$DCPATH" ]; then
        chown -R root:root "$DCPATH"
        # Directories need execute (traverse) but not write
        find "$DCPATH" -type d -exec chmod 555 {} \;
        # Files: read-only for everyone
        find "$DCPATH" -type f -exec chmod 444 {} \;
        echo "[entrypoint] $DCPATH locked: owned by root, no write for anyone."
    fi
done

# ── Git system-level pre-commit hook ──────────────────────────────────────────
# Blocks commits that touch .devcontainer/ files regardless of how git is invoked.
# Placed in /opt/git-hooks/ (root-owned) and wired via git config --system so
# the vscode user cannot override it with a local repo config.
mkdir -p /opt/git-hooks
cat > /opt/git-hooks/pre-commit << 'HOOK'
#!/bin/sh
if git diff --cached --name-only | grep -q '^\.devcontainer/'; then
    echo ""
    echo "COMMIT REJECTED: Changes to .devcontainer/ cannot be committed from inside"
    echo "the container. This configuration is managed externally and is tamper-protected."
    echo ""
    exit 1
fi
HOOK
chmod 755 /opt/git-hooks/pre-commit
chown -R root:root /opt/git-hooks
# --system writes to /etc/gitconfig (root-owned); vscode cannot override at system level
git config --system core.hooksPath /opt/git-hooks
echo "[entrypoint] Git pre-commit hook installed (blocks .devcontainer/ commits)."

echo "[entrypoint] Dev container starting."
exec "$@"
