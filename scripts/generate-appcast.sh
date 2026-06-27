#!/usr/bin/env bash
#
# Generate the Sparkle appcast.xml from the built .dmg releases.
#
# DEFERRED — NOT YET IMPLEMENTED. Sparkle 2 integration (SPM dependency, EdDSA
# keypair, public key in the bundle, the updater UI, and the `generate_appcast`
# tooling it ships) was split into its own issue (see .scratch/earnings-ping/
# issues/09-sparkle-self-updates.md). The release pipeline (build-dmg.sh +
# notarize.sh) deliberately does not depend on this step.
#
# Once Sparkle is vendored, this script should:
#   1. Run Sparkle's `generate_appcast` over the directory of signed .dmgs:
#        ./bin/generate_appcast build/dist/
#      which EdDSA-signs each entry with the private key in the login keychain
#      and writes/updates appcast.xml.
#   2. Publish the .dmg to GitHub Releases and appcast.xml to GitHub Pages
#      (stable channel only; monthly check; prompt-to-install).
set -euo pipefail

cat >&2 <<'MSG'
!! generate-appcast.sh is a deferred stub.
   Sparkle self-updates are tracked in:
     .scratch/earnings-ping/issues/09-sparkle-self-updates.md
   Implement Sparkle there, then flesh out this script per its header comment.
MSG
exit 1
