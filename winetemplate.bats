#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/winetemplate"
  export WINEPREFIX="$BATS_TEST_TMPDIR/wine"
  mkdir -p "$WINEPREFIX"
  echo 'program.exe' > "$WINEPREFIX/.WINETEMPLATE_BINARY_PATH"

  export CMD_LOG="$BATS_TEST_TMPDIR/cmd.log"
  : > "$CMD_LOG"

  FAKE_BIN_DIR="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$FAKE_BIN_DIR"

  cat > "$FAKE_BIN_DIR/git" <<'FAKE'
#!/usr/bin/env bash
if [[ $1 == for-each-ref ]]; then
  printf '%s\n' main _wine-staging feature-one feature-two
else
  echo "git $*" >> "$CMD_LOG"
fi
FAKE

  cat > "$FAKE_BIN_DIR/fzf" <<'FAKE'
#!/usr/bin/env bash
echo "fzf $*" >> "$CMD_LOG"
cat >> "$CMD_LOG"
echo feature-two
FAKE

  cat > "$FAKE_BIN_DIR/wine" <<'FAKE'
#!/usr/bin/env bash
echo "wine $*" >> "$CMD_LOG"
FAKE

  cat > "$FAKE_BIN_DIR/pgrep" <<'FAKE'
#!/usr/bin/env bash
exit 1
FAKE

  chmod +x "$FAKE_BIN_DIR"/*
  export PATH="$FAKE_BIN_DIR:$PATH"
}

@test "without a branch, chooses one interactively and runs it" {
  run "$SCRIPT"

  [[ $status -eq 0 ]]
  grep -Fx 'fzf ' "$CMD_LOG"
  grep -Fx 'feature-one' "$CMD_LOG"
  grep -Fx 'feature-two' "$CMD_LOG"
  if grep -Fx '_wine-staging' "$CMD_LOG"; then
    false
  fi
  grep -Fx 'git checkout feature-two' "$CMD_LOG"
  grep -Fx 'wine program.exe' "$CMD_LOG"
}
