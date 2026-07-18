#!/usr/bin/env python3
# SysAdminHCP DKIM outbound signer (Ubuntu/Debian only — see enableDkimUbuntu() in
# mailService.ts for why this exists instead of spamdyke's dkim-sign option).
#
# Usage: dkim-sign-message.py <domain> <private-key-file>  (message on stdin, signed
# message on stdout). Any failure here must never break mail delivery — the caller
# (deploy/qmail-queue-check.sh) only trusts the output if this exits 0 with non-empty
# stdout, and falls back to the original unsigned message otherwise.
import sys
import dkim

def main():
    domain = sys.argv[1].encode()
    privkey_path = sys.argv[2]
    selector = b'default'  # matches generateDkim()'s existing "default._domainkey" DNS record

    with open(privkey_path, 'rb') as f:
        privkey = f.read()
    message = sys.stdin.buffer.read()

    sig = dkim.sign(
        message, selector, domain, privkey,
        include_headers=[b'from', b'to', b'subject', b'date', b'message-id'],
    )
    sys.stdout.buffer.write(sig)
    sys.stdout.buffer.write(message)

if __name__ == '__main__':
    main()
