#!/usr/bin/env zsh
# NAME: qemu
# DESC: qemu-test: boot an ISO in a KVM test VM with a persistent qcow2 disk (keeps state between runs)
# TAGS: SYSTEM, DEV
# DEP: qemu-system-x86_64, qemu-img
# DEFAULT: off
# VER: 2.0
# DEV: SilverX
# EXAMPLE: qemu-test ~/iso/archlinux.iso
# EXAMPLE: qemu-test distro.iso -m 8G -smp 4 -name distro --reset
# EXAMPLE: qemu-test-ls
# | Ported from `qemu.zsh` (v1.1).
# |
# | | Option | Meaning |
# | |---|---|
# | | `-m SIZE` | RAM (default `$QEMU_TEST_MEM`, 24G) |
# | | `-smp N` | CPU cores (default `$QEMU_TEST_CPUS`, 8) |
# | | `-name NAME` | VM name → disk `$QEMU_TEST_DIR/NAME.qcow2` (default test-vm) |
# | | `-disk SIZE` | size of a newly created disk (default `$QEMU_TEST_DISK`, 20G) |
# | | `--reset` | delete the VM's disk first (fresh install) |
# | | anything else | passed straight to qemu-system-x86_64 |
# |
# | `qemu-test-ls` lists existing test disks, `qemu-test-rm NAME` deletes one.
# | Tweakables: `QEMU_TEST_DIR` (default `/var/tmp`), `QEMU_TEST_MEM`, `QEMU_TEST_CPUS`, `QEMU_TEST_DISK`.

: ${QEMU_TEST_DIR:=/var/tmp}
: ${QEMU_TEST_MEM:=24G}
: ${QEMU_TEST_CPUS:=8}
: ${QEMU_TEST_DISK:=20G}

# qemu-test ISO [-m RAM] [-smp N] [-name NAME] [-disk SIZE] [--reset] [qemu args...] — boot ISO in a KVM VM
qemu-test() {
  emulate -L zsh
  if [[ -z ${1-} || ! -f $1 ]]; then
    print -u2 "usage: qemu-test /path/to/image.iso [-m 24G] [-smp 8] [-name NAME] [-disk 20G] [--reset] [extra qemu flags...]"
    return 2
  fi
  msh::need qemu-system-x86_64 qemu-img || return
  local iso=$1; shift
  local mem=$QEMU_TEST_MEM cores=$QEMU_TEST_CPUS name=test-vm size=$QEMU_TEST_DISK wipe=0
  local -a extra
  while (( $# )); do
    case $1 in
      -m)     mem=$2; shift 2 ;;
      -smp)   cores=$2; shift 2 ;;
      -name)  name=$2; shift 2 ;;
      -disk)  size=$2; shift 2 ;;
      --reset) wipe=1; shift ;;
      *) extra+=("$1"); shift ;;
    esac
  done
  local disk="$QEMU_TEST_DIR/$name.qcow2"
  msh::info "ISO: $iso"
  msh::info "VM: $name | RAM: $mem | CPU: $cores | disk: $disk"
  if (( wipe )) && [[ -f $disk ]]; then
    msh::confirm "--reset: delete $disk?" || return 1
    rm -f -- "$disk"
  fi
  if [[ ! -f $disk ]]; then
    msh::info "creating a new $size qcow2 disk"
    qemu-img create -f qcow2 "$disk" "$size" >/dev/null || return
  else
    msh::info "reusing existing disk (previous VM state)"
  fi
  [[ -w /dev/kvm ]] || msh::warn "/dev/kvm not writable — add yourself to the kvm group"
  qemu-system-x86_64 -enable-kvm -cpu host -m "$mem" -smp "$cores" \
    -drive file="$disk",format=qcow2 -cdrom "$iso" -boot order=d -name "$name" "${extra[@]}"
}

# qemu-test-ls — list the persistent test VM disks
qemu-test-ls() {
  local -a disks=( $QEMU_TEST_DIR/*.qcow2(N) )
  (( $#disks )) || { msh::info "no test disks in $QEMU_TEST_DIR"; return 0; }
  du -h -- $disks
}

# qemu-test-rm NAME — delete a test VM disk
qemu-test-rm() {
  local disk="$QEMU_TEST_DIR/${1:?usage: qemu-test-rm <name>}.qcow2"
  [[ -f $disk ]] || { msh::err "no such disk: $disk"; return 1; }
  msh::confirm "Delete $disk?" && rm -f -- "$disk" && msh::ok "deleted $disk"
}
