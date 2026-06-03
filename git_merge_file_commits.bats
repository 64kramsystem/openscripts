#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/git_merge_file_commits"

  v_repo_dir=$(mktemp -d)
  cd "$v_repo_dir"

  git init -q
  git config user.name Test
  git config user.email test@example.com

  v_filename=FILE
}

teardown() {
  rm -rf "$v_repo_dir" "$c_rebase_commands_file"
}

# ── Helpers ───────────────────────────────────────────────────────────────────

# $1: filename, $2: content, $3: subject; prints the commit hash.
make_commit() {
  echo "$2" > "$1"
  git add .
  git commit -qm "$3"
  git rev-parse HEAD
}

standard_fixture() {
  make_commit other.txt base 'unrelated 0' > /dev/null
  c_add_hash=$(make_commit FILE v1 'Add FILE')
  c_u1_hash=$(make_commit other.txt change1 'unrelated 1')
  c_v2_hash=$(make_commit FILE v2 'FILE v2')
  c_u2_hash=$(make_commit other.txt change2 'unrelated 2')
  c_v3_hash=$(make_commit FILE v3 'FILE v3')
}

# ── First addition hash ───────────────────────────────────────────────────────

@test "find_first_addition_hash: file name also matching a ref" {
  standard_fixture
  git tag FILE

  [ "$(find_first_addition_hash)" = "$c_add_hash" ]
}

# ── Rebase commands ───────────────────────────────────────────────────────────

@test "prepare_rebase_commands: fixups all file commits; unrelated commits stay in order" {
  standard_fixture

  prepare_rebase_commands "$(find_first_addition_hash)"

  diff - "$c_rebase_commands_file" << EXPECTED
pick $c_u1_hash unrelated 1
pick $c_u2_hash unrelated 2
pick $c_add_hash Add FILE
fixup $c_v2_hash FILE v2
fixup $c_v3_hash FILE v3
EXPECTED
}

@test "prepare_rebase_commands: HEAD commit not touching the file is picked, not dropped" {
  standard_fixture
  c_u3_hash=$(make_commit other.txt change3 'unrelated 3')

  prepare_rebase_commands "$(find_first_addition_hash)"

  diff - "$c_rebase_commands_file" << EXPECTED
pick $c_u1_hash unrelated 1
pick $c_u2_hash unrelated 2
pick $c_u3_hash unrelated 3
pick $c_add_hash Add FILE
fixup $c_v2_hash FILE v2
fixup $c_v3_hash FILE v3
EXPECTED
}

@test "prepare_rebase_commands: all commits in range touch the file" {
  make_commit other.txt base 'unrelated 0' > /dev/null
  c_add_hash=$(make_commit FILE v1 'Add FILE')
  c_v2_hash=$(make_commit FILE v2 'FILE v2')
  c_v3_hash=$(make_commit FILE v3 'FILE v3')

  prepare_rebase_commands "$(find_first_addition_hash)"

  diff - "$c_rebase_commands_file" << EXPECTED
pick $c_add_hash Add FILE
fixup $c_v2_hash FILE v2
fixup $c_v3_hash FILE v3
EXPECTED
}

# ── Rebase execution ──────────────────────────────────────────────────────────

@test "rebase: single file commit with latest content, as HEAD" {
  standard_fixture

  first_addition_hash=$(find_first_addition_hash)
  prepare_rebase_commands "$first_addition_hash"
  perform_rebase "$first_addition_hash"

  [ "$(git log --pretty=%s -- FILE)" = 'Add FILE' ]
  [ "$(cat FILE)" = v3 ]
  [ "$(git log --reverse --pretty=%s)" = 'unrelated 0
unrelated 1
unrelated 2
Add FILE' ]
}
