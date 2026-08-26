#!/usr/bin/env python3
"""
SysAdminHCP mail metadata capture — invoked from qmail-queue-check.sh for every message,
both inbound and outbound, right before it's handed to the real qmail-queue. This is the only
point in the delivery path that ever sees the actual message content: by the time the panel
looks at qmail-send's own log for the "Recent Mail" list, the queue file is long gone and no
Subject was ever recorded there. This script appends one JSON line per envelope recipient to
/var/log/sysadminhcp/email-subjects.jsonl, which the panel correlates back against qmail-send's
log entries by (from, to, bytes) - see EmailStatsService.getRecentMail() in the panel source.

Never raises past main(): any failure here must not block or corrupt mail delivery. Bounded by
a `timeout` wrapper in the calling shell script as a second layer of defense against hangs.

Usage: extract-mail-metadata.py <direction> <sender> [recipient ...] -- <message-file-path>
"""
import sys
import os
import json
import time

LOG_PATH = '/var/log/sysadminhcp/email-subjects.jsonl'
MAX_SUBJECT_LEN = 200


def decode_subject(msg):
    try:
        raw = msg.get('subject')
        if raw is None:
            return ''
        # email.policy.default auto-decodes RFC 2047 encoded-words (=?UTF-8?B?...?=) when the
        # header value is stringified, so non-ASCII subjects come out human-readable already.
        return str(raw).strip()[:MAX_SUBJECT_LEN]
    except Exception:
        return ''


def main():
    args = sys.argv[1:]
    if '--' not in args:
        return
    sep = args.index('--')
    meta = args[:sep]
    rest = args[sep + 1:]
    if len(meta) < 2 or not rest:
        return
    direction, sender = meta[0], meta[1]
    recipients = [r for r in meta[2:] if r]
    if not recipients:
        return
    msg_path = rest[0]

    from email.parser import BytesParser
    from email import policy

    with open(msg_path, 'rb') as f:
        size = os.fstat(f.fileno()).st_size
        # headersonly=True stops parsing at the blank line after headers — never loads a large
        # attachment/body into memory just to read one header.
        msg = BytesParser(policy=policy.default).parse(f, headersonly=True)

    subject = decode_subject(msg)
    ts = int(time.time())

    lines = []
    for rcpt in recipients:
        lines.append(json.dumps({
            'ts': ts,
            'direction': direction,
            'from': sender,
            'to': rcpt,
            'subject': subject,
            'bytes': size,
        }))

    with open(LOG_PATH, 'a') as out:
        out.write('\n'.join(lines) + '\n')


if __name__ == '__main__':
    try:
        main()
    except Exception:
        # Best-effort only — a broken/unreadable message must still be queued normally.
        pass
