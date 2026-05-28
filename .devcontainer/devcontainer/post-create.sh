#!/bin/bash
# post-create.sh — runs inside the devcontainer as the vscode user after creation.
# Installs Python project dependencies and prints a welcome summary.
set -euo pipefail

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SVCLink Dev Container — post-create setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd /workspace

# ── Install Python dependencies ───────────────────────────────────────────────
if [ -f requirements.txt ]; then
    echo ""
    echo "[post-create] Installing Python dependencies..."
    pip install --no-cache-dir -q -r requirements.txt
    echo "[post-create] Dependencies installed."
else
    echo "[post-create] No requirements.txt found — skipping."
fi

# ── Verify proxy connectivity ─────────────────────────────────────────────────
echo ""
echo "[post-create] Verifying proxy connectivity..."

# Test an allowed domain
if curl -sf --max-time 8 -o /dev/null https://pypi.org/simple/ 2>/dev/null; then
    echo "[post-create] ✓ Proxy is working (pypi.org reachable)."
else
    echo "[post-create] ✗ Warning: pypi.org not reachable. Check proxy container logs."
fi

# Test that a blocked domain is actually blocked
BLOCKED_STATUS=$(curl -sf --max-time 5 -o /dev/null -w "%{http_code}" \
    --proxy "http://proxy:7890" https://example.com/ 2>/dev/null || true)
if [ "$BLOCKED_STATUS" = "403" ]; then
    echo "[post-create] ✓ Egress filtering is active (example.com blocked with 403)."
else
    echo "[post-create] ✗ Warning: example.com was NOT blocked (status: $BLOCKED_STATUS)."
fi

# ── Welcome message ───────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Ready. Key information:"
echo ""
echo "  Egress filtering : ACTIVE — only allowlisted domains reachable"
echo "  Egress logs      : /var/log/egress/egress.log  (read-only, view with 'tail -f')"
echo "  Secrets CLI      : devsecret --help"
echo "  Allowlist        : .devcontainer/proxy/allowlist.txt  (edit in repo, rebuild to apply)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
