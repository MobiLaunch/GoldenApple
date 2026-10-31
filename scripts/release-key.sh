#!/usr/bin/env bash
# Make a CitronOS release signing key (Ed25519).
#
#   scripts/release-key.sh [PRIVATE-KEY-FILE]
#
# The public key goes into apps/settings/release-keys/ (commit it: systems
# trust what they install). The private key is written to PRIVATE-KEY-FILE
# (default ~/citronos-release-key.pem), readable only by you, and never
# printed. Keep it offline as well, and give it to CI as the repository
# secret CITRONOS_RELEASE_KEY (GitHub: Settings › Secrets and variables ›
# Actions › New repository secret, pasting the file's contents), which
# .github/workflows/release.yml signs releases with.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
key="${1:-$HOME/citronos-release-key.pem}"
pub="$REPO/apps/settings/release-keys/citronos-$(date +%Y%m%d).pem"
[[ ! -e $key ]] || { echo "$key already exists; not replacing it." >&2; exit 1; }
[[ ! -e $pub ]] || { echo "$pub already exists." >&2; exit 1; }
command -v openssl >/dev/null || { echo "openssl is needed." >&2; exit 1; }
(umask 077; openssl genpkey -algorithm ed25519 -out "$key")
openssl pkey -in "$key" -pubout -out "$pub"
echo "› Private key: $key (keep it secret; back it up offline)"
echo "› Public key:  ${pub#"$REPO"/} (commit this)"
echo "› Then add the private key's contents as the GitHub Actions secret CITRONOS_RELEASE_KEY."
