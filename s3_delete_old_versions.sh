#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset
shopt -s inherit_errexit

# Source: https://github.com/Tarvinder91/aws-utils/blob/master/S3/Delete-old-version-objects-1000obj-at-a-time.sh
#         https://gist.github.com/pecigonzalo/3f89a4b29b6fae933000ca03720e15c5
#
# Incomplete:
#
# - it needs testing;
# - it needs to be checked if there is an upper limit to the number of objects that `list-object-versions`
#   returns;
# - some functions not only find, but also set, so they should be split.
#
# Note that this purpose can be easily accomplished by lifetimes, so this is mostly a reference for
# how to work with awscli in general.

v_bucket=
v_prefix=
v_data_dir=
v_batch_size=1000
v_execute=        # boolean: false=blank, true=anything else

old_object_versions_count=

c_summary_file_prefix=current-objects-summary
c_all_objects_file=all-objects.json
c_old_objects_file=old-objects.json
c_markers_file=delete-markers.json
c_old_objects_batch_files_prefix=deleted-files-start-index-
c_markers_batch_files_prefix=deleted-markers-start-index-

c_blank_prefix_dirname=blank_prefix
c_help="Usage: $(basename "$0") [-h|--help] [-x|--execute] [-p|--prefix <prefix>] [-b|--batch-size <size>] [-d|--data-dir <dir>] <bucket_name>

No write actions are performed, unless the execute option is specified.

The batch size defaults to $v_batch_size.

The prefix defaults to blank.

The data dir default to <prefix_name> in the current directory (\"blank_prefix\" if no prefix is provided."

function decode_cmdline_options {
  local data_dir

  local params
  params=$(getopt --options hxp:b:d: --long help,execute,prefix:,batch-size:,data-dir: --name "$(basename "$0")" -- "$@")

  eval set -- "$params"

  while true; do
    case "$1" in
      -h|--help)
        echo "$c_help"
        exit 0 ;;
      -x|--execute)
        v_execute=1
        shift ;;
      -p|--prefix)
        v_prefix=$2
        shift 2 ;;
      -b|--batch-size)
        v_batch_size=$2
        shift 2 ;;
      -d|--data-dir)
        data_dir=$2
        shift 2 ;;
      --)
        shift
        break ;;
    esac
  done

  if [[ $# -ne 1 ]]; then
    >&2 echo "$c_help"
    exit 1
  fi

  v_bucket=$1
  v_data_dir=${data_dir:-$(dirname "$(mktemp)")/${v_prefix:-$c_blank_prefix_dirname}}
}

function print_params {
  echo "Running with params:"
  echo "- prefix:     ${v_prefix:-(none)}"
  echo "- data_dir:   ${v_data_dir}"
  echo "- batch_size: ${v_batch_size}"
  echo "- execute:    ${v_execute:-no}"
  echo
}

function create_and_switch_to_prefix_objects_dir {
  if [[ -d $v_data_dir ]]; then
    echo "The data dir already exists; deleting it..."
    rm -r "$v_data_dir"
    echo
  fi

  mkdir -p "$v_data_dir"
  pushd "$v_data_dir" > /dev/null
}

function register_exit_hook {
  function _exit_hook { popd > /dev/null; }
  trap _exit_hook EXIT
}

function print_current_objects_summary {
  local suffix=${1:-}

  local summary_filename=$c_summary_file_prefix$suffix.txt

  echo -n "Objects number/size${v_prefix:+ with prefix '$v_prefix'} (current version): "

  aws s3 ls --summarize --human-readable "s3://$v_bucket/$v_prefix" --recursive > "$summary_filename"

  tail -2 "$summary_filename" | perl -0777 -ne 'print join("/", m/: (.+)$/mg)."\n"'
}

function store_all_object_versions_list {
  aws s3api list-object-versions --bucket "$v_bucket" --prefix "$v_prefix" > "$c_all_objects_file"
}

function print_all_object_versions_count {
  echo -n "Objects number${v_prefix:+ with prefix '$v_prefix'} (including old versions): "

  jq 'length' "$c_all_objects_file"
}

function store_old_object_versions_list {
  jq '[ .Versions | .[] | select(.IsLatest | not) ]' "$c_all_objects_file" > "$c_old_objects_file"
}

function store_markers_list {
  jq '.DeleteMarkers' "$c_all_objects_file" > "$c_markers_file"
}

function delete_old_versions {
  local old_object_versions_count
  old_object_versions_count=$(jq 'length' "$c_old_objects_file")

  echo "Objects number${v_prefix:+ with prefix '$v_prefix'} (old versions): $old_object_versions_count"

  echo

  for ((i = 0; i < old_object_versions_count; i+=v_batch_size)); do
    local next_batch_i=$((i + v_batch_size))

    echo "Deleting records from $i to $((next_batch_i -1))${v_execute:- (dry run)}..."

    local old_versions
    old_versions=$(jq "[ .[$i:$next_batch_i] | .[] | {Key,VersionId} ]" "$c_old_objects_file")

    local batch_filename=$c_old_objects_batch_files_prefix-$i.json
    cat > "$batch_filename" << EOF
{
"Objects": $old_versions,
"Quiet": true
}
EOF

    if [[ -n $v_execute ]]; then
      aws s3api delete-objects --bucket "$v_bucket" --delete "file://$batch_filename"
    fi
  done
}

function delete_markers {
  local markers_count
  markers_count=$(cat "$c_markers_file" | jq 'length')

  echo "Markers number: $markers_count"

  echo

  for ((i=0; i < markers_count; i+=v_batch_size)); do
    local next_batch_i=$((i + v_batch_size))

    echo "Deleting markers from $i to $((next_batch_i - 1))${v_execute:- (dry run)}..."

    local markers
    markers=$(jq "[ .[$i:$next_batch_i] | .[] | {Key,VersionId} ]" "$c_markers_file")

    local batch_filename=$c_markers_batch_files_prefix-$i.json
    cat > "$batch_filename.json" << EOF
{
"Objects": $markers,
"Quiet": true
}
EOF
    if [[ -n $v_execute ]]; then
      aws s3api delete-objects --bucket "$v_bucket" --delete "file://$batch_filename"
    fi
  done
}

decode_cmdline_options "$@"
print_params

create_and_switch_to_prefix_objects_dir
register_exit_hook
print_current_objects_summary
store_all_object_versions_list
print_all_object_versions_count
store_old_object_versions_list
store_markers_list
delete_old_versions
delete_markers
print_current_objects_summary '-AFTER-DELETION'
