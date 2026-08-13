"""Domain-aware sharing rights backend for Radicale.

Grants: full access to your own collections, full access to your domain's shared
collection, full access everywhere for the panel's own internal service identity
(used to provision shared collections and build the public read-only feed export —
see davService.ts; there is no anonymous/token-based path handled here at all,
deliberately: public sharing is brokered entirely by the Node panel authenticating
as the service identity, not by Radicale granting any unauthenticated access). Config:

    [rights]
    type = sysadminhcp_dav.rights
"""
import re

from radicale.rights import BaseRights

from ._service import SERVICE_LOGIN

# Matches both the collection root itself ("/shared@domain") and anything under it
# ("/shared@domain/calendar") — Radicale does not guarantee a trailing slash on the
# collection's own root path, only on paths one level deeper or below.
_SHARED_PATH_RE = re.compile(r"^/shared@([^/]+)(?:/.*)?$")


def _owns(user, path):
    root = f"/{user}"
    return path == root or path.startswith(root + "/")


class Rights(BaseRights):
    def authorization(self, user, path):
        if not user:
            return ""

        if user == SERVICE_LOGIN:
            return "RrWw"

        # The server root ("/", or "" once Radicale strips the leading/trailing
        # slashes) is not anyone's collection - it's what every real CalDAV/CardDAV
        # client PROPFINDs first to discover {DAV:}current-user-principal before it
        # ever knows to look at /user@domain/. Radicale's own stock rights backends
        # (e.g. owner_only.Rights) explicitly grant read-only access here for exactly
        # that reason; without it, every client's very first request 403s before
        # login even gets a chance to matter. Confirmed live: authentication
        # succeeded ("Successful login") immediately followed by "Access to '/'
        # denied" on literally every login attempt, for every client.
        if path in ("", "/"):
            return "R"

        # Owner access: /user@domain (root) and everything under /user@domain/...
        if _owns(user, path):
            return "RrWw"

        # Domain-shared collections: /shared@domain(/...) — any authenticated user
        # on that same domain gets full access.
        match = _SHARED_PATH_RE.match(path)
        if match:
            shared_domain = match.group(1)
            user_domain = user.split("@")[-1] if "@" in user else ""
            if user_domain == shared_domain:
                return "RrWw"

        return ""
