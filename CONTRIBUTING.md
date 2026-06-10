# Contributing to Agently

Agently is currently maintainer-directed.

This repository is public, but it is not currently accepting unsolicited code
contributions, feature requests, broad refactors, formatting sweeps, governance
edits, doctrine edits, or speculative cleanup.

Please do not open pull requests unless the maintainer has explicitly invited
the work.

## Collaboration Interest

Individuals interested in Agently may contact the maintainer first with:

- who they are
- what they are interested in
- relevant background
- the specific area they want to discuss

Opening an issue or pull request does not imply review, acceptance, roadmap
commitment, or support obligation.

## Pull Requests

Pull requests are considered only when they are maintainer-invited and limited
to the agreed scope.

A pull request may be closed without review if it:

- was not invited
- targets `main` directly from any branch other than `dev`
- changes protected authority surfaces
- introduces new runtime authority
- adds legacy compatibility paths
- changes doctrine or governance without explicit maintainer direction
- expands project scope
- adds external services, telemetry, or network behavior
- performs broad formatting or cleanup outside the requested task

## Branch Model

Agently uses a controlled source-repository branch promotion model:

```text
task/* -> dev -> main
```

`main` is the public canonical branch.

`dev` is the controlled integration branch.

`main` should only receive changes through a formal pull request from `dev`
after the full promotion gate passes.

This branch model is for the `uscient/agently` source repository. It is separate
from Agently product workstream branch behavior, which remains local-only.

## Protected Surfaces

The following areas are maintainer-controlled:

- doctrine
- authority rules
- command contracts
- agent boundaries
- promotion rules
- runtime authority
- install behavior
- security tests
- protected-surface tests

## Validation

Expected validation for invited code changes:

```sh
bash -n bin/agently lib/*.sh tests/*.sh
./tests/smoke.sh
```

Additional targeted tests may be required depending on the change.
