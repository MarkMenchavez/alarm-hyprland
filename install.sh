#!/usr/bin/env bash
set -euxo pipefail

DISK="/dev/nvme0n1"

echo "This will WIPE and repartition ${DISK}"
read -rp "Type YES to continue: " CONFIRM </dev/tty
if [[ "${CONFIRM}" != "YES" ]]; then
  echo "Aborted."
  exit 1
fi

wipefs -a "${DISK}"
