# shellcheck shell=bash
# The v_* globals below are set by whichever entry point sources this file, so shellcheck cannot see
# their assignment, and v_cherry_pick_branch_created is set here but read by the entry point.
# shellcheck disable=SC2154,SC2034
# Shared kernel build mechanics, sourced by build_kernel and build_kernel_arcade.
#
# This library is a pure extraction: every function below is byte-identical to the one it replaced
# in build_kernel. It deliberately has no side effects at source time, so both entry points can
# source it before deciding anything.
#
# The functions read exactly these globals, which the sourcing entry point must set before calling
# them (nounset makes an unset one fatal):
#
#   v_packages_destination  where built .debs are collected
#   v_local_version         the kernel localversion (e.g. sav)
#   v_cpu_target            -march/-mtune target validated and configured into the kernel
#   v_gcc_package           the gcc package to build with; resolved here when empty
#   v_sav_remote            remote holding the per-major sav branch to replay, or empty to skip
#   v_unattended            non-empty to suppress the only prompt (verify_disabled_modules)
#   v_bisect                non-empty in bisect mode; build_kernel only
#   c_crack_bundle_temp_file  a writable temporary path for the downloaded packaging bundle
#
# v_cherry_pick_branch_created is assigned here and read by build_kernel exit hook.


# Pure constants, so the library can define them at source time.
#
# The cherry-pick branch name lives here because apply_sav_branch lands the replayed sav commits on
# it, so both entry points need it, not only the cherry-pick feature.
c_cherry_pick_branch=temporary_cherry_picks
# Example: https://kernel.ubuntu.com/mainline/v6.7/
c_mainline_ppa_url=https://kernel.ubuntu.com/mainline/
# Example: https://kernel.ubuntu.com/mainline/v6.8-rc1/amd64/linux-modules-6.8.0-060800rc1-generic_6.8.0-060800rc1.202401212233_amd64.deb
c_package_name_pattern="amd64/linux-modules-[[:alnum:]_.-]+_amd64+\.deb"

function find_latest_installed_gcc_package {
  dpkg-query -W -f='${binary:Package}\t${db:Status-Status}\n' 'gcc-[0-9]*' 2>/dev/null |
    awk '$2 == "installed" && $1 ~ /^gcc-[0-9]+(:[[:alnum:]]+)?$/ { sub(/:.*/, "", $1); print $1 }' |
    sort -Vu |
    tail -n 1
}

function validate_toolchain {
  if [[ -n $v_gcc_package ]]; then
    if [[ ! $v_gcc_package =~ ^gcc-[0-9]+$ ]] ||
      [[ $(dpkg-query -W -f='${db:Status-Status}' "$v_gcc_package" 2>/dev/null || true) != installed ]]; then
      >&2 echo "Invalid GCC package: $v_gcc_package"
      exit 1
    fi
  else
    v_gcc_package=$(find_latest_installed_gcc_package)
    if [[ -z $v_gcc_package ]]; then
      >&2 echo 'No installed gcc-N package found.'
      exit 1
    fi
  fi

  if ! command -v "$v_gcc_package" >/dev/null; then
    >&2 echo "Invalid GCC package: $v_gcc_package"
    exit 1
  fi

  local cpu_flag
  for cpu_flag in "-march=$v_cpu_target" "-mtune=$v_cpu_target"; do
    if ! "$v_gcc_package" "$cpu_flag" -x c -fsyntax-only /dev/null >/dev/null 2>&1; then
      >&2 echo "Unsupported CPU target for $v_gcc_package: $v_cpu_target"
      exit 1
    fi
  done
}

# Return format: `M.m.p` or `M.m-rcN`.
#
function normalize_kernel_version {
  local version=$1

  if [[ $version =~ ^[[:digit:]]+\.[[:digit:]]+$ ]]; then
    echo -n "$version.0"
  else
    echo -n "$version"
  fi
}

# Shorten the kernel version:
#
# - `with_rc`: remove the patch `0` version (present in GA versions), but keep the RC (if present)
# - `no_rc`  : remove both the patch `0` and RC versions
#
# $2: `with_rc` or `no_rc`
#
function short_kernel_version {
  case $2 in
  with_rc)
    echo "$1" | perl -pe 's/^\d+\.\d+\K\.0//'
    ;;
  no_rc)
    echo "$1" | perl -ne 'print /^(\d+\.\d+)/'
    ;;
  *)
    >&2 echo "Invalid short version mode: $2"
    exit 1
    ;;
  esac
}

function fetch_remotes {
  git fetch --all
}

# Return format: normalized version.
#
function find_latest_kernel_version {
  local normalized_version=$1

  local short_version
  short_version=$(short_kernel_version "$normalized_version" no_rc)
  local escaped_short_version=${short_version//./\\.}

  # Append a zero to GA releases, otherwise, `sort -V` places it before the RCs.
  #
  local latest_version
  latest_version=$(
    git tag \
      | grep -P "^v$escaped_short_version"'($|-rc|\.)' \
      | perl -pe 's/^v\d+\.\d+\K$/.0/' \
      | sort -V \
      | tail -n 1 \
      | perl -pe 's/^v//' \
    || true
  )

  if [[ -z $latest_version ]]; then
    >&2 echo "No kernel versions found for v$short_version."
    exit 1
  fi

  echo -n "$latest_version"
}

# See remove_destination_old_version_files() for the filenames format.
#
# Returns the config file full path.
#
function find_local_config_file_for_version {
  local kernel_version=$1

  find "$v_packages_destination" -name "config-$kernel_version" -printf "%p"
}

# Search the most recent patch version config for the given kernel, both in the PPA and the local
# directory.
#
function find_most_recent_config_version_available {
  local building_kernel_version=$1

  local candidate_versions
  candidate_versions=$(find_ppa_kernel_versions "$1")

  >&2 echo "Found config package candidate versions:"
  >&2 echo "$candidate_versions" | perl -pe 's/^/- /'

  # When operating, the PPA includes all the version as directories, including failed builds.
  #
  # It doesn't always operate though, and based on the logic below, if a config file is present,
  # but the version is not included in the PPA, is ignored.
  #
  # Since the config files come from the PPA anyway, this doesn't matter.
  #
  for candidate_version in $candidate_versions; do
    # WATCH OUT! Versioning on the PPA/packages is slightly different, so try to keep versions
    # as normalized as possible.
    #
    local source_config_file short_candidate_version
    short_candidate_version=$(short_kernel_version "$candidate_version" with_rc)
    source_config_file=$(find_local_config_file_for_version "$short_candidate_version")

    if [[ -n $source_config_file ]]; then
      >&2 echo "Found local config version $candidate_version."
      echo "$source_config_file"
      return
    fi

    local amd64_modules_package_link
    amd64_modules_package_link=$(find_amd64_modules_package_link "$candidate_version")

    if [[ -n $amd64_modules_package_link ]]; then
      >&2 echo "Found packaged config version ($candidate_version) in the PPA; downloading and extracting..."
      download_and_extract_config_file_from_modules_package "$amd64_modules_package_link"
      return
    else
      >&2 echo "Module package not found for version $candidate_version!"
    fi
  done

  >&2 echo "No config (module package) found for the required kernel!"
  exit 1
}

# # Print the versions, one per line, with .0 patch version.
#
function find_ppa_kernel_versions {
  local target_version
  target_version=$(short_kernel_version "$1" no_rc)

  declare -x target_version_regex=${target_version//./\\.}

  local mainline_ppa_page_content
  mainline_ppa_page_content=$(wget --quiet "$c_mainline_ppa_url" --output-document -)

  # Examples:
  #
  #   >v6.6/</a>
  #   >v6.7-rc1/</a>
  #   >v6.7.1/</a>
  #
  # Append a zero to GA releases, otherwise, `sort -V` places it before the RCs.
  #
  echo "$mainline_ppa_page_content" \
  | perl -lne 'print $1 if />v($ENV{target_version_regex}(\.\d+|-rc\d+)?)\/</' \
  | perl -pe 's/^\d+\.\d+\K$/.0/' \
  | sort --version-sort --reverse
}

function find_amd64_modules_package_link {
  local kernel_version=$1

  local package_kernel_version
  package_kernel_version=$(short_kernel_version "$kernel_version" with_rc)

  local builds_url=${c_mainline_ppa_url}v$package_kernel_version

  local builds_page_content
  builds_page_content=$(wget --quiet "$builds_url" --output-document - || true)

  if [[ -n $builds_page_content ]]; then
    [[ $builds_page_content =~ $c_package_name_pattern ]] || true

    if [[ -n "${BASH_REMATCH[*]}" ]]; then
      echo -n "$builds_url/${BASH_REMATCH[0]}"
    fi
  fi
}

# Prints the full path of the extracted config file, transformed to use the standard naming.
#
function download_and_extract_config_file_from_modules_package {
  local amd64_modules_package_link=$1

  # Download into a unique temp dir (not a predictable /tmp/<basename>) so concurrent runs don't
  # collide on the same path. The package is only needed to extract the config, so drop it after.
  #
  local download_dir
  download_dir=$(mktemp -d)

  local local_package_name=$download_dir/${amd64_modules_package_link##*/}

  curl -L "$amd64_modules_package_link" --output "$local_package_name"

  # Examples:
  #
  #   ./boot/config-6.7.0-060700-generic
  #   ./boot/config-6.10.0-061000rc1-generic
  #
  # The filename returned is the input one, so we need to further process it.
  #
  local raw_config_file
  raw_config_file=$(
    dpkg-deb --fsys-tarfile "$local_package_name" \
      | tar xv -C "$v_packages_destination" --wildcards --transform="s|^\./boot/||" "./boot/config-*" \
      | perl -pe 's|^\./boot/||'
  )

  # The config has been extracted to the destination; the package itself is no longer needed.
  rm -rf "$download_dir"

  # We can't unify the regex easily, because of the required dash preceding the `rc` in the desired
  # output.
  #
  if [[ $raw_config_file == *rc* ]]; then
    config_file=$(echo "$raw_config_file" | perl -pe 's/\.0-\d{6}(rc\d+)-generic/-$1/')
  else
    config_file=$(echo "$raw_config_file" | perl -pe 's/(\.0)?-\d{6}-generic//')
  fi

  # Make sure that the processing was correct.
  #
  if [[ -z $(echo "$config_file" | perl -ne 'print if /^config-\d+\.\d+(\.\d+|-rc\d+)?$/') ]]; then
    >&2 echo "Config filename processing failed: $raw_config_file"
    exit 1
  fi

  mv "$v_packages_destination/$raw_config_file" "$v_packages_destination/$config_file"

  echo -n "$v_packages_destination/$config_file"
}

# Download crack.bundle for the specified kernel version.
#
# $1: kernel version (e.g., "6.19-rc8" or "6.11.4")
#
# Returns: path to the downloaded crack.bundle file
#
function download_crack_bundle {
  local kernel_version=$1
  local short_version
  short_version=$(short_kernel_version "$kernel_version" with_rc)

  local crack_bundle_url="${c_mainline_ppa_url}v${short_version}/crack.bundle"

  >&2 echo "Downloading crack.bundle from ${crack_bundle_url}..."

  if wget --quiet "$crack_bundle_url" -O "$c_crack_bundle_temp_file"; then
    >&2 echo "Downloaded crack.bundle for v${short_version}"
    echo -n "$c_crack_bundle_temp_file"
  else
    >&2 echo "Failed to download crack.bundle from ${crack_bundle_url}"
    exit 1
  fi
}

# Extract debian/ and debian.master/ directories from crack.bundle.
# The bundle is a git bundle containing the Ubuntu mainline packaging.
#
# $1: path to crack.bundle file
#
# Extracts debian directories to the current directory.
#
function extract_debian_from_crack_bundle {
  local bundle_path=$1

  if [[ ! -f "$bundle_path" ]]; then
    >&2 echo "Error: crack.bundle not found at $bundle_path"
    exit 1
  fi

  >&2 echo "Extracting debian packaging from crack.bundle..."

  # Determine the tag name from the bundle itself (e.g., cod/mainline/v6.17.13).
  # Do NOT rely on `git tag -l` against the local repo: previous runs leave
  # cod/mainline/* tags around, and `sort -V | tail -1` would return a stale tag
  # (e.g. cod/mainline/v7.0-rc7 when the freshly downloaded bundle is v7.0.0).
  local bundle_tag
  bundle_tag=$(git bundle list-heads "$bundle_path" \
    | awk '{print $2}' \
    | grep '^refs/tags/cod/mainline/' \
    | sed 's|^refs/tags/||' \
    | sort -V \
    | tail -1)

  if [[ -z $bundle_tag ]]; then
    >&2 echo "Error: No cod/mainline tag found in bundle"
    exit 1
  fi

  # Fetch the bundle into current repo (bundles have dependencies on existing commits).
  # Force-update so a stale local tag from a prior run doesn't block the fetch.
  if ! git fetch --force "$bundle_path" "refs/tags/${bundle_tag}:refs/tags/${bundle_tag}" 2>/dev/null; then
    >&2 echo "Error: Failed to fetch crack.bundle"
    exit 1
  fi

  # Extract debian directories from the tag
  if ! git checkout "$bundle_tag" -- debian debian.master 2>/dev/null; then
    >&2 echo "Error: Failed to extract debian directories from $bundle_tag"
    exit 1
  fi

  >&2 echo "Successfully extracted debian packaging from $bundle_tag"
}

# Assumes that there are no multiple builds for the same version.
#
# Return format: normalized version.
#
function find_latest_packaged_version {
  local kernel_version=$1

  if [[ $kernel_version =~ ^([[:digit:]]+\.[[:digit:]]+)$ ]]; then
    kernel_version=${BASH_REMATCH[1]}.0
  fi

  # Extract the kernel version from every image package filename, normalize it
  # to the canonical form (M.m.p for GA, M.m-rcN for RC), then filter for the
  # target. Must recognize all historical and current naming variants:
  #
  #   - linux-image-M.m-localver-generic_...                                   (very old, no ABI)
  #   - linux-image(-unsigned)?-M.m-<abi>-localver-generic_...                 (old GA short form)
  #   - linux-image(-unsigned)?-M.m.p-<abi>-localver-generic_...               (old patch form / new GA form)
  #   - linux-image(-unsigned)?-M.m-rcN-<abi>rcN-localver-generic_...          (old RC form)
  #   - linux-image(-unsigned)?-M.m.0-<abi>rcN-localver-generic_...            (new/mainline-PPA RC form)
  #
  find "$v_packages_destination" -printf "%P\n" |
    perl -lne '
      if (/^linux-image(?:-unsigned)?-(\d+\.\d+)(?:\.(\d+)|-rc(\d+))?(?:-(\d+)(?:rc(\d+))?)?[-_]/) {
        my ($mm, $patch, $ver_rc, $abi_rc) = ($1, $2, $3, $5);
        my $rc = defined $ver_rc ? $ver_rc : $abi_rc;
        if (defined $rc)    { print "$mm-rc$rc"; }
        else                { $patch = 0 unless defined $patch; print "$mm.$patch"; }
      }
    ' |
    sort -u |
    grep -Fx "$kernel_version" ||
    true
}

# `M.m.0` versions are stored without the patch version.
#
function create_if_required_and_switch_branch {
  local building_kernel_version=$1
  building_kernel_version=$(short_kernel_version "$building_kernel_version" with_rc)

  local branch_working_copy=bv"$building_kernel_version"

  # When switching across branches for different non-patch versions, some files may be end up changed,
  # which blocks the checkout; in order to solve this, we do `--force`d checkout.
  #
  if git rev-parse --verify "$branch_working_copy" 2> /dev/null; then
    git checkout --force "$branch_working_copy"
  else
    git checkout -b "$branch_working_copy" --force v"$building_kernel_version"
  fi
}

function same_major_minor_version {
  local short_version_1 short_version_2

  short_version_1=$(short_kernel_version "$1" no_rc)
  short_version_2=$(short_kernel_version "$2" no_rc)

  [[ $short_version_1 == "$short_version_2" ]]
}

function import_config_file {
  # Always copy to .config first for modifications
  cp "$source_config_file" .config
}

# Move modified config to Ubuntu location
#
function finalize_ubuntu_config {
  echo "Finalizing config for Ubuntu packaging"
  mkdir -p debian.master/config/amd64
  mv -f .config debian.master/config/amd64/config.common.amd64
}

function annotation_set {
  _annotation_ops+=("set $1 $2")
  if [[ $2 == n ]]; then
    _disabled_configs+=("$1")
  fi
}

function annotation_undefine {
  _annotation_ops+=("remove $1")
}

function flush_annotations {
  # -B: don't write .pyc into the kernel tree (the annotations wrapper disables this too, to avoid
  # accidentally committing bytecode), since we import kconfig directly rather than via the wrapper.
  printf '%s\n' "${_annotation_ops[@]}" | PYTHONPATH=debian/scripts/misc python3 -B -c '
import sys
from kconfig.annotations import Annotation
from kconfig.utils import autodetect_annotations

fname = autodetect_annotations()
a = Annotation(fname)
for line in sys.stdin:
    op, *rest = line.split()
    if op == "set":
        a.set(rest[0], arch="amd64", value=rest[1])
    elif op == "remove":
        a.remove(rest[0], arch="amd64")
a.save(fname)
'
  _annotation_ops=()
}

function fix_ubuntu_config {
  annotation_set CONFIG_SYSTEM_TRUSTED_KEYS '""'
  annotation_set CONFIG_SYSTEM_REVOCATION_KEYS '""'
}

# Takes a lot of time, and generates a large package.
#
function disable_debug_info {
  annotation_undefine CONFIG_DEBUG_INFO
  annotation_set      CONFIG_DEBUG_INFO_NONE y
  annotation_undefine CONFIG_DEBUG_INFO_REDUCED
  annotation_undefine CONFIG_DEBUG_INFO_COMPRESSED_NONE
  annotation_undefine CONFIG_DEBUG_INFO_COMPRESSED_ZLIB
  annotation_undefine CONFIG_DEBUG_INFO_SPLIT
  annotation_undefine CONFIG_GDB_SCRIPTS
  annotation_set      CONFIG_DEBUG_INFO_DWARF5 n
  annotation_set      CONFIG_DEBUG_INFO_BTF n
}

function configure_cpu_target {
  annotation_set CONFIG_X86_NATIVE_CPU n
  export KCFLAGS="-march=$v_cpu_target -mtune=$v_cpu_target"
}

# Extracted from kernel 6.11-rc3.
#
function disable_unused_modules {
  # $1: building kernel version (e.g. 7.0.11); used to gate version-specific symbols.
  local building_version
  building_version=$(short_kernel_version "$1" no_rc)

  # DON'T FORGET TO APPLY THE UBUNTU FIXES, IF COPY/PASTING!

  # Some don't make any measurable comptime improvements, but anyway they're not used.
  #
  # On my current setup, compilation without (deb's or changes below) takes ~8'.
  #
  # To test:
  #
  #     make mrproper
  #     cp .config{.sav,}
  #     # (apply below)
  #     /usr/bin/time -f "TIME: %e" make -j $(nproc)
  #     ${SCRIPTING_ALARM_PROGRAM:-true}
  #
  annotation_set      CONFIG_CPU_SUP_HYGON n                   # exotic hw architectures...
  annotation_set      CONFIG_CPU_SUP_CENTAUR n
  annotation_set      CONFIG_CPU_SUP_ZHAOXIN n
  annotation_set      CONFIG_INTEL_TDX_HOST n                  # Intel-only confidential-VM host support
  annotation_undefine CONFIG_KVM_INTEL_TDX
  annotation_set      CONFIG_DRM_RADEON n                      # radeon...
  annotation_undefine CONFIG_DRM_RADEON_USERPTR
  annotation_set      CONFIG_DRM_AMDGPU_SI n                   # GCN 1.0 (2012)
  annotation_set      CONFIG_DRM_AMDGPU_CIK n                  # GCN 2.0 (2013-2014)
  annotation_set      CONFIG_DRM_NOUVEAU n                     # nouveau...
  annotation_undefine CONFIG_NOUVEAU_DEBUG
  annotation_undefine CONFIG_NOUVEAU_DEBUG_DEFAULT
  annotation_undefine CONFIG_NOUVEAU_DEBUG_MMU
  annotation_undefine CONFIG_NOUVEAU_DEBUG_PUSH
  annotation_undefine CONFIG_DRM_NOUVEAU_BACKLIGHT
  annotation_undefine CONFIG_DRM_NOUVEAU_SVM
  annotation_undefine CONFIG_DRM_NOUVEAU_GSP_DEFAULT
  annotation_set      CONFIG_DRM_XE n                          # intel xe...
  annotation_undefine CONFIG_DRM_GPUVM
  annotation_undefine CONFIG_DRM_XE_DISPLAY
  annotation_undefine CONFIG_DRM_XE_FORCE_PROBE
  annotation_undefine CONFIG_DRM_XE_WERROR
  annotation_undefine CONFIG_DRM_XE_DEBUG
  annotation_undefine CONFIG_DRM_XE_DEBUG_VM
  annotation_undefine CONFIG_DRM_XE_DEBUG_SRIOV
  annotation_undefine CONFIG_DRM_XE_DEBUG_MEM
  annotation_undefine CONFIG_DRM_XE_LARGE_GUC_BUFFER
  annotation_undefine CONFIG_DRM_XE_USERPTR_INVAL_INJECT
  annotation_undefine CONFIG_DRM_XE_JOB_TIMEOUT_MAX
  annotation_undefine CONFIG_DRM_XE_JOB_TIMEOUT_MIN
  annotation_undefine CONFIG_DRM_XE_TIMESLICE_MAX
  annotation_undefine CONFIG_DRM_XE_TIMESLICE_MIN
  annotation_undefine CONFIG_DRM_XE_PREEMPT_TIMEOUT
  annotation_undefine CONFIG_DRM_XE_PREEMPT_TIMEOUT_MAX
  annotation_undefine CONFIG_DRM_XE_PREEMPT_TIMEOUT_MIN
  annotation_undefine CONFIG_DRM_XE_ENABLE_SCHEDTIMEOUT_LIMIT
  annotation_set      CONFIG_DRM_MGAG200 n                     # matrox g200
  annotation_set      CONFIG_XEN n                             # xen...
  annotation_set      CONFIG_KVM_XEN n
  annotation_undefine CONFIG_PARAVIRT_XXL
  annotation_undefine CONFIG_XEN_PV
  annotation_undefine CONFIG_XEN_512GB
  annotation_undefine CONFIG_XEN_PV_SMP
  annotation_undefine CONFIG_XEN_PV_DOM0
  annotation_undefine CONFIG_XEN_PVHVM
  annotation_undefine CONFIG_XEN_PVHVM_SMP
  annotation_undefine CONFIG_XEN_PVHVM_GUEST
  annotation_undefine CONFIG_XEN_SAVE_RESTORE
  annotation_undefine CONFIG_XEN_DEBUG_FS
  annotation_undefine CONFIG_XEN_PVH
  annotation_undefine CONFIG_XEN_DOM0
  annotation_undefine CONFIG_XEN_PV_MSR_SAFE
  annotation_undefine CONFIG_PCI_XEN
  annotation_undefine CONFIG_NET_9P_XEN
  annotation_undefine CONFIG_XEN_PCIDEV_FRONTEND
  annotation_undefine CONFIG_SYS_HYPERVISOR
  annotation_undefine CONFIG_XEN_BLKDEV_FRONTEND
  annotation_undefine CONFIG_XEN_BLKDEV_BACKEND
  annotation_undefine CONFIG_XEN_SCSI_FRONTEND
  annotation_undefine CONFIG_XEN_NETDEV_FRONTEND
  annotation_undefine CONFIG_XEN_NETDEV_BACKEND
  annotation_undefine CONFIG_INPUT_XEN_KBDDEV_FRONTEND
  annotation_undefine CONFIG_HVC_IRQ
  annotation_undefine CONFIG_HVC_XEN
  annotation_undefine CONFIG_HVC_XEN_FRONTEND
  annotation_undefine CONFIG_TCG_XEN
  annotation_undefine CONFIG_XEN_WDT
  annotation_undefine CONFIG_DRM_XEN
  annotation_undefine CONFIG_DRM_XEN_FRONTEND
  annotation_undefine CONFIG_XEN_FBDEV_FRONTEND
  annotation_undefine CONFIG_SND_XEN_FRONTEND
  annotation_undefine CONFIG_USB_XEN_HCD
  annotation_undefine CONFIG_XEN_BALLOON
  annotation_undefine CONFIG_XEN_BALLOON_MEMORY_HOTPLUG
  annotation_undefine CONFIG_XEN_MEMORY_HOTPLUG_LIMIT
  annotation_undefine CONFIG_XEN_SCRUB_PAGES_DEFAULT
  annotation_undefine CONFIG_XEN_DEV_EVTCHN
  annotation_undefine CONFIG_XEN_BACKEND
  annotation_undefine CONFIG_XENFS
  annotation_undefine CONFIG_XEN_COMPAT_XENFS
  annotation_undefine CONFIG_XEN_SYS_HYPERVISOR
  annotation_undefine CONFIG_XEN_XENBUS_FRONTEND
  annotation_undefine CONFIG_XEN_GNTDEV
  annotation_undefine CONFIG_XEN_GNTDEV_DMABUF
  annotation_undefine CONFIG_XEN_GRANT_DEV_ALLOC
  annotation_undefine CONFIG_XEN_GRANT_DMA_ALLOC
  annotation_undefine CONFIG_SWIOTLB_XEN
  annotation_undefine CONFIG_XEN_PCI_STUB
  annotation_undefine CONFIG_XEN_PCIDEV_BACKEND
  annotation_undefine CONFIG_XEN_PVCALLS_FRONTEND
  annotation_undefine CONFIG_XEN_PVCALLS_BACKEND
  annotation_undefine CONFIG_XEN_SCSI_BACKEND
  annotation_undefine CONFIG_XEN_PRIVCMD
  annotation_undefine CONFIG_XEN_PRIVCMD_EVENTFD
  annotation_undefine CONFIG_XEN_ACPI_PROCESSOR
  annotation_undefine CONFIG_XEN_MCE_LOG
  annotation_undefine CONFIG_XEN_HAVE_PVMMU
  annotation_undefine CONFIG_XEN_EFI
  annotation_undefine CONFIG_XEN_AUTO_XLATE
  annotation_undefine CONFIG_XEN_ACPI
  annotation_undefine CONFIG_XEN_SYMS
  annotation_undefine CONFIG_XEN_HAVE_VPMU
  annotation_undefine CONFIG_XEN_FRONT_PGDIR_SHBUF
  annotation_undefine CONFIG_XEN_UNPOPULATED_ALLOC
  annotation_undefine CONFIG_XEN_GRANT_DMA_OPS
  annotation_undefine CONFIG_XEN_VIRTIO
  annotation_undefine CONFIG_XEN_VIRTIO_FORCE_GRANT
  # Intel Graphics
  annotation_set      CONFIG_DRM_I915 n                        # Integrated/discrete graphics (very large)
  annotation_undefine CONFIG_DRM_I915_GVT
  annotation_undefine CONFIG_DRM_I915_GVT_KVMGT
  annotation_undefine CONFIG_DRM_I915_USERPTR
  # Other GPU Drivers
  annotation_set      CONFIG_DRM_AST n                         # ASPEED server graphics
  annotation_set      CONFIG_DRM_QXL n                         # QEMU/KVM virtual GPU
  annotation_set      CONFIG_DRM_BOCHS n                       # QEMU bochs VGA
  annotation_set      CONFIG_DRM_VMWGFX n                      # VMware SVGA virtual GPU
  annotation_set      CONFIG_DRM_VIRTIO_GPU n                  # virtio GPU for VMs
  annotation_set      CONFIG_DRM_LIMA n                        # ARM Mali 400/450
  annotation_set      CONFIG_DRM_PANFROST n                    # ARM Mali Midgard/Bifrost
  annotation_set      CONFIG_DRM_ETNAVIV n                     # Vivante GPU (embedded)
  annotation_set      CONFIG_DRM_TEGRA n                       # NVIDIA Tegra (ARM)
  annotation_set      CONFIG_DRM_GMA500 n                      # Intel GMA500/600
  # VirtIO guest drivers (for when Linux runs as VM guest)
  annotation_set      CONFIG_VIRTIO_BLK n                      # VirtIO block device
  annotation_set      CONFIG_VIRTIO_NET n                      # VirtIO network
  annotation_set      CONFIG_VIRTIO_CONSOLE n                  # VirtIO console
  annotation_set      CONFIG_SCSI_VIRTIO n                     # VirtIO SCSI
  annotation_set      CONFIG_VIRTIO_BALLOON n                  # VirtIO memory balloon
  annotation_set      CONFIG_VIRTIO_INPUT n                    # VirtIO input devices
  annotation_set      CONFIG_HW_RANDOM_VIRTIO n                # VirtIO RNG
  annotation_set      CONFIG_CRYPTO_DEV_VIRTIO n               # VirtIO crypto
  annotation_set      CONFIG_VIRTIO_PMEM n                     # VirtIO persistent memory
  annotation_set      CONFIG_VIRTIO_MEM n                      # VirtIO memory hotplug
  # Intel Network Drivers
  annotation_set      CONFIG_E1000 n                           # Intel Gigabit (old)
  annotation_set      CONFIG_E1000E n                          # Intel Gigabit (newer)
  annotation_set      CONFIG_IGB n                             # Intel I350
  annotation_set      CONFIG_IXGBE n                           # Intel 10GbE
  annotation_set      CONFIG_I40E n                            # Intel 40GbE
  annotation_set      CONFIG_ICE n                             # Intel Ethernet Connection E800
  # Legacy/Old Ethernet Drivers (10/100 Mbps, 90s/2000s era)
  annotation_set      CONFIG_NET_VENDOR_3COM n                 # 3Com cards (3c59x, 3c509, etc.)
  annotation_set      CONFIG_VORTEX n                          # 3Com 3c59x
  annotation_set      CONFIG_TYPHOON n                         # 3Com Typhoon
  annotation_set      CONFIG_NET_VENDOR_AMD n                  # AMD PCnet32, etc.
  annotation_set      CONFIG_PCNET32 n                         # AMD PCnet32
  annotation_set      CONFIG_NE2000 n                          # NE2000 ISA
  annotation_set      CONFIG_NE2K_PCI n                        # NE2000 PCI
  annotation_set      CONFIG_8139TOO n                         # Realtek RTL8139 (10/100)
  annotation_set      CONFIG_8139CP n                          # Realtek RTL8139C+
  annotation_set      CONFIG_NET_VENDOR_SIS n                  # SiS 900/7016
  annotation_set      CONFIG_SIS900 n                          # SiS 900/7016
  annotation_set      CONFIG_NET_VENDOR_VIA n                  # VIA Rhine
  annotation_set      CONFIG_VIA_RHINE n                       # VIA Rhine
  annotation_set      CONFIG_NET_VENDOR_DEC n                  # DEC Tulip
  annotation_set      CONFIG_TULIP n                           # DEC 21x4x Tulip
  annotation_set      CONFIG_DE2104X n                         # DEC 21040
  annotation_set      CONFIG_NET_VENDOR_NATSEMI n              # National Semiconductor
  annotation_set      CONFIG_NATSEMI n                         # DP8381x
  annotation_set      CONFIG_FEALNX n                          # Myson MTD-8xx
  annotation_set      CONFIG_NET_VENDOR_DLINK n                # D-Link DL2000
  annotation_set      CONFIG_SUNDANCE n                        # Sundance Alta
  annotation_set      CONFIG_NET_VENDOR_SMSC n                 # SMSC LAN91C111
  annotation_set      CONFIG_SMC91X n                          # SMC 91Cxx
  annotation_set      CONFIG_NET_VENDOR_SILAN n                # Silan SC92031
  annotation_set      CONFIG_SC92031 n                         # Silan SC92031
  # Very Old WiFi Drivers Only
  annotation_set      CONFIG_IPW2100 n                         # Intel PRO/Wireless 2100 (2003)
  annotation_set      CONFIG_IPW2200 n                         # Intel PRO/Wireless 2200BG (2004)
  annotation_set      CONFIG_IWL4965 n                         # Intel Wireless WiFi 4965AGN (2007)
  annotation_set      CONFIG_IWL3945 n                         # Intel PRO/Wireless 3945ABG (2006)
  annotation_set      CONFIG_ATH5K n                           # Atheros 5xxx (pre-2010)
  annotation_set      CONFIG_ATH9K n                           # Atheros 802.11n (older)
  annotation_set      CONFIG_B43 n                             # Broadcom 43xx (old)
  annotation_set      CONFIG_B43LEGACY n                       # Broadcom 43xx legacy
  annotation_set      CONFIG_RTL8180 n                         # Realtek RTL8180/8185 (old)
  annotation_set      CONFIG_RTL8187 n                         # Realtek RTL8187/8187B (old)
  annotation_set      CONFIG_RT2400PCI n                       # Ralink rt2400 (2004)
  annotation_set      CONFIG_RT2500PCI n                       # Ralink rt2500 (2005)
  annotation_set      CONFIG_RT61PCI n                         # Ralink rt2501/rt61 (2006)
  annotation_set      CONFIG_RT2500USB n                       # Ralink rt2500 USB
  annotation_set      CONFIG_RT73USB n                         # Ralink rt2501/rt73 USB
  annotation_set      CONFIG_RT2800PCI n                       # Ralink rt2800 PCI
  annotation_set      CONFIG_RT2800USB n                       # Ralink rt2800 USB
  annotation_set      CONFIG_LIBERTAS n                        # Marvell Libertas
  # PCMCIA/CardBus (obsolete laptop tech)
  annotation_set      CONFIG_PCCARD n                          # PCMCIA/CardBus support
  annotation_set      CONFIG_PCMCIA n                          # PCMCIA support
  annotation_set      CONFIG_CARDBUS n                         # CardBus support
  # Fibre Channel (datacenter SAN storage)
  annotation_set      CONFIG_SCSI_FC_ATTRS n                   # Fibre Channel transport
  annotation_set      CONFIG_SCSI_QLOGIC_1280 n                # QLogic ISP1280
  annotation_set      CONFIG_SCSI_LPFC n                       # Emulex LightPulse FC
  annotation_set      CONFIG_SCSI_BFA_FC n                     # Brocade BFA FC
  annotation_set      CONFIG_FCOE n                            # FCoE (Fibre Channel over Ethernet)
  # Hardware RAID controllers (enterprise servers)
  annotation_set      CONFIG_MEGARAID_SAS n                    # LSI MegaRAID SAS
  annotation_set      CONFIG_SCSI_MPT3SAS n                    # LSI MPT Fusion SAS 3.0
  annotation_set      CONFIG_SCSI_MPT2SAS n                    # LSI MPT Fusion SAS 2.0
  annotation_set      CONFIG_SCSI_3W_9XXX n                    # 3ware 9xxx RAID
  annotation_set      CONFIG_SCSI_3W_SAS n                     # 3ware SAS/SATA RAID
  annotation_set      CONFIG_SCSI_AACRAID n                    # Adaptec AACRAID
  annotation_set      CONFIG_SCSI_AIC7XXX n                    # Adaptec AIC7xxx
  annotation_set      CONFIG_SCSI_AIC79XX n                    # Adaptec AIC79xx
  annotation_set      CONFIG_SCSI_ARCMSR n                     # ARECA SATA RAID
  annotation_set      CONFIG_SCSI_HPSA n                       # HP Smart Array
  annotation_set      CONFIG_SCSI_HPTIOP n                     # HighPoint RocketRAID
  annotation_set      CONFIG_SCSI_MVSAS n                      # Marvell SAS
  annotation_set      CONFIG_SCSI_MVUMI n                      # Marvell UMI
  annotation_set      CONFIG_SCSI_ESAS2R n                     # ATTO ExpressSAS
  annotation_set      CONFIG_SCSI_PM8001 n                     # PMC Sierra SAS/SATA
  # Legacy Audio Drivers (ISA/old PCI sound cards)
  annotation_set      CONFIG_SND_ISA n                         # ISA sound cards
  annotation_set      CONFIG_SND_SB8 n                         # SoundBlaster 1.0/2.0
  annotation_set      CONFIG_SND_SB16 n                        # SoundBlaster 16
  annotation_set      CONFIG_SND_SBAWE n                       # SoundBlaster AWE32/64
  annotation_set      CONFIG_SND_ES1688 n                      # ESS ES1688/ES688
  annotation_set      CONFIG_SND_ES18XX n                      # ESS ES18xx
  annotation_set      CONFIG_SND_CS4231 n                      # CS4231
  annotation_set      CONFIG_SND_CS4236 n                      # CS4232/CS4236+
  annotation_set      CONFIG_SND_OPL3SA2 n                     # Yamaha OPL3-SA2/SA3
  annotation_set      CONFIG_SND_AD1816A n                     # AD1816A
  annotation_set      CONFIG_SND_ALS100 n                      # Avance Logic ALS100/ALS120
  annotation_set      CONFIG_SND_AZT2320 n                     # Aztech AZT2320
  annotation_set      CONFIG_SND_CMI8330 n                     # C-Media CMI8330
  annotation_set      CONFIG_SND_ENS1370 n                     # Ensoniq ES1370 (old)
  annotation_set      CONFIG_SND_ENS1371 n                     # Ensoniq ES1371 (old)
  annotation_set      CONFIG_SND_FM801 n                       # ForteMedia FM801
  annotation_set      CONFIG_SND_YMFPCI n                      # Yamaha YMF7xx PCI
  annotation_set      CONFIG_SND_CMIPCI n                      # C-Media CMI8338/8738
  annotation_set      CONFIG_SND_ALS300 n                      # Avance Logic ALS300
  annotation_set      CONFIG_SND_ALS4000 n                     # Avance Logic ALS4000
  annotation_set      CONFIG_SND_ALI5451 n                     # ALi M5451 PCI
  annotation_set      CONFIG_SND_ATIIXP n                      # ATI IXP AC97
  annotation_set      CONFIG_SND_ATIIXP_MODEM n                # ATI IXP Modem
  annotation_set      CONFIG_SND_AU8810 n                      # Aureal Advantage
  annotation_set      CONFIG_SND_AU8820 n                      # Aureal Vortex
  annotation_set      CONFIG_SND_AU8830 n                      # Aureal Vortex 2
  annotation_set      CONFIG_SND_BT87X n                       # Bt87x audio
  annotation_set      CONFIG_SND_CA0106 n                      # Creative SB Audigy LS/Live 24bit
  annotation_set      CONFIG_SND_CS4281 n                      # Cirrus Logic CS4281
  annotation_set      CONFIG_SND_CS46XX n                      # Cirrus Logic CS46xx
  annotation_set      CONFIG_SND_EMU10K1 n                     # Creative SB Live!/Audigy (old)
  annotation_set      CONFIG_SND_EMU10K1X n                    # Creative SB Live! Dell OEM
  annotation_set      CONFIG_SND_MAESTRO3 n                    # ESS Allegro/Maestro3
  annotation_set      CONFIG_SND_TRIDENT n                     # Trident 4D-Wave
  annotation_set      CONFIG_SND_VIA82XX n                     # VIA 82Cxxx AC97
  annotation_set      CONFIG_SND_VIA82XX_MODEM n               # VIA 82Cxxx Modem
  annotation_set      CONFIG_SND_VIRTUOSO n                    # Asus Virtuoso (old)
  # Hyper-V
  annotation_set      CONFIG_HYPERV n                          # Microsoft Hyper-V
  # InfiniBand/RDMA
  annotation_set      CONFIG_INFINIBAND n                      # InfiniBand support
  annotation_set      CONFIG_INFINIBAND_IPOIB n
  # Network filesystems (keeping CIFS for SMB)
  annotation_set      CONFIG_NFS_FS n
  annotation_set      CONFIG_NFSD n
  annotation_set      CONFIG_CODA_FS n
  annotation_set      CONFIG_AFS_FS n
  # Exotic filesystems (keeping ext4, btrfs, vfat, fuse, squashfs, ntfs3)
  annotation_set      CONFIG_XFS_FS n
  annotation_set      CONFIG_F2FS_FS n
  annotation_set      CONFIG_JFS_FS n
  annotation_set      CONFIG_NTFS_FS n                         # Legacy driver
  annotation_set      CONFIG_OCFS2_FS n
  annotation_set      CONFIG_GFS2_FS n
  annotation_set      CONFIG_NILFS2_FS n
  annotation_set      CONFIG_EROFS_FS n
  annotation_set      CONFIG_UBIFS_FS n
  annotation_set      CONFIG_CRAMFS n
  # Datacenter/specialty hardware
  annotation_set      CONFIG_IIO n                             # Industrial I/O sensors
  annotation_set      CONFIG_USB4 n                            # Thunderbolt/USB4 (was CONFIG_THUNDERBOLT)
  annotation_set      CONFIG_NVME_TARGET n                     # NVMe over Fabrics (datacenter)
  annotation_set      CONFIG_NVME_TCP n
  annotation_set      CONFIG_NVME_RDMA n
  # Staging drivers (experimental)
  annotation_set      CONFIG_STAGING n

  # ==== Additions for 7.0/7.1 on this machine (9950X3D iGPU + RTX 5090, Realtek 2.5G NIC, ====
  # ==== NVMe/SATA, HDA + USB audio, USB webcam, Bluetooth dongle/onboard; no WiFi) ============
  #
  # GPU note: nouveau already off above; nvidia-open is out-of-tree (no in-tree CONFIG), and
  # amdgpu stays for the 9950X3D iGPU. No GPU config change is needed for the RTX 5090.

  # Wired NIC vendors: keep only REALTEK (r8169 / RTL8126a). Gate off cascades to all drivers.
  annotation_set      CONFIG_NET_VENDOR_ADAPTEC n
  annotation_set      CONFIG_NET_VENDOR_ADI n
  annotation_set      CONFIG_NET_VENDOR_AGERE n
  annotation_set      CONFIG_NET_VENDOR_ALACRITECH n
  annotation_set      CONFIG_NET_VENDOR_AMAZON n
  annotation_set      CONFIG_NET_VENDOR_AQUANTIA n
  annotation_set      CONFIG_NET_VENDOR_ARC n
  annotation_set      CONFIG_NET_VENDOR_ASIX n
  annotation_set      CONFIG_NET_VENDOR_ATHEROS n
  annotation_set      CONFIG_NET_VENDOR_BROADCOM n
  annotation_set      CONFIG_NET_VENDOR_BROCADE n
  annotation_set      CONFIG_NET_VENDOR_CADENCE n
  annotation_set      CONFIG_NET_VENDOR_CAVIUM n
  annotation_set      CONFIG_NET_VENDOR_CHELSIO n
  annotation_set      CONFIG_NET_VENDOR_CISCO n
  annotation_set      CONFIG_NET_VENDOR_CORTINA n
  annotation_set      CONFIG_NET_VENDOR_DAVICOM n
  annotation_set      CONFIG_NET_VENDOR_EMULEX n
  annotation_set      CONFIG_NET_VENDOR_ENGLEDER n
  annotation_set      CONFIG_NET_VENDOR_EZCHIP n
  annotation_set      CONFIG_NET_VENDOR_FUNGIBLE n
  annotation_set      CONFIG_NET_VENDOR_GOOGLE n
  annotation_set      CONFIG_NET_VENDOR_HUAWEI n
  annotation_set      CONFIG_NET_VENDOR_I825XX n
  annotation_set      CONFIG_NET_VENDOR_INTEL n
  annotation_set      CONFIG_NET_VENDOR_LITEX n
  annotation_set      CONFIG_NET_VENDOR_MARVELL n
  annotation_set      CONFIG_NET_VENDOR_MELLANOX n
  annotation_set      CONFIG_NET_VENDOR_META n
  annotation_set      CONFIG_NET_VENDOR_MICREL n
  annotation_set      CONFIG_NET_VENDOR_MICROCHIP n
  annotation_set      CONFIG_NET_VENDOR_MICROSEMI n
  annotation_set      CONFIG_NET_VENDOR_MICROSOFT n
  annotation_set      CONFIG_NET_VENDOR_MUCSE n
  annotation_set      CONFIG_NET_VENDOR_MYRI n
  annotation_set      CONFIG_NET_VENDOR_NETRONOME n
  annotation_set      CONFIG_NET_VENDOR_NI n
  annotation_set      CONFIG_NET_VENDOR_NVIDIA n
  annotation_set      CONFIG_NET_VENDOR_OKI n
  annotation_set      CONFIG_NET_VENDOR_PENSANDO n
  annotation_set      CONFIG_NET_VENDOR_QLOGIC n
  annotation_set      CONFIG_NET_VENDOR_QUALCOMM n
  annotation_set      CONFIG_NET_VENDOR_RDC n
  annotation_set      CONFIG_NET_VENDOR_RENESAS n
  annotation_set      CONFIG_NET_VENDOR_ROCKER n
  annotation_set      CONFIG_NET_VENDOR_SAMSUNG n
  annotation_set      CONFIG_NET_VENDOR_SEEQ n
  annotation_set      CONFIG_NET_VENDOR_SOCIONEXT n
  annotation_set      CONFIG_NET_VENDOR_SOLARFLARE n
  annotation_set      CONFIG_NET_VENDOR_STMICRO n
  annotation_set      CONFIG_NET_VENDOR_SUN n
  annotation_set      CONFIG_NET_VENDOR_SYNOPSYS n
  annotation_set      CONFIG_NET_VENDOR_TEHUTI n
  annotation_set      CONFIG_NET_VENDOR_TI n
  annotation_set      CONFIG_NET_VENDOR_VERTEXCOM n
  annotation_set      CONFIG_NET_VENDOR_WANGXUN n
  annotation_set      CONFIG_NET_VENDOR_WIZNET n
  annotation_set      CONFIG_NET_VENDOR_XILINX n
  # SCSI-over-Ethernet offload selects the Broadcom/Chelsio gates above; disable it so they
  # actually take effect (datacenter-only anyway).
  annotation_set      CONFIG_SCSI_BNX2X_FCOE n                 # Broadcom FCoE offload
  annotation_set      CONFIG_SCSI_BNX2_ISCSI n                 # Broadcom iSCSI offload
  annotation_set      CONFIG_SCSI_CXGB3_ISCSI n                # Chelsio T3 iSCSI offload
  annotation_set      CONFIG_SCSI_CXGB4_ISCSI n                # Chelsio T4 iSCSI offload

  # WiFi: unused on this machine (Bluetooth is independent and stays enabled). CFG80211 off
  # cascades to the whole 802.11 stack and every WLAN_VENDOR_* driver (~150 modules).
  annotation_set      CONFIG_WLAN n
  annotation_set      CONFIG_CFG80211 n
  annotation_set      CONFIG_MAC80211 n

  # Media: keep USB webcam (UVC) + HDMI CEC; drop analog TV / DVB / radio / SDR / PCI capture.
  annotation_set      CONFIG_MEDIA_ANALOG_TV_SUPPORT n
  annotation_set      CONFIG_MEDIA_DIGITAL_TV_SUPPORT n        # drops DVB_CORE + all frontends
  annotation_set      CONFIG_MEDIA_RADIO_SUPPORT n
  annotation_set      CONFIG_MEDIA_SDR_SUPPORT n
  annotation_set      CONFIG_MEDIA_PCI_SUPPORT n               # no PCI capture card

  # Buses absent from this board
  annotation_set      CONFIG_CAN n                             # CAN bus (automotive)
  annotation_set      CONFIG_FIREWIRE n                        # IEEE-1394
  annotation_set      CONFIG_SND_FIREWIRE n                    # FireWire audio
  annotation_set      CONFIG_ATM n                             # ATM networking
  annotation_set      CONFIG_WAN n                             # legacy sync-serial WAN
  annotation_set      CONFIG_GPIB n                            # lab instrument bus (GPIB/IEEE-488)
  annotation_set      CONFIG_MEMSTICK n                        # Sony Memory Stick

  # Pluggable peripherals not used (USB tethering via cdc_ether/rndis is kept)
  annotation_set      CONFIG_MMC n                             # no SD/MMC reader
  annotation_set      CONFIG_USB_SERIAL n                      # FTDI/CP210x/CH341 adapters
  annotation_set      CONFIG_USB_NET_AX8817X n                 # ASIX USB-Ethernet dongles
  annotation_set      CONFIG_USB_NET_AX88179_178A n            # ASIX USB-Ethernet (newer)
  annotation_set      CONFIG_PARPORT n                         # parallel port (printer is USB)

  # Platforms/buses this desktop will never be
  annotation_set      CONFIG_X86_EXTENDED_PLATFORM n           # non-PC x86 (SGI UV, Intel MID, ...)
  annotation_set      CONFIG_RAPIDIO n                         # datacenter interconnect
  annotation_set      CONFIG_AGP n                             # legacy AGP bus (PCIe now)
  annotation_set      CONFIG_FUSION n                          # old LSI Fusion-MPT
  annotation_set      CONFIG_MACINTOSH_DRIVERS n               # Apple Mac hardware
  annotation_set      CONFIG_CHROME_PLATFORMS n                # ChromeOS embedded controllers
  annotation_set      CONFIG_SURFACE_PLATFORMS n               # MS Surface devices
  annotation_set      CONFIG_COMEDI n                          # lab data-acquisition cards
  # Linux-as-guest paravirt; this kernel never boots inside a VM. VMware/VBox/QEMU+VFIO run as
  # HOSTS and are unaffected (VFIO/KVM/VHOST/VMCI/IOMMU all stay enabled).
  annotation_set      CONFIG_HYPERVISOR_GUEST n
  annotation_set      CONFIG_WWAN n                            # cellular modems
  annotation_set      CONFIG_NFC n                             # near-field comm
  annotation_set      CONFIG_INPUT_TOUCHSCREEN n               # no touchscreen
  annotation_set      CONFIG_INPUT_TABLET n                    # old serial tablets (USB Wacom is HID)
  # Other-vendor laptop platform drivers (this is an MSI desktop)
  annotation_set      CONFIG_THINKPAD_ACPI n
  annotation_set      CONFIG_DELL_LAPTOP n
  annotation_set      CONFIG_DELL_WMI n
  annotation_set      CONFIG_HP_ACCEL n
  annotation_set      CONFIG_HP_WMI n
  annotation_set      CONFIG_ASUS_LAPTOP n
  annotation_set      CONFIG_ASUS_WMI n
  annotation_set      CONFIG_EEEPC_LAPTOP n
  annotation_set      CONFIG_SONY_LAPTOP n
  annotation_set      CONFIG_FUJITSU_LAPTOP n
  annotation_set      CONFIG_SAMSUNG_LAPTOP n
  annotation_set      CONFIG_LG_LAPTOP n
  annotation_set      CONFIG_PANASONIC_LAPTOP n
  annotation_set      CONFIG_ACER_WMI n
  annotation_set      CONFIG_SYSTEM76_ACPI n

  # Removed in 7.1: only annotate when building <= 7.0, otherwise these are dead no-ops.
  if dpkg --compare-versions "$building_version" lt 7.1; then
    annotation_set    CONFIG_HAMRADIO n                        # Amateur Radio (gone in 7.1)
    annotation_set    CONFIG_ISDN n                            # Legacy telephony (gone in 7.1)
  fi
}

# Verify that the disables actually took effect, before the (long) compilation starts.
#
# The Ubuntu build skips `annotations --check` (do_mainline_build forces do_skip_checks), so a
# disabled option that another option `select`s back on would slip through silently. Here we
# resolve a throwaway .config from the (modified) annotations and report only options annotated
# 'n' that came back as 'y'/'m'. Orphaned children (annotated m/y, resolved to absent) are the
# expected result of disabling a parent gate and are ignored.
#
function verify_disabled_modules {
  local check_dir
  check_dir=$(mktemp -d)

  python3 debian/scripts/misc/annotations --arch amd64 --export > "$check_dir/.config"
  make O="$check_dir" olddefconfig > /dev/null

  # Restrict to the options we disabled (--check reports every n→y/m flip, including stock-n
  # annotations the build legitimately forces on).
  local overridden
  overridden=$(python3 debian/scripts/misc/annotations --arch amd64 --check "$check_dir/.config" 2>/dev/null \
    | grep -E 'changed from n to [ym]' \
    | grep -Fw -f <(printf '%s\n' "${_disabled_configs[@]}") || true)

  rm -rf "$check_dir"

  if [[ -n $overridden ]]; then
    >&2 echo "WARNING: these disabled options were forced back on (selected by another option):"
    >&2 echo "$overridden"
    if [[ -n $v_unattended ]]; then
      >&2 echo 'Unattended build aborted because disabled options were forced on.'
      exit 1
    fi
    local reply
    read -rp "Continue with the build anyway? [y/N] " reply
    if [[ $reply != [yY] ]]; then
      >&2 echo "Build aborted."
      exit 1
    fi
  fi
}

# $v_sav_remote can be empty, in which case no replay is performed. The sav branch name is composed
# from the target version as '<remote>/v<M.m>-sav', so it follows the version automatically. Replays
# the commits unique to that branch (merge-base..branch) onto the target version's tag with
# `git rebase --onto`, landing them on $c_cherry_pick_branch so the exit hook cleans them up. rebase
# performs the 3-way merge, drops commits already present upstream, and aborts loudly on a genuine
# conflict.
#
function apply_sav_branch {
  if [[ -n $v_sav_remote ]]; then
    local version_tag series sav_branch merge_base
    version_tag=v$(short_kernel_version "$1" with_rc)
    series=$(short_kernel_version "$1" no_rc)
    sav_branch="$v_sav_remote/v$series-sav"
    merge_base=$(git merge-base "$version_tag" "$sav_branch")

    # Refuse to adopt (and later delete) a branch this run didn't create.
    if git rev-parse --verify "$c_cherry_pick_branch" >/dev/null 2>&1; then
      >&2 echo "Branch '$c_cherry_pick_branch' already exists; remove it manually if it's stale."
      exit 1
    fi

    echo "# REPLAY sav branch $sav_branch onto $version_tag ##########"
    git checkout -b "$c_cherry_pick_branch" "$sav_branch"
    v_cherry_pick_branch_created=1

    # Pin an identity and disable signing so the replay does not depend on the caller's git config.
    git \
      -c user.name='64kramsystem' \
      -c user.email='64kramsystem@users.noreply.github.com' \
      -c commit.gpgsign=false \
      rebase --onto "$version_tag" "$merge_base"
  fi
}

function verify_or_setup_ubuntu_packaging {
  local running_kernel_version=$1

  # Check if we have a complete debian.master setup (not just changelog)
  if [[ -f debian.master/changelog && -f debian.master/rules.d/amd64.mk && -d debian.master/config ]]; then
    >&2 echo "Found existing debian.master directory (Ubuntu kernel tree)"
    return
  fi

  # Remove incomplete debian directories and extract fresh from crack.bundle
  rm -rf debian.master debian

  >&2 echo "Downloading Ubuntu packaging from mainline PPA"

  # Find the latest version to get packaging from (for the running kernel major.minor)
  local packaging_version
  packaging_version=$(find_ppa_kernel_versions "$running_kernel_version" | head -n 1)

  >&2 echo "Using packaging from v${packaging_version}"

  # Download crack.bundle
  local bundle_path
  bundle_path=$(download_crack_bundle "$packaging_version")

  # Extract debian directories
  extract_debian_from_crack_bundle "$bundle_path"
}

# Generate Ubuntu-style ABI number (e.g., 060100 for 6.1.0, 061000rc1 for 6.10.0-rc1)
function generate_abi_number {
  local version=$1

  version=${version#v}

  if [[ $version =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    # GA version: 6.1.0 -> 060100
    printf "%02d%02d%02d" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
  elif [[ $version =~ ^([0-9]+)\.([0-9]+)-rc([0-9]+)$ ]]; then
    # RC version: 6.10-rc1 -> 061000rc1
    printf "%02d%02d00rc%d" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
  elif [[ $version =~ ^([0-9]+)\.([0-9]+)$ ]]; then
    # Short version: 6.1 -> 060100
    printf "%02d%02d00" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  else
    >&2 echo "Error: Cannot parse version for ABI number: $version"
    exit 1
  fi
}

# Build the source package version string used in debian/changelog entries.
#
# $1: normalized kernel version (X.Y.Z or X.Y-rcN)
# $2: local version suffix (may be empty)
# $3: deb timestamp (e.g., YYYYMMDDHHMM)
#
# Format: <upstream>-<abi>[-<localver>].<timestamp>
#
# Matches Ubuntu mainline PPA convention (https://kernel.ubuntu.com/mainline/):
# the upstream part is always X.Y.Z (with Z=0 for the initial release), for
# both GA and RC; the RC marker is encoded only inside the ABI (e.g.,
# 070000rc7), never as a segment between upstream and ABI. That keeps GA
# releases sorted above the corresponding RCs under GRUB's version_sort.
function mainline_package_version {
  local kernel_version=$1 local_version=$2 debversion=$3

  local upstream
  if [[ $kernel_version =~ ^([0-9]+\.[0-9]+)-rc[0-9]+$ ]]; then
    upstream="${BASH_REMATCH[1]}.0"
  else
    upstream=$kernel_version
  fi

  local abinum
  abinum=$(generate_abi_number "$kernel_version")

  echo -n "${upstream}-${abinum}${local_version:+-$local_version}.${debversion}"
}

# The kernel packaging templates invoke run-parts with two directories, which debianutils supports
# from 5.23 (Ubuntu 26.04); older releases (e.g. Noble's 5.17) accept a single directory only, so
# there the maintainer script invocations must be patched.
#
function run_parts_accepts_multiple_directories {
  local dir_1 dir_2 exit_status=0
  dir_1=$(mktemp -d)
  dir_2=$(mktemp -d)
  run-parts --list "$dir_1" "$dir_2" > /dev/null 2>&1 || exit_status=$?
  rmdir "$dir_1" "$dir_2"
  return "$exit_status"
}

function fix_run_parts_two_directory_invocations {
  python3 - <<'PYEOF'
import pathlib

p = pathlib.Path('debian/templates/image.preinst.in')
if p.exists():
    old = ('if [ -d /etc/kernel/preinst.d ] || [ -d /usr/share/kernel/preinst.d ]; then\n'
           '    DEB_MAINT_PARAMS="$*" run-parts --report --exit-on-error --arg=$version \\\n'
           '        --arg=$image_path /etc/kernel/preinst.d /usr/share/kernel/preinst.d\n'
           'fi')
    new = ('for _kd in /etc/kernel/preinst.d /usr/share/kernel/preinst.d; do\n'
           '    if [ -d "$_kd" ]; then\n'
           '        DEB_MAINT_PARAMS="$*" run-parts --report --exit-on-error --arg=$version --arg=$image_path "$_kd"\n'
           '    fi\n'
           'done')
    content = p.read_text()
    if old in content:
        p.write_text(content.replace(old, new))
        print(f'  Patched run-parts two-directory invocation in {p}')
PYEOF
}

function setup_ubuntu_packaging {
  echo "Setting up Ubuntu packaging for $building_kernel_version"

  local debversion
  debversion=$(date +%Y%m%d%H%M)

  local source_version
  source_version=$(mainline_package_version "$building_kernel_version" "$v_local_version" "$debversion")

  echo "  Source version: $source_version"

  local ubuntu_series
  ubuntu_series=$(lsb_release -cs)

  # Modify changelog - keep source package as "linux" (no renaming for simplicity)
  # Handle both GA format (6.19.0-061900.timestamp) and RC format (6.19.0-061900rc8.timestamp)
  sed -i -re "s/(^linux) \(([0-9]+\.[0-9]+\.[0-9]+)-([0-9]+)(rc[0-9]+)?\.[0-9]+\) ([^;]*)(.*)/linux (${source_version}) ${ubuntu_series}\6/" debian.master/changelog

  # Update dwarves dependency
  sed -i -re 's/dwarves \[/dwarves (>=1.21) \[/g' debian.master/control.stub.in

  # Remove ZFS modules dependency - not built in mainline builds (introduced in 7.0-rc7)
  sed -i -re 's/, linux-main-modules-zfs-\S+ \[[^]]+\]//' debian.master/control.d/flavour-control.stub

  # Fix run-parts two-directory invocation (introduced in 7.0-rc7) where the system run-parts only
  # accepts one directory
  if ! run_parts_accepts_multiple_directories; then
    python3 - <<'PYEOF'
import pathlib

def patch(path, old, new):
    content = path.read_text()
    patched = content.replace(old, new)
    if patched != content:
        path.write_text(patched)
        print(f'  Patched run-parts two-directory invocation in {path}')

p = pathlib.Path('debian/templates/headers.postinst.in')
if p.exists():
    old = ('if [ -d /etc/kernel/header_postinst.d ] || [ -d /usr/share/kernel/header_postinst.d ]; then\n'
           '    DEB_MAINT_PARAMS="$*" run-parts --report --exit-on-error --arg=$version \\\n'
           '        /etc/kernel/header_postinst.d /usr/share/kernel/header_postinst.d\n'
           'fi')
    new = ('for _kd in /etc/kernel/header_postinst.d /usr/share/kernel/header_postinst.d; do\n'
           '    if [ -d "$_kd" ]; then\n'
           '        DEB_MAINT_PARAMS="$*" run-parts --report --exit-on-error --arg=$version "$_kd"\n'
           '    fi\n'
           'done')
    patch(p, old, new)

for fname, img in [('image.postinst.in', '$image_path'), ('extra.postinst.in', '"$image_path"')]:
    p = pathlib.Path(f'debian/templates/{fname}')
    if p.exists():
        old = (f'DEB_MAINT_PARAMS="$*" run-parts --report --exit-on-error --arg=$version \\\n'
               f'    --arg={img} /etc/kernel/postinst.d /usr/share/kernel/postinst.d')
        # this run-parts call is inside an unquoted heredoc (the dpkg trigger script), so $_kd must
        # be escaped to survive until the trigger runs
        new = ('for _kd in /etc/kernel/postinst.d /usr/share/kernel/postinst.d; do\n'
               '    if [ -d "\\$_kd" ]; then\n'
               '        DEB_MAINT_PARAMS="$*" run-parts --report --exit-on-error --arg=$version --arg=$image_path "\\$_kd"\n'
               '    fi\n'
               'done')
        patch(p, old, new)

p = pathlib.Path('debian/templates/image.postrm.in')
if p.exists():
    old = ('    DEB_MAINT_PARAMS="$*" run-parts --report --exit-on-error --arg=$version \\\n'
           '        --arg=$image_path /etc/kernel/postrm.d /usr/share/kernel/postrm.d')
    new = ('    for _kd in /etc/kernel/postrm.d /usr/share/kernel/postrm.d; do\n'
           '        if [ -d "$_kd" ]; then\n'
           '            DEB_MAINT_PARAMS="$*" run-parts --report --exit-on-error --arg=$version --arg=$image_path "$_kd"\n'
           '        fi\n'
           '    done')
    patch(p, old, new)

p = pathlib.Path('debian/templates/image.prerm.in')
if p.exists():
    old = ('if [ -d /etc/kernel/prerm.d ] || [ -d /usr/share/kernel/prerm.d ]; then\n'
           '    DEB_MAINT_PARAMS="$*" run-parts --report --exit-on-error --arg=$version \\\n'
           '        --arg=$image_path /etc/kernel/prerm.d /usr/share/kernel/prerm.d\n'
           'fi')
    new = ('for _kd in /etc/kernel/prerm.d /usr/share/kernel/prerm.d; do\n'
           '    if [ -d "$_kd" ]; then\n'
           '        DEB_MAINT_PARAMS="$*" run-parts --report --exit-on-error --arg=$version --arg=$image_path "$_kd"\n'
           '    fi\n'
           'done')
    patch(p, old, new)
PYEOF

    fix_run_parts_two_directory_invocations
  fi

  # Don't fail if we find no *.ko files in the build dir
  sed -i -re 's/zstd -19 --quiet --rm/zstd -19 --rm || true/g' debian/rules.d/2-binary-arch.mk || true

  echo "  Applying adjustments"

  sed -i -rE "1s/^gcc:=.*/gcc:=$v_gcc_package/" debian/rules.d/0-common-vars.mk
  sed -i -rE "s/export gcc\?=.*/export gcc?=$v_gcc_package/" debian/rules.d/0-common-vars.mk
  sed -i -rE "s/gcc-[[:digit:]]+/$v_gcc_package/g" debian.master/control.stub.in

  # Note: We don't modify amd64.mk here. Instead, we pass do_mainline_build=true
  # and do_tools=0 on the command line when calling debian/rules, which overrides
  # any settings in .mk files. This matches how the mainline PPA builds kernels.
}

# Run Ubuntu's config preparation
#
# The kernel packaging calls run-parts with two directories, which debianutils supports only from
# 5.23 (Resolute). Noble ships 5.17, where that form fails at install time on the client, so the
# templates are patched to call run-parts once per directory. That patch is an exact-string
# replacement which silently does nothing once upstream restructures the text, so check the
# deliverable instead of trusting the patch. This is deliberately not fatal on a merely unfamiliar
# template: it fails only on the form that is known to break.
function verify_single_directory_run_parts {
  [[ -d debian/templates ]] || return 0

  local offending
  # The $-expressions in the perl program are perl's, not the shell's.
  # shellcheck disable=SC2016
  offending=$(
    find debian/templates -maxdepth 1 -name "*.in" -print0 |
      xargs -0 -r perl -0777 -ne '
        # Join backslash-continued lines first: the two directories usually sit on the continuation.
        s/\\\n\s*/ /g;
        for my $line (split /\n/, $_) {
          # extra.postrm.in keeps a commented-out copy of the postinst trigger, two directories and
          # all; it never runs, so it must not fail the build.
          next if $line =~ /^\s*#/;
          next unless $line =~ /\brun-parts\b/;
          my @directories = $line =~ m{\s(/\S+)}g;
          print "$ARGV: $line\n" if @directories > 1;
        }
      '
  )

  if [[ -n $offending ]]; then
    >&2 echo "Packaging calls run-parts with more than one directory; that fails on debianutils 5.17:"
    >&2 printf "%s\n" "$offending"
    return 1
  fi
}

function prepare_ubuntu_build {
  echo "Preparing Ubuntu kernel build environment"

  # Modify annotations to only include amd64 architecture
  sed -i -e 's/^# ARCH: .*/# ARCH: amd64/' \
         -e 's/^# FLAVOUR: .*/# FLAVOUR: amd64-generic/' \
         debian.master/config/annotations

  mkdir -p debian.master/etc
  echo 'archs="amd64"' > debian.master/etc/kernelconfig
  fakeroot debian/rules clean defaultconfigs
}

function compile_kernel {
  echo "Building kernel with Ubuntu mainline method (debian/rules targets)"

  # Enable ccache
  export PATH="/usr/lib/ccache:$PATH"
  export KBUILD_BUILD_TIMESTAMP=''

  # Mainline PPA flags: disable tools, extras, rust-lib; enable mainline mode
  local build_flags=(do_mainline_build=true do_extras_package=false do_tools=0 do_lib_rust=false no_dumpfile=1)

  # Work around fakeroot+lchown incompatibility on newer kernels (6.19+) where
  # lchown fails with EINVAL under fakeroot's LD_PRELOAD. This causes cpio
  # and cp -a to return errors despite actually copying files correctly.
  #
  sed -i \
    -e 's/cpio -pd --preserve-modification-time/& --no-preserve-owner/g' \
    -e 's/cp -a /cp -r --no-preserve=ownership /g' \
    debian/rules.d/3-binary-indep.mk

  # Clean
  fakeroot debian/rules clean

  # Build headers
  fakeroot debian/rules do_tools=0 no_dumpfile=1 binary-headers

  # Build kernel (yes '' auto-answers prompts)
  # The 'yes' command will receive SIGPIPE when build-arch closes stdin, so we ignore that error
  (yes '' || test $? -eq 141) | debian/rules "${build_flags[@]}" build-arch

  # Package into .deb files
  fakeroot debian/rules "${build_flags[@]}" binary-debs

  # Remove extra packages that mainline PPA doesn't publish.
  #
  # The Ubuntu debian/rules (extracted from crack.bundle) creates these additional packages:
  # - linux-buildinfo-*: Build metadata (config, ABI, modules list, compiler info).
  # - linux-lib-rust-*: Rust kernel library support (even with do_lib_rust=false).
  #
  # The mainline PPA build DOES create these packages (visible in build logs), but the
  # mainline-build infrastructure filters them out and only publishes 4 packages:
  #   1. linux-headers-*_all.deb
  #   2. linux-headers-*-generic_amd64.deb
  #   3. linux-image-unsigned-*-generic_amd64.deb
  #   4. linux-modules-*-generic_amd64.deb
  #
  # We delete the extras to match the published mainline PPA package set.
  rm -f ../linux-buildinfo-*.deb ../linux-lib-rust-*.deb
}

function remove_destination_old_version_files {
  local raw_version=$1 source_config_file=$2

  local short_version
  short_version=$(short_kernel_version "$raw_version" no_rc)

  # Note that at least one configuration is necessarily present, but not the packages.

  if [[ -z $v_bisect ]]; then
    # This is actually redundant, although by using the basename, we make this logic more robust.
    #
    local config_basename
    config_basename=$(basename "$source_config_file")

    # Sample filenames (GA configs are stored in short form, without the .0 patch):
    #
    # - config-6.9
    # - config-6.10-rc2
    #
    # Ignore configurations that don't follow the convention, so that they can be used for other purposes,
    # e.g. reference/backup.
    #
    find "$v_packages_destination" -regextype egrep -not -name "$config_basename" -regex ".*/config-$short_version(\.|-rc)[[:digit:]]+" -exec rm {} \;
  fi

  # Sample filenames (mainline-style packages):
  #
  # - linux-headers-6.19-061900-mybuild_6.19-061900-mybuild.202602091928_all.deb
  # - linux-image-unsigned-6.19-061900-mybuild-generic_6.19-061900-mybuild.202602091928_amd64.deb
  # - linux-modules-6.19-061900-mybuild-generic_6.19-061900-mybuild.202602091928_amd64.deb
  #
  find "$v_packages_destination" -regextype egrep -regex ".*/.+[-_]$short_version.+\.deb" -exec rm {} \;
}

function move_packages_and_cleanup {
  local normalized_version=$1

  local short_version
  short_version=$(short_kernel_version "$normalized_version" no_rc)

  # Move only the packages for the version just built. A blanket `mv ../*.deb` would also sweep in
  # unrelated/stale .debs sitting in the parent directory, which could then be reported on FD 3 or
  # installed. See find_built_packages() for the filename pattern.
  #
  find .. -maxdepth 1 -name "linux-*[-_]$short_version*-*.deb" -exec mv -t "$v_packages_destination"/ {} +
}

# Output the package filenames, newline-separated.
#
function find_built_packages {
  local normalized_version=$1

  local short_version
  short_version=$(short_kernel_version "$normalized_version" no_rc)

  # See remove_destination_old_version_files() for the filenames format.
  # Pattern matches: linux-headers-6.19-061900-mybuild_6.19-061900-mybuild.202602091928_all.deb
  #
  find "$v_packages_destination" -name "linux-*[-_]$short_version*-*.deb"
}

# Sends only if the FD is open/valid.
#
# $1: see find_built_packages().
#
function send_built_packages_to_fd3 {
  if { true >&3; } 2>/dev/null; then
    echo -n "$1" >&3
  fi
}
