"""
mitmproxy addon: egress domain allowlist enforcement + full request/response logging.

Behaviour:
  - Every outbound request is logged (JSON, one line per event).
  - Requests to domains NOT in the allowlist receive a 403 and are logged as BLOCK.
  - Requests to allowlisted domains are proxied normally and the response is also logged.
  - Sensitive auth headers (Authorization, Cookie, etc.) are REDACTED in logs.
  - Request and response bodies are logged up to MAX_BODY_BYTES (default 50 KB).
  - Logs rotate at 100 MB, keeping 5 backups.

Log path  : /var/log/egress/egress.log  (set via EGRESS_LOG_PATH env var)
Allowlist : /etc/mitmproxy/allowlist.txt (set via ALLOWLIST_PATH env var)
"""

from __future__ import annotations

import json
import logging
import logging.handlers
import os
import re
from datetime import datetime, timezone
from typing import Optional

from mitmproxy import ctx, http

# ── Configuration ─────────────────────────────────────────────────────────────

ALLOWLIST_PATH: str = os.environ.get(
    "ALLOWLIST_PATH", "/etc/mitmproxy/allowlist.txt"
)
LOG_PATH: str = os.environ.get(
    "EGRESS_LOG_PATH", "/var/log/egress/egress.log"
)
MAX_BODY_BYTES: int = int(os.environ.get("MAX_BODY_BYTES", str(50 * 1024)))  # 50 KB
LOG_MAX_BYTES: int = 100 * 1024 * 1024   # 100 MB per log file
LOG_BACKUP_COUNT: int = 5

# Headers whose values must never appear in logs
_SENSITIVE: frozenset[str] = frozenset(
    {
        "authorization",
        "cookie",
        "set-cookie",
        "x-api-key",
        "x-auth-token",
        "x-session-token",
        "proxy-authorization",
        "x-goog-authenticated-user-email",
        "x-forwarded-token",
    }
)

# ── Helpers ───────────────────────────────────────────────────────────────────


def _load_patterns(path: str) -> list[re.Pattern[str]]:
    """Parse the allowlist file into compiled regexes.

    Wildcard (*) matches exactly one subdomain label (no dots), e.g.:
      *.github.com  →  api.github.com  ✓
      *.github.com  →  a.b.github.com  ✗  (two labels — use two rules)
    """
    patterns: list[re.Pattern[str]] = []
    try:
        with open(path, encoding="utf-8") as fh:
            for raw in fh:
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                # Escape special regex chars, then restore the wildcard
                regex = re.escape(line).replace(r"\*", r"[^.]+")
                patterns.append(re.compile(f"^{regex}$", re.IGNORECASE))
    except OSError as exc:
        ctx.log.error(f"[egress-filter] Cannot read allowlist '{path}': {exc}")
    return patterns


def _redact_headers(headers: dict[str, str]) -> dict[str, str]:
    return {
        k: "[REDACTED]" if k.lower() in _SENSITIVE else v
        for k, v in headers.items()
    }


def _decode_body(raw: bytes, limit: int) -> tuple[str, bool]:
    """Return (decoded_string, was_truncated)."""
    truncated = len(raw) > limit
    chunk = raw[:limit]
    try:
        return chunk.decode("utf-8", errors="replace"), truncated
    except Exception:
        return f"<binary {len(raw)} bytes>", truncated


def _make_logger() -> logging.Logger:
    os.makedirs(os.path.dirname(LOG_PATH) or ".", exist_ok=True)
    logger = logging.getLogger("egress")
    logger.setLevel(logging.INFO)
    if not logger.handlers:
        handler = logging.handlers.RotatingFileHandler(
            LOG_PATH, maxBytes=LOG_MAX_BYTES, backupCount=LOG_BACKUP_COUNT
        )
        handler.setFormatter(logging.Formatter("%(message)s"))
        logger.addHandler(handler)
    return logger


# ── Addon ─────────────────────────────────────────────────────────────────────


class EgressFilter:
    """mitmproxy addon that enforces the domain allowlist and logs all traffic."""

    def __init__(self) -> None:
        self._patterns: list[re.Pattern[str]] = []
        self._logger: logging.Logger = _make_logger()

    # ── Lifecycle ──────────────────────────────────────────────────────────────

    def load(self, loader) -> None:  # noqa: ANN001
        self._patterns = _load_patterns(ALLOWLIST_PATH)
        ctx.log.info(
            f"[egress-filter] Loaded {len(self._patterns)} allowlist rules "
            f"from '{ALLOWLIST_PATH}'"
        )

    # ── Internal ──────────────────────────────────────────────────────────────

    def _allowed(self, host: str) -> bool:
        return any(p.match(host) for p in self._patterns)

    def _write(self, entry: dict) -> None:
        self._logger.info(json.dumps(entry, ensure_ascii=False))

    # ── mitmproxy hooks ───────────────────────────────────────────────────────

    def request(self, flow: http.HTTPFlow) -> None:
        host: str = flow.request.pretty_host
        allowed: bool = self._allowed(host)

        entry: dict = {
            "ts": datetime.now(timezone.utc).isoformat(),
            "type": "REQUEST",
            "verdict": "ALLOW" if allowed else "BLOCK",
            "method": flow.request.method,
            "url": flow.request.pretty_url,
            "host": host,
            "headers": _redact_headers(dict(flow.request.headers)),
        }

        if flow.request.content:
            body, truncated = _decode_body(flow.request.content, MAX_BODY_BYTES)
            entry["body"] = body
            entry["body_truncated"] = truncated

        self._write(entry)

        if not allowed:
            # Block the request — the response hook will see the 403 we set here.
            flow.response = http.Response.make(
                403,
                (
                    f"[egress-filter] BLOCKED: '{host}' is not in the allowlist.\n"
                    "Contact your admin to add new domains.\n"
                ),
                {"Content-Type": "text/plain"},
            )
            # Mark this flow so the response hook skips it
            flow.metadata["egress_blocked"] = True

    def response(self, flow: http.HTTPFlow) -> None:
        # Flows blocked in the request phase are already logged — skip them.
        if flow.metadata.get("egress_blocked"):
            return

        host: str = flow.request.pretty_host
        resp: Optional[http.Response] = flow.response

        entry: dict = {
            "ts": datetime.now(timezone.utc).isoformat(),
            "type": "RESPONSE",
            "verdict": "ALLOW",
            "method": flow.request.method,
            "url": flow.request.pretty_url,
            "host": host,
            "status_code": resp.status_code if resp else None,
            "response_headers": dict(resp.headers) if resp else {},
        }

        if resp and resp.content:
            body, truncated = _decode_body(resp.content, MAX_BODY_BYTES)
            entry["response_body"] = body
            entry["response_body_truncated"] = truncated

        self._write(entry)


addons = [EgressFilter()]
