# CitronOS release keys

Software Update installs a CitronOS release only if its manifest is signed by
one of the Ed25519 public keys here (`*.pem`). They ship with CitronOS, so a
system trusts the keys it was installed or last updated with.

- **Make the first key:** `scripts/release-key.sh` (it writes the public key
  here and says where to keep the private one).
- **Add a key** (to rotate): put its `.pem` here and release once while the old
  key still signs; then remove the old one in a later release.
- **Never** put a private key in this folder or anywhere in the repository.
