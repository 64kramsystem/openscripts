#!/usr/bin/env bats

c_script="$BATS_TEST_DIRNAME/scrape_terminal_screen"

# ── Argument handling ───────────────────────────────────────────────────────────

@test "--help: prints usage and exits 0" {
  run "$c_script" --help

  [ "$status" -eq 0 ]
  [[ "$output" == Usage:* ]]
}

@test "rejects positional arguments" {
  run "$c_script" extra

  [ "$status" -eq 1 ]
  [[ "$output" == Usage:* ]]
}

# ── Resume-id extraction ────────────────────────────────────────────────────────
#
# This mirrors the pipeline used by the claude() wrapper in .zsh_saverio.sh; keep them in sync.

extract_last_resume_id() {
  perl -ne 'print "$1\n" if /^claude --resume ([-a-z0-9]+)$/' | tail -n 1
}

@test "extract: returns the resume UUID printed by claude on exit" {
  run extract_last_resume_id <<'SCREEN'
some session output
claude --resume bcbdd625-e862-4b41-8e54-739e3e874b99
SCREEN

  [ "$status" -eq 0 ]
  [ "$output" = "bcbdd625-e862-4b41-8e54-739e3e874b99" ]
}

@test "extract: takes the LAST match when several are present" {
  run extract_last_resume_id <<'SCREEN'
claude --resume aaaaaaaa-1111-2222-3333-444444444444
noise
claude --resume bcbdd625-e862-4b41-8e54-739e3e874b99
SCREEN

  [ "$output" = "bcbdd625-e862-4b41-8e54-739e3e874b99" ]
}

@test "extract: ignores the command when not at the start of a line" {
  run extract_last_resume_id <<'SCREEN'
  $ claude --resume deadbeef-0000-1111-2222-333333333333
SCREEN

  [ -z "$output" ]
}

@test "extract: ignores lines with trailing content after the id" {
  run extract_last_resume_id <<'SCREEN'
claude --resume deadbeef-0000-1111-2222-333333333333 (most recent)
SCREEN

  [ -z "$output" ]
}
