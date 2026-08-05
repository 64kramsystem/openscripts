#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup_file() {
  source "$BATS_TEST_DIRNAME/build_kernel_unattended"
  # setup_file runs in its own process, so every function the tests call — the wrapper's and the
  # library's — has to travel through the environment.
  local name
  while read -r name; do
    export -f "$name"
  done < <(declare -F | awk '{ print $3 }')
  # Same for the file-level constants the functions read.
  export c_already_packaged_status c_crack_bundle_temp_file
}

teardown_file() {
  rm -f "${c_crack_bundle_temp_file:-}"
}

setup() {
  v_series=; v_packages_destination=; v_repo_path=; v_local_version=
  v_cpu_target=; v_gcc_package=; v_sav_remote=; v_force=

  v_repo_path=$(mktemp -d)
  git -c init.defaultBranch=main init --quiet "$v_repo_path"
  # One commit, so HEAD is born and branches can be created, checked out and deleted.
  git -C "$v_repo_path" -c user.email=t@example.com -c user.name=t \
    commit -q --allow-empty -m 'fixture'
  v_packages_destination=$(mktemp -d)
}

teardown() {
  rm -rf "$v_repo_path" "$v_packages_destination"
}

# The options a valid invocation always carries.
complete_args() {
  printf '%s\n' --series 7.1 --destination "$v_packages_destination" --repo "$v_repo_path" \
    --local-version sav --cpu-target znver5 --gcc-package gcc-14
}

# Replace everything that would touch the network, the config or the compiler, so `main` can be run
# for its decisions alone. Each stub records that it ran.
stub_build_steps() {
  v_ran=()
  local name
  # register_exit_hook is deliberately NOT stubbed: its cleanup is under test, and its body is
  # harmless when v_cherry_pick_branch_created is empty.
  for name in validate_toolchain fetch_remotes \
    create_if_required_and_switch_branch apply_sav_branch verify_or_setup_ubuntu_packaging \
    import_config_file setup_ubuntu_packaging finalize_ubuntu_config prepare_ubuntu_build \
    fix_ubuntu_config disable_debug_info configure_cpu_target disable_unused_modules \
    flush_annotations verify_disabled_modules compile_kernel \
    remove_destination_old_version_files move_packages_and_cleanup; do
    eval "$name() { v_ran+=($name); }"
  done
  find_latest_kernel_version() { echo 7.1.6; }
  find_local_config_file_for_version() { echo /dev/null; }
  find_most_recent_config_version_available() { echo /dev/null; }
  find_built_packages() { echo "$v_packages_destination/linux-image-x.deb"; }
}

# ── Argument decoding and validation ──────────────────────────────────────────

@test "decode_cmdline_args reads every option" {
  mapfile -t args < <(complete_args)
  decode_cmdline_args "${args[@]}" --sav-remote fork --force

  printf 'series=%s dest=%s local=%s cpu=%s gcc=%s remote=%s force=%s' \
    "$v_series" "$v_packages_destination" "$v_local_version" "$v_cpu_target" \
    "$v_gcc_package" "$v_sav_remote" "$v_force" |
    grep -q "series=7.1 .*local=sav cpu=znver5 gcc=gcc-14 remote=fork force=1"
}

@test "every missing option is reported at once, in a stable order" {
  run bash "$BATS_TEST_DIRNAME/build_kernel_unattended" --series 7.1
  [ "$status" -eq 1 ]
  [ "$output" = "Missing required options: --destination --repo --local-version --cpu-target --gcc-package" ]
}

@test "an invalid series is rejected before anything runs" {
  run bash "$BATS_TEST_DIRNAME/build_kernel_unattended" --series 7 \
    --destination "$v_packages_destination" --repo "$v_repo_path" \
    --local-version sav --cpu-target znver5 --gcc-package gcc-14
  [ "$status" -eq 1 ]
  [[ $output == "Invalid --series: 7 (expected M.m, M.m.p or M.m-rcN)" ]]
}

@test "a repo that is not a git checkout is rejected" {
  local not_a_repo
  not_a_repo=$(mktemp -d)
  run bash "$BATS_TEST_DIRNAME/build_kernel_unattended" --series 7.1 \
    --destination "$v_packages_destination" --repo "$not_a_repo" \
    --local-version sav --cpu-target znver5 --gcc-package gcc-14
  rmdir "$not_a_repo"
  [ "$status" -eq 1 ]
  [[ $output == "Not a git checkout: "* ]]
}

@test "an unwritable destination is rejected" {
  run bash "$BATS_TEST_DIRNAME/build_kernel_unattended" --series 7.1 \
    --destination /nonexistent-destination --repo "$v_repo_path" \
    --local-version sav --cpu-target znver5 --gcc-package gcc-14
  [ "$status" -eq 1 ]
  [[ $output == "Destination is not a writable directory: "* ]]
}

# ── The already-packaged status ───────────────────────────────────────────────

@test "already packaged exits 3 without building" {
  touch "$v_packages_destination/linux-image-unsigned-7.1.6-070106-sav-generic_7.1.6-070106-sav.202601010000_amd64.deb"
  mapfile -t args < <(complete_args)
  stub_build_steps

  local status=0 output
  output=$(main "${args[@]}" 2>&1) || status=$?
  [ "$status" -eq 3 ]
  [[ $output == *"already packaged"* ]]
  [[ " ${v_ran[*]} " != *" compile_kernel "* ]]
}

@test "--force builds even when the version is already packaged" {
  touch "$v_packages_destination/linux-image-unsigned-7.1.6-070106-sav-generic_7.1.6-070106-sav.202601010000_amd64.deb"
  mapfile -t args < <(complete_args)
  stub_build_steps
  send_built_packages_to_fd3() { echo "reported"; }

  main "${args[@]}" --force > /dev/null 2>&1
  [[ " ${v_ran[*]} " == *" compile_kernel "* ]]
}

@test "a clean destination builds and reports the packages" {
  mapfile -t args < <(complete_args)
  stub_build_steps
  send_built_packages_to_fd3() { printf 'reported:%s' "$1"; }

  local status=0 output
  output=$(main "${args[@]}" 2>&1) || status=$?
  [ "$status" -eq 0 ]
  [[ $output == *"reported:$v_packages_destination/linux-image-x.deb"* ]]
}

@test "a build that produces no packages fails instead of reporting nothing" {
  mapfile -t args < <(complete_args)
  stub_build_steps
  find_built_packages() { echo ''; }

  local status=0 output
  output=$(main "${args[@]}" 2>&1) || status=$?
  [ "$status" -eq 1 ]
  [[ $output == *"produced no packages"* ]]
}

# The exit hook only fires when the process exits, so this runs the wrapper in a subshell. Without the
# cleanup the branch outlives the run, and the next build of a new version aborts on
# apply_sav_branch's "already exists" guard — daily, in both suites, until it is deleted by hand.
@test "the temporary replay branch never outlives the run" {
  run bash -c "
    source '$BATS_TEST_DIRNAME/build_kernel_unattended'
    $(declare -f stub_build_steps)
    stub_build_steps
    apply_sav_branch() {
      git checkout -q -b \"\$c_cherry_pick_branch\"
      v_cherry_pick_branch_created=1
    }
    send_built_packages_to_fd3() { :; }
    main --series 7.1 --destination '$v_packages_destination' --repo '$v_repo_path' \
      --local-version sav --cpu-target znver5 --gcc-package gcc-14 --sav-remote fork
  "
  [ "$status" -eq 0 ]

  run git -C "$v_repo_path" rev-parse -q --verify temporary_cherry_picks
  [ "$status" -ne 0 ]
}

# ── Contract with the library ─────────────────────────────────────────────────

@test "the prompt can never trigger: v_unattended is set at load time" {
  grep -q "^v_unattended=1$" "$BATS_TEST_DIRNAME/build_kernel_unattended"
}

@test "reporting on a closed FD 3 does not fail the build" {
  run bash 3>&- -c 'source '"$BATS_TEST_DIRNAME"'/lib/kernel_build.sh; send_built_packages_to_fd3 "a.deb"; echo survived'
  [ "$status" -eq 0 ]
  [[ $output == *survived* ]]
}

# The template patch is an exact-string replacement that silently does nothing once upstream
# restructures the text, so the deliverable is checked rather than the patch trusted. A package built
# with the two-directory form fails at install time on Noble's debianutils 5.17.
@test "a two-directory run-parts invocation in the packaging fails the build" {
  local tree
  tree=$(mktemp -d)
  mkdir -p "$tree/debian/templates"
  printf 'if [ -d /etc/kernel/preinst.d ]; then\n    DEB_MAINT_PARAMS="$*" run-parts --report --arg=$version \\\n        --arg=$image_path /etc/kernel/preinst.d /usr/share/kernel/preinst.d\nfi\n' \
    > "$tree/debian/templates/image.preinst.in"

  run bash -c "cd '$tree' && source '$BATS_TEST_DIRNAME/lib/kernel_build.sh' &&
    verify_single_directory_run_parts"
  [ "$status" -eq 1 ]
  [[ $output == *"more than one directory"* ]]

  # The patched loop form, which is valid on both suites, must pass.
  printf 'for _kd in /etc/kernel/preinst.d /usr/share/kernel/preinst.d; do\n    if [ -d "$_kd" ]; then\n        run-parts --report --arg=$version "$_kd"\n    fi\ndone\n' \
    > "$tree/debian/templates/image.preinst.in"

  run bash -c "cd '$tree' && source '$BATS_TEST_DIRNAME/lib/kernel_build.sh' &&
    verify_single_directory_run_parts"
  rm -rf "$tree"
  [ "$status" -eq 0 ]
}

# extra.postrm.in ships the whole postinst trigger commented out, two-directory form included.
@test "a commented-out two-directory run-parts invocation does not fail the build" {
  local tree
  tree=$(mktemp -d)
  mkdir -p "$tree/debian/templates"
  printf '#    cat - >/usr/lib/linux/triggers/$version <<EOF\n#DEB_MAINT_PARAMS="configure" run-parts --report --exit-on-error --arg=$version \\\n#    --arg="$image_path" /etc/kernel/postinst.d /usr/share/kernel/postinst.d\n#EOF\n' \
    > "$tree/debian/templates/extra.postrm.in"

  run bash -c "cd '$tree' && source '$BATS_TEST_DIRNAME/lib/kernel_build.sh' &&
    verify_single_directory_run_parts"
  rm -rf "$tree"
  [ "$status" -eq 0 ]
}
