#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/toggle_screen_black"

  # State file isolation: the script keys off ${XDG_RUNTIME_DIR}/toggle_screen_black.state.
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR"
  STATE_FILE="$XDG_RUNTIME_DIR/toggle_screen_black.state"

  # Stub the external commands the script invokes. pgrep MUST be stubbed: the real one would find
  # the user's running xflux, and the script would then kill -STOP it.
  export FAKE_BIN_DIR="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$FAKE_BIN_DIR"

  export XRANDR_LOG="$BATS_TEST_TMPDIR/xrandr.log"
  : > "$XRANDR_LOG"

  # `--verbose` emits a connected output and a brightness, parsed by the script's perl one-liners;
  # every other invocation (the actual --brightness set) just succeeds. All calls are logged.
  cat > "$FAKE_BIN_DIR/xrandr" <<'FAKE'
#!/usr/bin/env bash
printf 'xrandr %s\n' "$*" >> "$XRANDR_LOG"
if [[ $1 == --verbose ]]; then
  printf '%s\n' 'DP-2 connected primary 3440x1440+0+0'
  printf '\t%s\n' 'Brightness: 1.0'
fi
exit 0
FAKE
  chmod +x "$FAKE_BIN_DIR/xrandr"

  # No xflux running: exit non-zero with no output, matching real pgrep on no match.
  cat > "$FAKE_BIN_DIR/pgrep" <<'FAKE'
#!/usr/bin/env bash
exit 1
FAKE
  chmod +x "$FAKE_BIN_DIR/pgrep"

  PATH="$FAKE_BIN_DIR:$PATH"
}

# ── Argument parsing ──────────────────────────────────────────────────────────

@test "--help prints usage and exits 0" {
  run "$SCRIPT" --help
  [[ $status -eq 0 ]]
  [[ $output == Usage:* ]]
}

@test "rejects an unknown argument" {
  run "$SCRIPT" bogus
  [[ $status -eq 1 ]]
  [[ $output == Usage:* ]]
}

@test "rejects more than one argument" {
  run "$SCRIPT" on off
  [[ $status -eq 1 ]]
  [[ $output == Usage:* ]]
}

# ── No argument: toggle ─────────────────────────────────────────────────────────

@test "no arg, currently visible: blacks the screen" {
  run "$SCRIPT"
  [[ $status -eq 0 ]]
  [[ -f $STATE_FILE ]]
  [[ $(< "$STATE_FILE") == 1.0 ]]
  grep -qx 'xrandr --output DP-2 --brightness 0' "$XRANDR_LOG"
}

@test "no arg, currently black: restores the screen" {
  echo 1.0 > "$STATE_FILE"
  run "$SCRIPT"
  [[ $status -eq 0 ]]
  [[ ! -f $STATE_FILE ]]
  grep -qx 'xrandr --output DP-2 --brightness 1.0' "$XRANDR_LOG"
}

# ── Explicit on ─────────────────────────────────────────────────────────────────

@test "on, currently visible: blacks the screen" {
  run "$SCRIPT" on
  [[ $status -eq 0 ]]
  [[ -f $STATE_FILE ]]
  grep -qx 'xrandr --output DP-2 --brightness 0' "$XRANDR_LOG"
}

@test "on, currently black: no-op (xrandr untouched, state preserved)" {
  echo 0.7 > "$STATE_FILE"
  run "$SCRIPT" on
  [[ $status -eq 0 ]]
  [[ -f $STATE_FILE ]]
  [[ $(< "$STATE_FILE") == 0.7 ]]
  [[ ! -s $XRANDR_LOG ]]
}

# ── Explicit off ────────────────────────────────────────────────────────────────

@test "off, currently black: restores the screen" {
  echo 0.7 > "$STATE_FILE"
  run "$SCRIPT" off
  [[ $status -eq 0 ]]
  [[ ! -f $STATE_FILE ]]
  grep -qx 'xrandr --output DP-2 --brightness 0.7' "$XRANDR_LOG"
}

@test "off, currently visible: no-op (xrandr untouched, no state file)" {
  run "$SCRIPT" off
  [[ $status -eq 0 ]]
  [[ ! -f $STATE_FILE ]]
  [[ ! -s $XRANDR_LOG ]]
}
