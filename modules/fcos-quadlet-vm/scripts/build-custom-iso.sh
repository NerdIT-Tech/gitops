#!/usr/bin/env bash
# Builds an unattended-install FCOS ISO with the rendered Ignition config
# embedded - see ADR-0007. Invoked by terraform_data.custom_iso_build's
# local-exec provisioner, not meant to be run standalone.
set -euo pipefail

: "${PRISTINE_ISO_URL:?}" "${PRISTINE_ISO_SHA256:?}" "${IGNITION_FILE:?}" "${OUTPUT_ISO:?}" "${DEST_DEVICE:?}"

if ! command -v coreos-installer >/dev/null 2>&1; then
  echo "coreos-installer not found on PATH - required to build the Ignition-embedded install ISO." >&2
  echo "Install: cargo install coreos-installer --locked (see ADR-0007)." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_ISO")"

pristine="$(dirname "$OUTPUT_ISO")/$(basename "$PRISTINE_ISO_URL")"

# Cache the pristine (uncustomized) live ISO by checksum - it's ~1GB and
# identical across every service using the same fcos_stream/release, no
# reason to re-download it per service or per apply.
if [ ! -f "$pristine" ] || [ "$(sha256sum "$pristine" | cut -d' ' -f1)" != "$PRISTINE_ISO_SHA256" ]; then
  curl -sSfL -o "$pristine" "$PRISTINE_ISO_URL"
  actual="$(sha256sum "$pristine" | cut -d' ' -f1)"
  if [ "$actual" != "$PRISTINE_ISO_SHA256" ]; then
    echo "checksum mismatch for $pristine: expected $PRISTINE_ISO_SHA256, got $actual" >&2
    exit 1
  fi
fi

rm -f "$OUTPUT_ISO"
coreos-installer iso customize \
  --dest-device "$DEST_DEVICE" \
  --dest-ignition "$IGNITION_FILE" \
  -o "$OUTPUT_ISO" \
  "$pristine"
