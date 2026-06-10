# Pull Request

## Maintainer Invitation

- [ ] This pull request was explicitly invited by the maintainer.
- [ ] The linked maintainer request, issue, or discussion is included below.

Maintainer request:

<!-- link or short context -->

## Branch Target

- [ ] This PR targets `dev`, or
- [ ] This PR targets `main` from `dev` as a formal promotion PR.

PRs into `main` from branches other than `dev` are not accepted.

## Scope

- [ ] This change is limited to the invited scope.
- [ ] This change does not modify doctrine, authority, governance, command contracts, or protected surfaces unless explicitly requested.
- [ ] This change does not introduce new runtime authority.
- [ ] This change does not add telemetry, network behavior, external services, or self-install behavior.
- [ ] This change does not add legacy compatibility paths unless explicitly requested.

## Validation

- [ ] `bash -n bin/agently lib/*.sh tests/*.sh`
- [ ] `./tests/smoke.sh`
- [ ] Relevant targeted tests were run.

## Notes

<!-- concise implementation notes -->
