Deferred per QMAILTOASTER-SELF-HOST-PLAN.md's own risk assessment: DKIM (a modern,
widely-supported standard) supersedes DomainKeys, and libdomainkeys itself is abandoned
upstream with no GitHub mirror (SourceForge only). Not in the top-level Makefile's
`COMPONENTS` list — add it back only if a real need for legacy DomainKeys support surfaces.
