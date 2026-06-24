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
# normalize_screen mirrors scrape_terminal_screen's post-processing, and extract_last_resume_id the
# regex used by the claude() wrapper in .zsh_saverio.sh; keep them in sync.

normalize_screen() {
  perl -0777 -pe 's/[ \t]+$//mg; s/^\n+|\n+$//g'
}

extract_last_resume_id() {
  perl -ne 'print "$1\n" if /^claude --resume ([-a-z0-9]+)$/' | tail -n 1
}

extract_resume_from_screen() {
  normalize_screen | extract_last_resume_id
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

@test "extract: resume id survives iTerm2 trailing-space padding" {
  run extract_resume_from_screen < <(printf 'noise\nclaude --resume bcbdd625-e862-4b41-8e54-739e3e874b99      \n')

  [ "$output" = "bcbdd625-e862-4b41-8e54-739e3e874b99" ]
}
