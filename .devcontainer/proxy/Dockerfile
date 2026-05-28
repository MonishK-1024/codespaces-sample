# Use a plain Python base so we control the mitmproxy version exactly.
# mitmproxy/mitmproxy:latest can be ahead of the API we target.
FROM python:3.12-slim-bookworm

# Install mitmproxy pinned to the 10.x API used by egress_filter.py
RUN pip install --no-cache-dir "mitmproxy>=10.0,<11.0"

# Create required directories
RUN mkdir -p /var/log/egress /etc/mitmproxy /opt/mitmproxy /data/mitmproxy \
    && chmod 755 /var/log/egress /data/mitmproxy

# Copy the egress filter addon (root-owned, read-only)
COPY egress_filter.py /opt/mitmproxy/egress_filter.py
RUN chmod 644 /opt/mitmproxy/egress_filter.py \
    # Catch syntax errors at build time rather than at container start
    && python3 -m py_compile /opt/mitmproxy/egress_filter.py

EXPOSE 7890

# confdir=/data/mitmproxy: mitmproxy writes its auto-generated CA cert here.
# Mounted as a shared Docker volume so the devcontainer can read the cert.
# The allowlist is bind-mounted read-only from the repo.
CMD ["mitmdump", "--listen-host", "0.0.0.0", "--listen-port", "7890", "--set", "confdir=/data/mitmproxy", "-s", "/opt/mitmproxy/egress_filter.py"]
