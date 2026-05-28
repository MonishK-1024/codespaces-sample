FROM mitmproxy/mitmproxy:latest

USER root

# Create directories
RUN mkdir -p /var/log/egress /etc/mitmproxy /opt/mitmproxy /data/mitmproxy \
    && chmod 755 /var/log/egress /data/mitmproxy

# Copy the egress filter addon (owned by root — not writable by proxy process)
COPY egress_filter.py /opt/mitmproxy/egress_filter.py
RUN chmod 644 /opt/mitmproxy/egress_filter.py

EXPOSE 7890

# confdir=/data/mitmproxy: mitmproxy writes its auto-generated CA cert here.
# This directory is a shared Docker volume so the devcontainer can read the cert.
# The allowlist is bind-mounted read-only from the repo at /etc/mitmproxy/allowlist.txt.
CMD [ \
    "mitmdump", \
    "--listen-host", "0.0.0.0", \
    "--listen-port", "7890", \
    "--set", "confdir=/data/mitmproxy", \
    "-s", "/opt/mitmproxy/egress_filter.py" \
]
