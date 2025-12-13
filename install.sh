#!/usr/bin/env bash

# Re-exec with bash if not already running under bash
if [ -z "${BASH_VERSION:-}" ]; then
  echo "Re-executing under bash..." >&2
  exec /bin/bash
fi

set -Eeuo pipefail

DISK="/dev/nvme0n1"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

info() {
  echo "==> $*"
}

# --- Safety checks ------------------------------------------------------------

# Must be root
[[ $EUID -eq 0 ]] || die "Must be run as root"

# Disk must exist and be a block device
[[ -b "${DISK}" ]] || die "${DISK} is not a block device"

# Refuse to run if disk is mounted
if lsblk -n -o MOUNTPOINT "${DISK}" | grep -qv '^$'; then
  die "${DISK} has mounted partitions"
fi

info "Target disk: ${DISK}"
lsblk "${DISK}"

# --- Confirmation logic --------------------------------------------------------

if [[ "${FORCE:-}" != "YES" ]]; then
  if [[ ! -t 0 ]]; then
    die "Non-interactive shell detected. Set FORCE=YES to continue."
  fi

  echo
  echo "⚠️  ALL DATA ON ${DISK} WILL BE DESTROYED"
  read -rp "Type YES to continue: " CONFIRM </dev/tty
  [[ "${CONFIRM}" == "YES" ]] || die "Aborted by user"
else
  info "FORCE=YES set — skipping confirmation"
fi

# --- Destructive operations ---------------------------------------------------

info "Wiping filesystem signatures"
wipefs -a "${DISK}"

info "Creating GPT partition table"
sfdisk "$DISK" <<'EOF'
label: gpt

2048MiB,512MiB,EF02,BiosBoot
,1024MiB,EF00,EFI
,2048MiB,8300,boot
,8192MiB,8200,swap
,40960MiB,8300,root
,,8300,home
EOF

info "Reloading partition table"
partprobe "${DISK}"

info "Final disk layout:"
lsblk "${DISK}"

info "Partitioning completed successfully"
