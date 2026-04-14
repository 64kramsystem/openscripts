#!/usr/bin/env bats

setup_file() {
  source "$BATS_TEST_DIRNAME/build_kernel"
  export -f find_latest_packaged_version short_kernel_version
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

@test "explicit 7.0.0, only 7.0.0-named package → empty (packages use short form)" {
  make_pkg "linux-image-unsigned-7.0.0-070000-sav-generic_7.0.0-070000-sav.202601010000_amd64.deb"
  run find_latest_packaged_version "7.0.0"
  [ "$output" = "" ]
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
