"""Shared constant between auth.py and rights.py for the panel's own internal
service identity — used to provision shared calendars/address books and to build
the public read-only feed export, without needing to impersonate a real mailbox."""

SERVICE_LOGIN = "__sysadminhcp_service__"
