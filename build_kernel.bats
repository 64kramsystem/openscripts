#!/usr/bin/env bats

setup_file() {
  source "$BATS_TEST_DIRNAME/build_kernel"
  export -f find_latest_packaged_version short_kernel_version
  export -f mainline_package_version generate_abi_number
  export -f annotation_set annotation_undefine
  export -f find_running_kernel_version normalize_kernel_version
  export -f find_local_config_file_for_version
}

teardown_file() {
  rm -f "$c_crack_bundle_temp_file"
}

setup() {
  export v_packages_destination
  v_packages_destination=$(mktemp -d)
}

teardown() {
  rm -rf "$v_packages_destination"
}

# ── Helpers ───────────────────────────────────────────────────────────────────

make_pkg() {
  touch "$v_packages_destination/$1"
}

# Real-world filename formats:
#   linux-image-unsigned-7.0-rc3-070000rc3-sav-generic_7.0-rc3-070000rc3-sav.202603112040_amd64.deb
#   linux-image-unsigned-6.19.6-061906-sav-generic_6.19.6-061906-sav.202603052259_amd64.deb
#   linux-image-unsigned-6.19-061900-sav-generic_6.19-061900-sav.202601010000_amd64.deb  (GA/.0 version)

# ── RC versions ───────────────────────────────────────────────────────────────

@test "rc3 present → returns rc3" {
  make_pkg "linux-image-unsigned-7.0-rc3-070000rc3-sav-generic_7.0-rc3-070000rc3-sav.202603112040_amd64.deb"
  run find_latest_packaged_version "7.0-rc3"
  [ "$output" = "7.0-rc3" ]
}

@test "rc3 queried, only 7.0.0-rc3-named package present → empty (regression: old code matched this)" {
  make_pkg "linux-image-unsigned-7.0.0-rc3-070000rc3-sav-generic_7.0.0-rc3-070000rc3-sav.202603112040_amd64.deb"
  run find_latest_packaged_version "7.0-rc3"
  [ "$output" = "" ]
}

@test "rc2 queried, only rc3 present → empty" {
  make_pkg "linux-image-unsigned-7.0-rc3-070000rc3-sav-generic_7.0-rc3-070000rc3-sav.202603112040_amd64.deb"
  run find_latest_packaged_version "7.0-rc2"
  [ "$output" = "" ]
}

@test "stable 7.0 queried, only rc3 present → empty" {
  make_pkg "linux-image-unsigned-7.0-rc3-070000rc3-sav-generic_7.0-rc3-070000rc3-sav.202603112040_amd64.deb"
  run find_latest_packaged_version "7.0"
  [ "$output" = "" ]
}

@test "rc1..rc10 present, ask rc10 → rc10" {
  make_pkg "linux-image-unsigned-7.0-rc1-070000rc1-sav-generic_7.0-rc1-070000rc1-sav.202601010000_amd64.deb"
  make_pkg "linux-image-unsigned-7.0-rc2-070000rc2-sav-generic_7.0-rc2-070000rc2-sav.202601020000_amd64.deb"
  make_pkg "linux-image-unsigned-7.0-rc9-070000rc9-sav-generic_7.0-rc9-070000rc9-sav.202601090000_amd64.deb"
  make_pkg "linux-image-unsigned-7.0-rc10-070000rc10-sav-generic_7.0-rc10-070000rc10-sav.202601100000_amd64.deb"
  run find_latest_packaged_version "7.0-rc10"
  [ "$output" = "7.0-rc10" ]
}

@test "rc1..rc10 present, ask rc1 → rc1 (no rc10 bleed)" {
  make_pkg "linux-image-unsigned-7.0-rc1-070000rc1-sav-generic_7.0-rc1-070000rc1-sav.202601010000_amd64.deb"
  make_pkg "linux-image-unsigned-7.0-rc2-070000rc2-sav-generic_7.0-rc2-070000rc2-sav.202601020000_amd64.deb"
  make_pkg "linux-image-unsigned-7.0-rc9-070000rc9-sav-generic_7.0-rc9-070000rc9-sav.202601090000_amd64.deb"
  make_pkg "linux-image-unsigned-7.0-rc10-070000rc10-sav-generic_7.0-rc10-070000rc10-sav.202601100000_amd64.deb"
  run find_latest_packaged_version "7.0-rc1"
  [ "$output" = "7.0-rc1" ]
}

@test "rc3 not present among rc1/rc2/rc9/rc10 → empty" {
  make_pkg "linux-image-unsigned-7.0-rc1-070000rc1-sav-generic_7.0-rc1-070000rc1-sav.202601010000_amd64.deb"
  make_pkg "linux-image-unsigned-7.0-rc2-070000rc2-sav-generic_7.0-rc2-070000rc2-sav.202601020000_amd64.deb"
  make_pkg "linux-image-unsigned-7.0-rc9-070000rc9-sav-generic_7.0-rc9-070000rc9-sav.202601090000_amd64.deb"
  make_pkg "linux-image-unsigned-7.0-rc10-070000rc10-sav-generic_7.0-rc10-070000rc10-sav.202601100000_amd64.deb"
  run find_latest_packaged_version "7.0-rc3"
  [ "$output" = "" ]
}

# ── Stable patch versions ─────────────────────────────────────────────────────

@test "6.19.6 present → returns 6.19.6" {
  make_pkg "linux-image-unsigned-6.19.6-061906-sav-generic_6.19.6-061906-sav.202603052259_amd64.deb"
  run find_latest_packaged_version "6.19.6"
  [ "$output" = "6.19.6" ]
}

@test "6.19.5 queried, only 6.19.6 present → empty" {
  make_pkg "linux-image-unsigned-6.19.6-061906-sav-generic_6.19.6-061906-sav.202603052259_amd64.deb"
  run find_latest_packaged_version "6.19.5"
  [ "$output" = "" ]
}

@test "6.19.1 queried, 6.19.12 also present → 6.19.1 only (no prefix bleed)" {
  make_pkg "linux-image-unsigned-6.19.1-061901-sav-generic_6.19.1-061901-sav.202601010000_amd64.deb"
  make_pkg "linux-image-unsigned-6.19.12-061912-sav-generic_6.19.12-061912-sav.202601120000_amd64.deb"
  run find_latest_packaged_version "6.19.1"
  [ "$output" = "6.19.1" ]
}

@test "6.19.12 queried, 6.19.1 also present → 6.19.12" {
  make_pkg "linux-image-unsigned-6.19.1-061901-sav-generic_6.19.1-061901-sav.202601010000_amd64.deb"
  make_pkg "linux-image-unsigned-6.19.12-061912-sav-generic_6.19.12-061912-sav.202601120000_amd64.deb"
  run find_latest_packaged_version "6.19.12"
  [ "$output" = "6.19.12" ]
}

# ── Mainline-PPA-form .0 GA and RC packages (X.Y.Z upstream) ────────────────
#
# After the mainline_package_version fix, setup_ubuntu_packaging emits packages
# whose upstream segment is X.Y.Z (with Z=0 for the initial release) for both
# GA and RC, matching kernel.ubuntu.com/mainline naming. find_latest_packaged_version
# must recognize these, otherwise check_if_version_already_packaged never sees
# a freshly built kernel as already packaged and the script rebuilds it.

@test "new-form explicit 7.0.0 → finds 7.0.0 mainline-PPA-form package" {
  make_pkg "linux-image-unsigned-7.0.0-070000-sav-generic_7.0.0-070000-sav.202604141930_amd64.deb"
  run find_latest_packaged_version "7.0.0"
  [ "$output" = "7.0.0" ]
}

@test "new-form short 7.0 → finds 7.0.0 mainline-PPA-form package" {
  make_pkg "linux-image-unsigned-7.0.0-070000-sav-generic_7.0.0-070000-sav.202604141930_amd64.deb"
  run find_latest_packaged_version "7.0"
  [ "$output" = "7.0.0" ]
}

@test "new-form rc7 → finds 7.0-rc7 mainline-PPA-form package (rc marker only in ABI)" {
  make_pkg "linux-image-unsigned-7.0.0-070000rc7-sav-generic_7.0.0-070000rc7-sav.202604081639_amd64.deb"
  run find_latest_packaged_version "7.0-rc7"
  [ "$output" = "7.0-rc7" ]
}

# ── Stable .0 GA versions (packages use short M.m form) ─────────────────────

@test "short 6.19 → finds 6.19.0 old-style package" {
  make_pkg "linux-image-6.19-sav-generic_6.19-sav_amd64.deb"
  run find_latest_packaged_version "6.19"
  [ "$output" = "6.19.0" ]
}

@test "short 6.19 → finds 6.19.0 mainline-style package" {
  make_pkg "linux-image-unsigned-6.19-061900-sav-generic_6.19-061900-sav.202601010000_amd64.deb"
  run find_latest_packaged_version "6.19"
  [ "$output" = "6.19.0" ]
}

@test "explicit 6.19.0 → finds 6.19.0 package" {
  make_pkg "linux-image-unsigned-6.19-061900-sav-generic_6.19-061900-sav.202601010000_amd64.deb"
  run find_latest_packaged_version "6.19.0"
  [ "$output" = "6.19.0" ]
}

@test "explicit 7.0.0 → finds package with short 7.0 in name" {
  make_pkg "linux-image-unsigned-7.0-070000-sav-generic_7.0-070000-sav.202601010000_amd64.deb"
  run find_latest_packaged_version "7.0.0"
  [ "$output" = "7.0.0" ]
}

@test "explicit 7.0.0 → finds new-form and short-form GA packages equivalently" {
  # Duplicate of the new-form test block above; keeps the section self-contained
  # so the old short-form and new mainline-PPA-form symmetry is visible here.
  make_pkg "linux-image-unsigned-7.0.0-070000-sav-generic_7.0.0-070000-sav.202601010000_amd64.deb"
  run find_latest_packaged_version "7.0.0"
  [ "$output" = "7.0.0" ]
}

@test "explicit 7.0.0, rc packages present → empty (no rc bleed)" {
  make_pkg "linux-image-unsigned-7.0-rc3-070000rc3-sav-generic_7.0-rc3-070000rc3-sav.202603112040_amd64.deb"
  run find_latest_packaged_version "7.0.0"
  [ "$output" = "" ]
}

@test "short 6.19, only patch packages present → empty" {
  make_pkg "linux-image-unsigned-6.19.6-061906-sav-generic_6.19.6-061906-sav.202603052259_amd64.deb"
  run find_latest_packaged_version "6.19"
  [ "$output" = "" ]
}

# ── Cross-minor isolation ─────────────────────────────────────────────────────

@test "6.19.6 query must not match 6.9.6 package" {
  make_pkg "linux-image-unsigned-6.19.6-061906-sav-generic_6.19.6-061906-sav.202603052259_amd64.deb"
  make_pkg "linux-image-unsigned-6.9.6-00609006-sav-generic_6.9.6-00609006-sav.202601010000_amd64.deb"
  run find_latest_packaged_version "6.19.6"
  [ "$output" = "6.19.6" ]
}

@test "6.9.6 query must not match 6.19.6 package" {
  make_pkg "linux-image-unsigned-6.19.6-061906-sav-generic_6.19.6-061906-sav.202603052259_amd64.deb"
  make_pkg "linux-image-unsigned-6.9.6-00609006-sav-generic_6.9.6-00609006-sav.202601010000_amd64.deb"
  run find_latest_packaged_version "6.9.6"
  [ "$output" = "6.9.6" ]
}

# ── Empty / no matching packages ──────────────────────────────────────────────

@test "empty dir, rc query → empty" {
  run find_latest_packaged_version "7.0-rc3"
  [ "$output" = "" ]
}

@test "empty dir, stable query → empty" {
  run find_latest_packaged_version "6.19.6"
  [ "$output" = "" ]
}

@test "config file only (no debs), rc query → empty" {
  make_pkg "config-7.0-rc3"
  run find_latest_packaged_version "7.0-rc3"
  [ "$output" = "" ]
}

# ── Package name variants ─────────────────────────────────────────────────────

@test "both signed and unsigned packages present → returns version" {
  make_pkg "linux-image-6.19-sav-generic_6.19-sav_amd64.deb"
  make_pkg "linux-image-unsigned-6.19-061900-sav-generic_6.19-061900-sav.202601010000_amd64.deb"
  run find_latest_packaged_version "6.19.0"
  [ "$output" = "6.19.0" ]
}

# ── mainline_package_version ──────────────────────────────────────────────────
#
# Matches Ubuntu mainline PPA convention (see https://kernel.ubuntu.com/mainline/):
# the upstream part is always X.Y.Z (with Z=0 for the initial release), for both
# GA and RC. The RC marker is encoded only inside the ABI (e.g., 070000rc7),
# never as a segment between upstream and ABI. This keeps GA releases sorted
# above the corresponding RCs under GRUB's version_sort.

@test "mainline_package_version: GA 7.0.0 with local version" {
  run mainline_package_version "7.0.0" "sav" "202604141930"
  [ "$output" = "7.0.0-070000-sav.202604141930" ]
}

@test "mainline_package_version: stable patch 6.19.5 with local version" {
  run mainline_package_version "6.19.5" "sav" "202601010000"
  [ "$output" = "6.19.5-061905-sav.202601010000" ]
}

@test "mainline_package_version: RC 7.0-rc7 with local version (no interior -rc segment)" {
  run mainline_package_version "7.0-rc7" "sav" "202604081639"
  [ "$output" = "7.0.0-070000rc7-sav.202604081639" ]
}

@test "mainline_package_version: GA 7.0.0 with empty local version (no trailing -suffix)" {
  run mainline_package_version "7.0.0" "" "202604141930"
  [ "$output" = "7.0.0-070000.202604141930" ]
}

@test "mainline_package_version: GA sorts above matching RC under grub-sort-version" {
  ga_release="$(mainline_package_version "7.0.0"   "sav" "202604141930")-generic"
  rc_release="$(mainline_package_version "7.0-rc7" "sav" "202604081639")-generic"
  first=$(printf '%s\n%s\n' "$ga_release" "$rc_release" \
          | LC_ALL=C /usr/lib/grub/grub-sort-version -r | head -n 1)
  [ "$first" = "$ga_release" ]
}

# ── annotation_set / annotation_undefine staging ───────────────────────────────
#
# Changes are staged into _annotation_ops (applied in one pass by flush_annotations) and, for
# n-disables, also into _disabled_configs, which scopes verify_disabled_modules to our own
# disables so stock-n annotations forced on by the build don't trigger a spurious prompt.

@test "annotation_set n stages a set op and records the config as ours to verify" {
  _annotation_ops=(); _disabled_configs=()
  annotation_set CONFIG_FOO n
  [ "${_annotation_ops[*]}" = "set CONFIG_FOO n" ]
  [ "${_disabled_configs[*]}" = "CONFIG_FOO" ]
}

@test "annotation_set y/m stages set ops but records no disable" {
  _annotation_ops=(); _disabled_configs=()
  annotation_set CONFIG_FOO y
  annotation_set CONFIG_BAR m
  [ "${_annotation_ops[*]}" = "set CONFIG_FOO y set CONFIG_BAR m" ]
  [ "${#_disabled_configs[@]}" -eq 0 ]
}

@test "annotation_undefine stages a remove op and records no disable" {
  _annotation_ops=(); _disabled_configs=()
  annotation_undefine CONFIG_FOO
  [ "${_annotation_ops[*]}" = "remove CONFIG_FOO" ]
  [ "${#_disabled_configs[@]}" -eq 0 ]
}

# ── find_running_kernel_version ─────────────────────────────────────────────────
#
# Must recognize the Ubuntu-mainline-PPA RC form this script itself produces, where the RC marker
# lives in the ABI segment (070000rc7) rather than as a -rcN suffix. A plain
# `M.m(.p)?(-rcN)?` extraction silently drops the rc and reports the kernel as GA.

@test "find_running_kernel_version: RC built by this script (rc in ABI) → M.m-rcN" {
  uname() { echo "7.0.0-070000rc7-sav-generic"; }
  export -f uname
  run find_running_kernel_version
  [ "$output" = "7.0-rc7" ]
}

@test "find_running_kernel_version: mainline-PPA RC form → M.m-rcN" {
  uname() { echo "6.8.0-060800rc1-generic"; }
  export -f uname
  run find_running_kernel_version
  [ "$output" = "6.8-rc1" ]
}

@test "find_running_kernel_version: kernel.org RC form (-rcN suffix) → M.m-rcN" {
  uname() { echo "7.0-rc7-generic"; }
  export -f uname
  run find_running_kernel_version
  [ "$output" = "7.0-rc7" ]
}

@test "find_running_kernel_version: GA with ABI → M.m.0" {
  uname() { echo "7.0.0-070000-sav-generic"; }
  export -f uname
  run find_running_kernel_version
  [ "$output" = "7.0.0" ]
}

@test "find_running_kernel_version: stable patch → M.m.p" {
  uname() { echo "6.19.6-061906-sav-generic"; }
  export -f uname
  run find_running_kernel_version
  [ "$output" = "6.19.6" ]
}

@test "find_running_kernel_version: bare M.m → normalized to M.m.0" {
  uname() { echo "6.6-generic"; }
  export -f uname
  run find_running_kernel_version
  [ "$output" = "6.6.0" ]
}

# ── find_local_config_file_for_version ──────────────────────────────────────────
#
# GA configs are stored in short form (config-7.0, not config-7.0.0), so the lookup must be done
# with the short version. These lock in that contract, which is why main() shortens
# building_kernel_version before the local lookup.

@test "find_local_config_file_for_version: GA config found by short version" {
  make_pkg "config-7.0"
  run find_local_config_file_for_version "7.0"
  [ "$output" = "$v_packages_destination/config-7.0" ]
}

@test "find_local_config_file_for_version: GA config NOT found by full M.m.0 form" {
  make_pkg "config-7.0"
  run find_local_config_file_for_version "7.0.0"
  [ "$output" = "" ]
}

@test "find_local_config_file_for_version: RC config found by short rc version" {
  make_pkg "config-7.0-rc7"
  run find_local_config_file_for_version "7.0-rc7"
  [ "$output" = "$v_packages_destination/config-7.0-rc7" ]
}

@test "find_local_config_file_for_version: patch config found by full patch version" {
  make_pkg "config-6.19.6"
  run find_local_config_file_for_version "6.19.6"
  [ "$output" = "$v_packages_destination/config-6.19.6" ]
}
