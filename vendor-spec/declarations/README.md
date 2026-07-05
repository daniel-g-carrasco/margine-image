# Declarations

This directory contains draft desired-state declarations for Margine Fedora
Atomic.

They are not applied automatically yet. During phase 1, declarations are a design
contract that records what the manual Silverblue lab has proven.

Rules:

- do not store secrets;
- do not encode guesses as policy;
- keep host state, user state, applications, containers, and boot security
  separate;
- keep hardware/media host state separate from creative or gaming applications;
- keep gaming launchers, host runtime helpers, and gaming-session policy
  separate;
- keep update orchestration policy separate from package/application
  declarations;
- update docs when declarations change;
- build read-only validation before automatic apply tooling.

Current draft:

- `margine-atomic.yaml`: single-file profile for the phase 1 GNOME/Silverblue
  target.
