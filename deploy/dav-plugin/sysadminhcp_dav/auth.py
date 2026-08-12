"""Direct vpopmail-MySQL auth backend for Radicale.

Queries the same vpopmail data Dovecot already authenticates against — no Dovecot
socket dependency, so this keeps working even if Dovecot is stopped. Config:

    [auth]
    type = sysadminhcp_dav.auth
    mysql_host = 127.0.0.1
    mysql_port = 3306
    mysql_db = vpopmail
    mysql_user = sysadminhcp
    mysql_password = <same password Dovecot's dovecot-sql.conf.ext already uses>

Two vpopmail MySQL layouts exist in the wild (confirmed live on two different
SysAdminHCP servers, not just documentation): a single `vpopmail` table with a
`pw_domain` column (current install script convention), and one table per domain
named after the domain with dots replaced by underscores, no `pw_domain` column
(legacy vpopmail default layout, still running on at least one active server).
Both are tried, unified table first.
"""
import crypt
import hmac
import re

import mysql.connector
from radicale.auth import BaseAuth
from radicale.log import logger

from ._service import SERVICE_LOGIN

PLUGIN_CONFIG_SCHEMA = {"auth": {
    "mysql_host": {"value": "127.0.0.1", "type": str},
    "mysql_port": {"value": "3306", "type": int},
    "mysql_db": {"value": "vpopmail", "type": str},
    "mysql_user": {"value": "sysadminhcp", "type": str},
    "mysql_password": {"value": "", "type": str},
    # Internal credential the panel itself uses to provision shared collections and
    # build the public read-only feed export — never exposed to real mail users.
    "service_password": {"value": "", "type": str},
}}

# Only safe characters for use as a MySQL table identifier — domain names in this
# stack are always lowercase-alnum/hyphen/dot, never anything a WHERE-clause
# parameter binding could otherwise neutralize (table names can't be bound params).
_SAFE_DOMAIN_TABLE = re.compile(r"^[a-z0-9_]+$")


class Auth(BaseAuth):
    def __init__(self, configuration):
        super().__init__(configuration.copy(PLUGIN_CONFIG_SCHEMA))
        self._db_host = self.configuration.get("auth", "mysql_host")
        self._db_port = self.configuration.get("auth", "mysql_port")
        self._db_name = self.configuration.get("auth", "mysql_db")
        self._db_user = self.configuration.get("auth", "mysql_user")
        self._db_pass = self.configuration.get("auth", "mysql_password")
        self._service_password = self.configuration.get("auth", "service_password")

    def _fetch_row(self, cursor, pw_name, pw_domain):
        # Preferred: single unified table with a pw_domain column.
        try:
            cursor.execute(
                "SELECT pw_passwd, pw_clear_passwd FROM vpopmail "
                "WHERE pw_name=%s AND pw_domain=%s",
                (pw_name, pw_domain),
            )
            return cursor.fetchone()
        except mysql.connector.Error as e:
            if e.errno != 1146:  # ER_NO_SUCH_TABLE
                raise

        # Fallback: legacy per-domain table layout (table name = domain, dots -> _).
        table = pw_domain.replace(".", "_").replace("-", "_")
        if not _SAFE_DOMAIN_TABLE.match(table):
            return None
        cursor.execute(
            f"SELECT pw_passwd, pw_clear_passwd FROM `{table}` WHERE pw_name=%s",
            (pw_name,),
        )
        return cursor.fetchone()

    def _login(self, login, password):
        # Internal service identity — constant-time compare, no DB round trip, and
        # deliberately checked before the "@" shape check so it works even if the
        # service password itself is empty/misconfigured (fails closed either way,
        # since hmac.compare_digest("", "") on a real client password is never true
        # unless the client also sends an empty password, which auth would reject
        # downstream regardless).
        if login == SERVICE_LOGIN:
            if self._service_password and hmac.compare_digest(password, self._service_password):
                return login
            return ""

        # Radicale login strings are the full email address (user@domain) —
        # matches this stack's existing convention (Dovecot, RainLoop/Roundcube
        # all authenticate with the full address, not the local part alone).
        if "@" not in login:
            return ""
        pw_name, pw_domain = login.rsplit("@", 1)

        conn = None
        try:
            conn = mysql.connector.connect(
                host=self._db_host, port=self._db_port,
                database=self._db_name,
                user=self._db_user, password=self._db_pass,
                connection_timeout=5,
            )
            cursor = conn.cursor(dictionary=True)
            row = self._fetch_row(cursor, pw_name, pw_domain)
            cursor.close()

            if not row:
                return ""

            # CRYPT hash first (handles MD5/SHA256/SHA512-crypt schemes) — same
            # column/verification method Dovecot's own passdb query relies on.
            if row["pw_passwd"] and crypt.crypt(password, row["pw_passwd"]) == row["pw_passwd"]:
                return login

            # Fallback: cleartext password, only populated if vpopmail was built
            # with --enable-clear-passwd=y (short column, may be empty/truncated).
            if row["pw_clear_passwd"] and password == row["pw_clear_passwd"]:
                return login

            return ""
        except mysql.connector.Error as e:
            logger.error("sysadminhcp_dav auth: vpopmail MySQL error: %s", e)
            return ""
        finally:
            if conn is not None:
                conn.close()
