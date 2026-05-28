#!/bin/bash
# entrypoint.sh — runs as root before VS Code Server connects.
# Responsibilities:
#   1. Wait for the mitmproxy proxy container to generate its CA certificate.
#   2. Install that CA cert into the system trust store so HTTPS works through the proxy.
#   3. Lock down the proxy settings profile.d file.
#   4. Exec the main container command (sleep infinity, replaced by VS Code Server).
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

# Ensure the proxy settings profile script cannot be modified by the vscode user.
# (It was already created with chmod 444 in the Dockerfile, this is belt-and-suspenders.)
chmod 444 /etc/profile.d/proxy-settings.sh 2>/dev/null || true

echo "[entrypoint] Dev container starting."
exec "$@"
