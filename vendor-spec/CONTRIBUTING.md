# Contributing

## Repository purpose

This repository is the Fedora Atomic branch of the Margine project. It
documents and validates Fedora Atomic Desktop as a base for the same
reproducible, recoverable, inspectable operating model that the Arch-based
branch implements.

Phase 1 (the Fedora-Silverblue VM lab) is complete: this repo's declarative
spec (`declarations/margine-atomic.yaml`) plus its `configure-*` / `validate-*`
scripts now feed the `margine-image` CI pipeline that builds the shipped
Bluefin-DX-based image and ISO. Contributions are primarily:

- corrections to documentation that misrepresents Fedora Atomic mechanics
- improvements to validation scripts and diagnostics
- observations recorded from the actual lab that contradict working hypotheses
- new ADRs for decisions that emerge during lab work

## Relationship to other Margine repositories

This repository is intentionally independent from `margine-os` and
`margine-os-personal`. It does not import, depend on, or re-export logic from
either of them. If a decision here turns out to apply to the shared machinery,
it belongs in a discussion, not in a cross-repo dependency.

## What belongs here

- documentation of Fedora Atomic mechanics as observed in the lab
- validation and diagnostic shell scripts for Fedora Atomic systems
- YAML desired-state declarations
- Margine branding assets as they apply to the Silverblue variant
- ADRs for architectural decisions specific to this branch

## What should stay out

- secrets or machine-specific credentials
- private package URLs or unpublished distribution remotes
- Arch/AUR assumptions imported without explicit adaptation
- changes that only make sense for the existing CachyOS/personal product
- scripts that modify system state (all scripts here are read-only validators)

## Documentation language

All documentation is in English. This matches the rest of the Margine project
family and makes ADRs and architecture records reviewable outside a single
language context.

## Change style

- keep scripts readable and explicit
- prefer small, auditable changes over compact clever ones
- update documentation when observed lab behavior contradicts it
- preserve rollback and recovery assumptions: if a change would make rollback
  harder, state why it is justified
- avoid importing Arch-specific concepts without a documented Fedora equivalent

## Validation before opening a pull request

```sh
bash -n scripts/<changed-script>
shellcheck scripts/<changed-script>
python3 -c "import yaml; yaml.safe_load(open('declarations/margine-atomic.yaml'))"
```

