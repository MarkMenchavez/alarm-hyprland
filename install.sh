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
sfdisk "${DISK}" <<'EOF'
label: gpt
unit: MiB
first-lba: 2048

# p1 — BIOS boot (reserved / unused)
size=512,  type=ef02, name="BIOS boot"

# p2 — EFI System Partition
size=1024, type=ef00, name="EFI System"

# p3 — Linux boot
size=2048, type=8300, name="Linux boot"

# p4 — Linux swap
size=8192, type=8200, name="Linux swap"

# p5 — Linux root
size=40960, type=8300, name="Linux root"

# p6 — Linux home (remaining space)
type=8300, name="Linux home"
EOF

info "Reloading partition table"
partprobe "${DISK}"

info "Final disk layout:"
lsblk "${DISK}"

info "Partitioning completed successfully"
