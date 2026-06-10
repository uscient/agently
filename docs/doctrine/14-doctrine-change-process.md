---
title: Doctrine Change Process
status: active
authority: doctrine
last_reviewed: 2026-06-02
---

# Doctrine Change Process

## When To Change Doctrine

Doctrine changes are required when work changes:

- Agently identity or scope;
- authority model;
- command contracts;
- architecture;
- filesystem layout;
- templates;
- workflow state;
- guardrail posture;
- testing obligations;
- roadmap boundaries.

## Requirements

A doctrine change SHOULD include:

- reason for the change;
- changed doctrine files;
- affected implementation areas;
- validation or tests run;
- explicit rationale when architectural or authority boundaries change.

## No Silent Drift

Future agents MUST NOT silently alter doctrine. If implementation and doctrine
diverge, reconcile them explicitly.

## Versioning

Doctrine is versioned with the repository. It SHOULD evolve through normal commits
and review.

## Final Report

Final reports for doctrine changes SHOULD identify:

- doctrine files changed;
- implementation files affected, if any;
- validation run;
- known mismatches or deferred reconciliation.
