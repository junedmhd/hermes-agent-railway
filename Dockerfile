FROM python:3.14-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl ca-certificates ripgrep ffmpeg \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"

# Pinned: upstream moves fast and an unpinned clone ran unreviewed code on every build.
# Bump deliberately (the Naib repo records the ref in deploy/hermes.ref).
ARG HERMES_REF=4abca2ced7ff336da96f44b937ce0569da0dda60
RUN git clone --recurse-submodules https://github.com/NousResearch/hermes-agent.git /opt/hermes-agent \
    && git -C /opt/hermes-agent checkout --recurse-submodules "$HERMES_REF"

WORKDIR /opt/hermes-agent
# Naib patch (2026-11-16): on first connect the email adapter marked ALL existing mail as handled,
# so mail that arrived while Hermes was down or restarting was never answered. Baseline on SEEN
# instead: processed mail is marked \Seen by the RFC822 fetch, unread mail stays eligible.
# The build fails if upstream changed the line, so the patch can never silently stop applying.
RUN f=plugins/platforms/email/adapter.py \
    && grep -q 'imap.uid("search", None, "ALL")' "$f" \
    && sed -i 's/imap.uid("search", None, "ALL")/imap.uid("search", None, "SEEN")/' "$f" \
    && sed -i 's/IMAP connection test passed. %d existing messages skipped./IMAP connection test passed. %d already-read messages skipped; unread mail will be processed./' "$f" \
    && grep -q 'imap.uid("search", None, "SEEN")' "$f" \
    && ! grep -q 'imap.uid("search", None, "ALL")' "$f"
RUN uv venv venv --python 3.14 \
    && VIRTUAL_ENV=/opt/hermes-agent/venv uv pip install -e ".[all,telegram,stt-whisper]"

ENV PATH="/opt/hermes-agent/venv/bin:$PATH"

RUN mkdir -p /root/.hermes/{cron,sessions,logs,memories,skills,pairing,hooks,image_cache,audio_cache} \
    && cp cli-config.yaml.example /root/.hermes/config.yaml \
    && touch /root/.hermes/.env

COPY auth_proxy.py /auth_proxy.py
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
