#!/usr/bin/env bash
# Build and sign a CitronOS release: the files Software Update installs.
#
#   scripts/make-release.sh VERSION PRIVATE-KEY OUT-DIR [stable|beta]
#
# Writes OUT-DIR/citronos-VERSION.tar.gz (an update bundle, see
# make-update-bundle.sh), citronos-VERSION.manifest.json (its version, tag,
# channel, commit and SHA-256) and citronos-VERSION.manifest.json.sig (the
# manifest's Ed25519 signature). Publish all three as assets of the GitHub
# release tagged vVERSION; .github/workflows/release.yml does this for each
# tag pushed. The signature is checked against apps/settings/release-keys
# before anything is written, so a key systems don't trust can't make one.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:?usage: make-release.sh VERSION PRIVATE-KEY OUT-DIR [stable|beta]}"
key="${2:?private key file}"
out="${3:?output folder}"
channel="${4:-stable}"
[[ $version =~ ^[0-9]{1,4}\.[0-9]{1,4}(\.[0-9]{1,4})?(-[0-9A-Za-z.-]{1,40})?$ ]] || { echo "Not a version: $version" >&2; exit 1; }
[[ $channel == stable || $channel == beta ]] || { echo "Channel must be stable or beta." >&2; exit 1; }
[[ $channel == beta || $version != *-* ]] || { echo "A pre-release ($version) goes on the beta channel." >&2; exit 1; }
# The release must be the version CitronOS says it is (Release.qml: 4.0 for 4.0.x).
named="$(sed -n 's/.*property string version: "\(.*\)".*/\1/p' "$REPO/apps/lib/theme/Release.qml")"
[[ $version == "$named" || $version == "$named".* || $version == "$named"-* ]] || {
  echo "Release.qml says version $named; this release is $version. Update Release.qml first." >&2; exit 1; }

mkdir -p "$out"
name="citronos-$version"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
GG_RELEASE_VERSION="$version" GG_RELEASE_CHANNEL="$channel" \
  bash "$REPO/scripts/make-update-bundle.sh" "$work/$name.tar.gz" "$work/version.json" >/dev/null
python3 - "$work/$name.tar.gz" "$work/version.json" "$version" "$channel" > "$work/$name.manifest.json" <<'PY'
import hashlib, json, sys
bundle, record, version, channel = sys.argv[1:5]
meta = json.load(open(record))
digest = hashlib.sha256(open(bundle, "rb").read()).hexdigest()
json.dump({"format": 1, "name": "CitronOS", "version": version, "tag": "v" + version, "channel": channel,
           "file": bundle.rsplit("/", 1)[-1], "sha256": digest, "commit": meta.get("commit", ""),
           "date": meta.get("date", "")}, sys.stdout, indent=2)
print()
PY
openssl pkeyutl -sign -inkey "$key" -rawin -in "$work/$name.manifest.json" -out "$work/$name.manifest.json.sig"
keys="${GG_RELEASE_KEYS:-$REPO/apps/settings/release-keys}"
trusted=0
for pub in "$keys"/*.pem; do
  [[ -e $pub ]] || continue
  if openssl pkeyutl -verify -pubin -inkey "$pub" -rawin -in "$work/$name.manifest.json" \
       -sigfile "$work/$name.manifest.json.sig" >/dev/null 2>&1; then trusted=1; break; fi
done
((trusted)) || { echo "That key isn't one of $keys/*.pem: systems wouldn't install this release." >&2; exit 1; }
mv "$work/$name.tar.gz" "$work/$name.manifest.json" "$work/$name.manifest.json.sig" "$out/"
echo "› $out/$name.tar.gz, .manifest.json, .manifest.json.sig ($channel)"
