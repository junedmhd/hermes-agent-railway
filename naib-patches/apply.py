"""Naib's patches to upstream Hermes, applied at image build (Dockerfile).

Each patch replaces an exact upstream snippet. If a snippet is missing (upstream changed it),
the build fails here, so a patch can never silently stop applying. Run from /opt/hermes-agent.
"""
import sys
from pathlib import Path

EMAIL = Path("plugins/platforms/email/adapter.py")


def sub(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    if text.count(old) != 1:
        sys.exit(f"naib patch '{label}': expected exactly one match in {path}, found {text.count(old)}")
    path.write_text(text.replace(old, new))
    print(f"naib patch applied: {label}")


# 1. Mail that arrived while Hermes was down or restarting (2026-11-16). On first connect the
#    adapter marked ALL existing mail as handled; baseline on SEEN instead. The RFC822 fetch marks
#    processed mail \Seen, so unread mail stays eligible for the first poll.
sub(EMAIL, 'imap.uid("search", None, "ALL")', 'imap.uid("search", None, "SEEN")', "email backlog after restart")
sub(EMAIL, '"[Email] IMAP connection test passed. %d existing messages skipped."',
    '"[Email] IMAP connection test passed. %d already-read messages skipped; unread mail will be processed."',
    "email backlog log line")

# 2. HTML email (2026-11-16). Replies went out as plain text full of markdown. Send
#    multipart/alternative: the text as written, plus HTML rendered from it.
sub(EMAIL, "from email.mime.text import MIMEText\n",
    '''from email.mime.text import MIMEText


def _naib_alternative(body: str) -> MIMEMultipart:
    """Plain text plus an HTML rendering of its markdown, as one multipart/alternative part."""
    alt = MIMEMultipart("alternative")
    alt.attach(MIMEText(body, "plain", "utf-8"))
    try:
        import markdown as _md
        rendered = _md.markdown(body, extensions=["extra", "sane_lists", "nl2br"])
        html = ('<!doctype html><html><body style="margin:0;padding:0">'
                '<div style="font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Helvetica,Arial,sans-serif;'
                'font-size:15px;line-height:1.5;color:#1a1a1a;max-width:680px">' + rendered + '</div></body></html>')
        alt.attach(MIMEText(html, "html", "utf-8"))
    except Exception:
        pass  # plain text alone is still a valid message
    return alt
''', "email html helper")
sub(EMAIL, '            msg.attach(MIMEText(body, "plain", "utf-8"))\n',
    '            msg.attach(_naib_alternative(body))\n', "email html replies")
sub(EMAIL, '        msg = MIMEText(message, "plain", "utf-8")\n',
    '        msg = MIMEMultipart()\n        msg.attach(_naib_alternative(message))\n', "email html standalone sends")
sub(EMAIL, '"plain text formatting (no markdown). Keep responses concise but complete.',
    '"simple markdown (short headings, bold, bullet lists); it is sent as HTML. Keep responses concise but complete.',
    "email platform hint")
