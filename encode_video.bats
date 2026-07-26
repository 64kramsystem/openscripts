#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/encode_video"

  WORK_DIR="$BATS_TEST_TMPDIR/work"
  mkdir -p "$WORK_DIR"

  export CMD_LOG="$BATS_TEST_TMPDIR/cmd.log"
  : > "$CMD_LOG"

  # Stub the external commands: nproc (must hit the procs mapping), ffprobe (input checks), parallel
  # (runs each stdin line through bash), ffmpeg (logs and touches the output file, i.e. its last
  # argument), trash.
  FAKE_BIN_DIR="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$FAKE_BIN_DIR"

  cat > "$FAKE_BIN_DIR/nproc" <<'FAKE'
#!/usr/bin/env bash
echo 32
FAKE

  cat > "$FAKE_BIN_DIR/ffprobe" <<'FAKE'
#!/usr/bin/env bash
echo "ffprobe $*" >> "$CMD_LOG"
if [[ $* == *"-select_streams v:0"* ]]; then
  echo "${FFPROBE_VIDEO_TYPE:-video}"
else
  echo "${FFPROBE_AUDIO_TYPE-audio}"
fi
FAKE

  cat > "$FAKE_BIN_DIR/parallel" <<'FAKE'
#!/usr/bin/env bash
while IFS= read -r line || [[ -n $line ]]; do
  bash -c "$line" || exit 1
done
FAKE

  cat > "$FAKE_BIN_DIR/ffmpeg" <<'FAKE'
#!/usr/bin/env bash
echo "ffmpeg $*" >> "$CMD_LOG"
[[ -n ${FFMPEG_FAIL:-} ]] && exit 1
for last in "$@"; do :; done
touch "$last"
FAKE

  cat > "$FAKE_BIN_DIR/trash" <<'FAKE'
#!/usr/bin/env bash
echo "trash $*" >> "$CMD_LOG"
rm -- "$@"
FAKE

  chmod +x "$FAKE_BIN_DIR"/*
  PATH="$FAKE_BIN_DIR:$PATH"
}

# Sources the script and runs the given snippet in its context (for unit-testing functions).
run_sourced() {
  run bash -c "source '$SCRIPT'; $1"
}

make_input() {
  local file
  for file in "$@"; do
    echo data > "$WORK_DIR/$file"
  done
}

# ── Argument parsing ──────────────────────────────────────────────────────────

@test "--help prints usage and exits 0" {
  run "$SCRIPT" --help
  [[ $status -eq 0 ]]
  [[ $output == Usage:* ]]
}

@test "no input files prints usage and exits 1" {
  run "$SCRIPT"
  [[ $status -eq 1 ]]
  [[ $output == Usage:* ]]
}

@test "rejects an invalid encoder" {
  run "$SCRIPT" --encoder vp9 in.mp4
  [[ $status -eq 1 ]]
  [[ $output == *"Invalid encoder"* ]]
}

@test "rejects an invalid rotation" {
  run "$SCRIPT" -R sideways in.mp4
  [[ $status -eq 1 ]]
  [[ $output == *"Invalid rotation"* ]]
}

@test "rejects an invalid DAR ratio" {
  run "$SCRIPT" -s 4:3 in.mp4
  [[ $status -eq 1 ]]
  [[ $output == *"Unexpected DAR ratio."* ]]
}

@test "rejects square and resize together" {
  run "$SCRIPT" -s 4/3 -r 720 in.mp4
  [[ $status -eq 1 ]]
  [[ $output == *"can't be performed together"* ]]
}

@test "rejects concat with a single input" {
  run "$SCRIPT" -c in.mp4
  [[ $status -eq 1 ]]
  [[ $output == *"Concat requires more than one input."* ]]
}

@test "errors on an unmapped processors count" {
  cat > "$FAKE_BIN_DIR/nproc" <<'FAKE'
#!/usr/bin/env bash
echo 7
FAKE
  run "$SCRIPT" in.mp4
  [[ $status -eq 1 ]]
  [[ $output == *"Procs count mapping not found for 7 processors."* ]]
}

# ── File name computation ─────────────────────────────────────────────────────

@test "temp input file prepends '.orig' to the extension" {
  run_sourced 'decode_cmdline_args /path/pizza.mp4; echo "${v_temp_input_files[0]}"'
  [[ $status -eq 0 ]]
  [[ $output == /path/pizza.orig.mp4 ]]
}

@test "output file replaces the extension with the default" {
  run_sourced 'decode_cmdline_args /path/pizza.mp4; echo "${v_output_files[0]}"'
  [[ $status -eq 0 ]]
  [[ $output == /path/pizza.mkv ]]
}

@test "output file honors --extension" {
  run_sourced 'decode_cmdline_args -e webm /path/pizza.mp4; echo "${v_output_files[0]}"'
  [[ $status -eq 0 ]]
  [[ $output == /path/pizza.webm ]]
}

@test "output file honors --output-dir, stripping any trailing slash" {
  run_sourced 'decode_cmdline_args -o /out/ /path/pizza.mp4; echo "${v_output_files[0]}"'
  [[ $status -eq 0 ]]
  [[ $output == /out/pizza.mkv ]]
}

@test "cut ranges are split off the input filename" {
  run_sourced 'decode_cmdline_args "/path/pizza.mp4=10-20,30-"; echo "${v_orig_input_files[0]}"; echo "${v_file_segments[0]}"'
  [[ $status -eq 0 ]]
  [[ ${lines[0]} == /path/pizza.mp4 ]]
  [[ ${lines[1]} == 10-20,30- ]]
}

@test "an '=' suffix that is not a valid range stays in the filename" {
  run_sourced 'decode_cmdline_args "/path/pizza=extra.mp4"; echo "${v_orig_input_files[0]}"; echo "${v_temp_input_files[0]}"'
  [[ $status -eq 0 ]]
  [[ ${lines[0]} == /path/pizza=extra.mp4 ]]
  [[ ${lines[1]} == /path/pizza=extra.orig.mp4 ]]
}

# ── segments_are_valid ────────────────────────────────────────────────────────

@test "segments_are_valid accepts valid formats" {
  local segments
  for segments in 10-20 -20 10- 1:02:03.5-2:00:00 0.5-1.5 10-20,30-40; do
    run_sourced "segments_are_valid '$segments'"
    [[ $status -eq 0 ]]
  done
}

@test "segments_are_valid rejects invalid formats" {
  local segments
  for segments in 10 abc-def 1:2:3:4-5 10-20,foo; do
    run_sourced "segments_are_valid '$segments'"
    [[ $status -eq 1 ]]
  done
}

# ── timestamp_to_seconds ──────────────────────────────────────────────────────

@test "timestamp_to_seconds converts all formats" {
  run_sourced 'timestamp_to_seconds 90; timestamp_to_seconds 1:30; timestamp_to_seconds 1:00:05'
  [[ $status -eq 0 ]]
  [[ ${lines[0]} == 90 ]]
  [[ ${lines[1]} == 90 ]]
  [[ ${lines[2]} == 3605 ]]
}

# ── video_filters ─────────────────────────────────────────────────────────────

@test "video_filters is empty by default" {
  run_sourced 'decode_cmdline_args in.mp4; video_filters'
  [[ $status -eq 0 ]]
  [[ -z $output ]]
}

@test "video_filters combines the options in order" {
  run_sourced 'decode_cmdline_args -d -r 720 -R cw in.mp4; video_filters'
  [[ $status -eq 0 ]]
  [[ $output == "yadif=mode=0,scale=-2:720,transpose=clock" ]]
}

@test "video_filters converts the DAR ratio to square pixels" {
  run_sourced 'decode_cmdline_args -s 4/3 in.mp4; video_filters'
  [[ $status -eq 0 ]]
  [[ $output == "scale='min(iw,ih*4/3)':'round(min(ih,iw*3/4)/2)*2',setsar=1" ]]
}

# ── Encoding workflow ─────────────────────────────────────────────────────────

@test "happy path: encodes, then trashes the temp input file" {
  make_input pizza.mp4
  run "$SCRIPT" -b "$WORK_DIR/pizza.mp4"
  [[ $status -eq 0 ]]
  [[ -f "$WORK_DIR/pizza.mkv" ]]
  [[ ! -f "$WORK_DIR/pizza.mp4" ]]
  [[ ! -f "$WORK_DIR/pizza.orig.mp4" ]]
  grep -q "ffmpeg .*pizza.orig.mp4" "$CMD_LOG"
  grep -q "trash $WORK_DIR/pizza.orig.mp4" "$CMD_LOG"
}

@test "--keep-input-files keeps the temp input file" {
  make_input pizza.mp4
  run "$SCRIPT" -b -k "$WORK_DIR/pizza.mp4"
  [[ $status -eq 0 ]]
  [[ -f "$WORK_DIR/pizza.mkv" ]]
  [[ -f "$WORK_DIR/pizza.orig.mp4" ]]
  ! grep -q "^trash " "$CMD_LOG"
}

@test "multiple inputs are all encoded" {
  make_input pizza.mp4 pasta.avi
  run "$SCRIPT" -b "$WORK_DIR/pizza.mp4" "$WORK_DIR/pasta.avi"
  [[ $status -eq 0 ]]
  [[ -f "$WORK_DIR/pizza.mkv" ]]
  [[ -f "$WORK_DIR/pasta.mkv" ]]
}

@test "concat produces a single output from multiple inputs" {
  make_input pizza.mp4 pasta.mp4
  run "$SCRIPT" -b -c "$WORK_DIR/pizza.mp4" "$WORK_DIR/pasta.mp4"
  [[ $status -eq 0 ]]
  [[ -f "$WORK_DIR/pizza.mkv" ]]
  [[ ! -f "$WORK_DIR/pasta.mkv" ]]
  grep -q "ffmpeg .*pizza.orig.mp4.*pasta.orig.mp4" "$CMD_LOG"
}

@test "rejects an input without a video stream" {
  make_input pizza.mp4
  FFPROBE_VIDEO_TYPE=audio run "$SCRIPT" -b "$WORK_DIR/pizza.mp4"
  [[ $status -eq 1 ]]
  [[ $output == *"is not/doesn't contain a video"* ]]
  [[ -f "$WORK_DIR/pizza.mp4" ]]
}

@test "rejects a concat input without audio" {
  make_input pizza.mp4 pasta.mp4
  FFPROBE_AUDIO_TYPE= run "$SCRIPT" -b -c "$WORK_DIR/pizza.mp4" "$WORK_DIR/pasta.mp4"
  [[ $status -eq 1 ]]
  [[ $output == *"has no audio (required in concat mode)"* ]]
  [[ -f "$WORK_DIR/pizza.mp4" ]]
}

@test "audio is not required outside concat mode" {
  make_input pizza.mp4
  FFPROBE_AUDIO_TYPE= run "$SCRIPT" -b "$WORK_DIR/pizza.mp4"
  [[ $status -eq 0 ]]
  [[ -f "$WORK_DIR/pizza.mkv" ]]
}

@test "on encoding failure, restores the input and deletes the output" {
  make_input pizza.mp4
  FFMPEG_FAIL=1 run "$SCRIPT" -b "$WORK_DIR/pizza.mp4"
  [[ $status -ne 0 ]]
  [[ $output == *">>> Original files restored."* ]]
  [[ -f "$WORK_DIR/pizza.mp4" ]]
  [[ ! -f "$WORK_DIR/pizza.orig.mp4" ]]
  [[ ! -f "$WORK_DIR/pizza.mkv" ]]
}

@test "aborts if the output file already exists, leaving the input untouched" {
  make_input pizza.mp4
  echo existing > "$WORK_DIR/pizza.mkv"
  run "$SCRIPT" -b "$WORK_DIR/pizza.mp4"
  [[ $status -eq 1 ]]
  [[ $output == *"exists!"* ]]
  [[ -f "$WORK_DIR/pizza.mp4" ]]
}

@test "encodes in place when the output extension matches the input one" {
  make_input pizza.mp4
  run "$SCRIPT" -b -e mp4 "$WORK_DIR/pizza.mp4"
  [[ $status -eq 0 ]]
  [[ -f "$WORK_DIR/pizza.mp4" ]]
  [[ ! -f "$WORK_DIR/pizza.orig.mp4" ]]
  grep -q "ffmpeg .*pizza.orig.mp4.*$WORK_DIR/pizza.mp4" "$CMD_LOG"
  grep -q "trash $WORK_DIR/pizza.orig.mp4" "$CMD_LOG"
}

@test "encodes in place when --output-dir points to the input directory" {
  make_input pizza.mp4
  cd "$WORK_DIR"
  run "$SCRIPT" -b -e mp4 -o . pizza.mp4
  [[ $status -eq 0 ]]
  [[ -f "$WORK_DIR/pizza.mp4" ]]
  grep -q "ffmpeg .*pizza.orig.mp4.*\./pizza.mp4" "$CMD_LOG"
}

@test "in-place encoding is not broken by an exported CDPATH" {
  mkdir "$WORK_DIR/videos"
  echo data > "$WORK_DIR/videos/pizza.mp4"
  cd "$WORK_DIR"
  CDPATH=. run "$SCRIPT" -b -e mp4 -o ./videos videos/pizza.mp4
  [[ $status -eq 0 ]]
  [[ -f "$WORK_DIR/videos/pizza.mp4" ]]
}

@test "on an in-place encoding failure, restores the input rather than deleting it" {
  make_input pizza.mp4
  FFMPEG_FAIL=1 run "$SCRIPT" -b -e mp4 "$WORK_DIR/pizza.mp4"
  [[ $status -ne 0 ]]
  [[ $output == *">>> Original files restored."* ]]
  [[ -f "$WORK_DIR/pizza.mp4" ]]
  [[ ! -f "$WORK_DIR/pizza.orig.mp4" ]]
}

@test "on a partial rename, the error hook doesn't delete the inputs still at their original path" {
  make_input pizza.mp4 pasta.mp4
  run_sourced "
    v_orig_input_files=('$WORK_DIR/pizza.mp4' '$WORK_DIR/pasta.mp4')
    v_temp_input_files=('$WORK_DIR/pizza.orig.mp4' '$WORK_DIR/pasta.orig.mp4')
    v_output_files=('$WORK_DIR/pizza.mp4' '$WORK_DIR/pasta.mp4')
    compute_input_entries
    register_exit_hooks
    trap - EXIT
    mv '$WORK_DIR/pizza.mp4' '$WORK_DIR/pizza.orig.mp4' # only the first input got renamed
    _error_exit_hook
  "
  [[ $status -eq 0 ]]
  [[ -f "$WORK_DIR/pizza.mp4" ]]
  [[ -f "$WORK_DIR/pasta.mp4" ]]
  [[ ! -f "$WORK_DIR/pizza.orig.mp4" ]]
}

@test "aborts if the output file is a hard link to an input, leaving both untouched" {
  mkdir "$WORK_DIR/out"
  make_input pizza.mp4
  ln "$WORK_DIR/pizza.mp4" "$WORK_DIR/out/pizza.mp4"
  run "$SCRIPT" -b -e mp4 -o "$WORK_DIR/out" "$WORK_DIR/pizza.mp4"
  [[ $status -eq 1 ]]
  [[ $output == *"exists!"* ]]
  [[ -f "$WORK_DIR/pizza.mp4" ]]
  [[ -f "$WORK_DIR/out/pizza.mp4" ]]
}

@test "aborts if the temp input file already exists, leaving both files untouched" {
  make_input pizza.mp4 pizza.orig.mp4
  run "$SCRIPT" -b "$WORK_DIR/pizza.mp4"
  [[ $status -eq 1 ]]
  [[ $output == *"Temporary file"*"exists!"* ]]
  [[ -f "$WORK_DIR/pizza.mp4" ]]
  [[ -f "$WORK_DIR/pizza.orig.mp4" ]]
}

@test "aborts if inputs with different extensions map to the same output file" {
  make_input pizza.mp4 pizza.avi
  run "$SCRIPT" -b "$WORK_DIR/pizza.mp4" "$WORK_DIR/pizza.avi"
  [[ $status -eq 1 ]]
  [[ $output == *"same output file"* ]]
  [[ -f "$WORK_DIR/pizza.mp4" ]]
  [[ -f "$WORK_DIR/pizza.avi" ]]
}

@test "aborts if inputs with the same basename map to the same output file via --output-dir" {
  mkdir "$WORK_DIR/a" "$WORK_DIR/b" "$WORK_DIR/out"
  echo data > "$WORK_DIR/a/pizza.mp4"
  echo data > "$WORK_DIR/b/pizza.mp4"
  run "$SCRIPT" -b -o "$WORK_DIR/out" "$WORK_DIR/a/pizza.mp4" "$WORK_DIR/b/pizza.mp4"
  [[ $status -eq 1 ]]
  [[ $output == *"same output file"* ]]
}

@test "aborts if the output directory doesn't exist, leaving the input untouched" {
  make_input pizza.mp4
  run "$SCRIPT" -b -o "$WORK_DIR/missing" "$WORK_DIR/pizza.mp4"
  [[ $status -eq 1 ]]
  [[ $output == *"output directory doesn't exist!"* ]]
  [[ -f "$WORK_DIR/pizza.mp4" ]]
}

@test "rejects a filename containing a double quote, leaving the input untouched" {
  make_input 'piz"za.mp4'
  run "$SCRIPT" -b "$WORK_DIR/piz\"za.mp4"
  [[ $status -eq 1 ]]
  [[ $output == *"includes a newline/double quote!"* ]]
  [[ -f "$WORK_DIR/piz\"za.mp4" ]]
}

# ── ffmpeg command construction ───────────────────────────────────────────────

@test "single-segment command includes -ss/-to" {
  make_input pizza.mp4
  run "$SCRIPT" -b "$WORK_DIR/pizza.mp4=10-20"
  [[ $status -eq 0 ]]
  grep -q "ffmpeg .*-ss 10 -to 20 .*-c:a copy" "$CMD_LOG"
}

@test "multi-segment command trims and concatenates via filter_complex" {
  make_input pizza.mp4
  run "$SCRIPT" -b "$WORK_DIR/pizza.mp4=10-20,30-40"
  [[ $status -eq 0 ]]
  grep -q "ffmpeg .*-filter_complex .*trim=start=10:end=20.*concat=n=2:v=1:a=1" "$CMD_LOG"
  grep -q "ffmpeg .*-c:a libfdk_aac -vbr 5 -ac 1" "$CMD_LOG"
}

@test "h265 and av1 use their respective codec options" {
  make_input pizza.mp4 pasta.mp4
  run "$SCRIPT" -b --encoder h265 "$WORK_DIR/pizza.mp4"
  [[ $status -eq 0 ]]
  grep -q "ffmpeg .*-c:v libx265 -crf 25 -preset slow" "$CMD_LOG"
  run "$SCRIPT" -b "$WORK_DIR/pasta.mp4"
  [[ $status -eq 0 ]]
  grep -q "ffmpeg .*-c:v libsvtav1 -crf 29 -preset 4" "$CMD_LOG"
}

@test "rotation disables autorotation and resets the rotate metadata" {
  make_input pizza.mp4
  run "$SCRIPT" -b -R ccw "$WORK_DIR/pizza.mp4"
  [[ $status -eq 0 ]]
  grep -q "ffmpeg -noautorotate .*-vf transpose=cclock.*-metadata:s:v:0 rotate=0" "$CMD_LOG"
}
