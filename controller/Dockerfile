FROM debian:12-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends bash ca-certificates curl python3 \
  && rm -rf /var/lib/apt/lists/*

# Render CLI 2.28.0 or later.
RUN curl -fsSL https://raw.githubusercontent.com/render-oss/cli/refs/heads/main/bin/install.sh | sh

RUN curl -fsSL "https://cursor.com/install?channel=lab" | bash \
  && ln -sfn /root/.local/bin/agent /usr/local/bin/agent

COPY spawn.sh /opt/cursor-render/spawn.sh
RUN chmod +x /opt/cursor-render/spawn.sh

ENV PATH="/usr/local/bin:/root/.local/bin:${PATH}"
ENV CURSOR_POOL="render-sandboxes"
WORKDIR /opt/cursor-render

# The API key is read from CURSOR_API_KEY. It is not passed on the command line.
CMD agent worker controller --spawn /opt/cursor-render/spawn.sh --pool "${CURSOR_POOL:-render-sandboxes}" --session-token
