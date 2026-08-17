#!/usr/bin/env bash
# Shared canonical project-registry resolution.

fm_project_init() {
  local script_dir
  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  FM_PROJECT_ROOT=${FM_ROOT_OVERRIDE:-$(cd "$script_dir/.." && pwd)}
  FM_PROJECT_HOME=${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_PROJECT_ROOT}}
  FM_PROJECT_DATA=${FM_DATA_OVERRIDE:-$FM_PROJECT_HOME/data}
  FM_PROJECT_REGISTRY=${FM_PROJECT_REGISTRY_OVERRIDE:-$FM_PROJECT_DATA/projects.md}
}

fm_project_records() {
  awk '
    function emit() {
      if (id != "") print id sprintf("%c", 28) path sprintf("%c", 28) mode sprintf("%c", 28) yolo
    }
    $1 == "-" {
      emit()
      id=$2
      path=""
      mode="no-mistakes"
      yolo="off"
      if ($3 ~ /^\[/) {
        flags=""
        for (i=3; i<=NF; i++) {
          flags = flags (flags == "" ? "" : " ") $i
          if ($i ~ /\]$/) break
        }
        gsub(/^\[|\]$/, "", flags)
        count=split(flags, parts, " ")
        for (i=1; i<=count; i++) {
          if (parts[i] == "+yolo") yolo="on"
          else if (parts[i] != "") mode=parts[i]
        }
      }
      next
    }
    /^  path: / {
      path=$0
      sub(/^  path: /, "", path)
    }
    END { emit() }
  ' "$FM_PROJECT_REGISTRY"
}

fm_project_physical_dir() {
  (cd "$1" 2>/dev/null && pwd -P)
}

fm_project_validate_root() {
  local id=$1 path=$2 physical git_root git_physical managed

  case "$path" in
    /*) ;;
    *) printf 'PROJECT_PATH_INVALID: %s has a relative repository path: %s\n' "$id" "$path" >&2; return 1 ;;
  esac
  [ -d "$path" ] || {
    printf 'PROJECT_PATH_INVALID: %s repository path does not exist: %s\n' "$id" "$path" >&2
    return 1
  }
  physical=$(fm_project_physical_dir "$path") || return 1
  git_root=$(git -C "$path" rev-parse --show-toplevel 2>/dev/null) || {
    printf 'PROJECT_PATH_INVALID: %s path is not a Git repository root: %s\n' "$id" "$path" >&2
    return 1
  }
  git_physical=$(fm_project_physical_dir "$git_root") || return 1
  [ "$physical" = "$git_physical" ] || {
    printf 'PROJECT_PATH_INVALID: %s path is not a Git repository root: %s\n' "$id" "$path" >&2
    return 1
  }

  if [ ! -f "$FM_PROJECT_HOME/.fm-secondmate-home" ]; then
    managed=$(fm_project_physical_dir "$FM_PROJECT_HOME/projects" 2>/dev/null || true)
    if [ -n "$managed" ]; then
      case "$physical" in
        "$managed"|"$managed"/*)
          printf "PROJECT_PATH_INVALID: %s path is inside Firstmate's managed project directory: %s\n" "$id" "$path" >&2
          return 1
          ;;
      esac
    fi
  fi

  printf '%s\n' "$physical"
}

fm_project_resolve() {
  local wanted=$1 records id path mode yolo physical seen_ids seen_paths found missing_wanted
  fm_project_init
  [ -f "$FM_PROJECT_REGISTRY" ] || {
    printf 'PROJECT_REGISTRY_MISSING: %s\n' "$FM_PROJECT_REGISTRY" >&2
    return 1
  }

  records=$(fm_project_records)
  seen_ids='|'
  seen_paths='|'
  found=0
  missing_wanted=0
  while IFS="$(printf '\034')" read -r id path mode yolo; do
    [ -n "$id" ] || continue
    case "$seen_ids" in
      *"|$id|"*) printf 'PROJECT_REGISTRY_INVALID: duplicate project id: %s\n' "$id" >&2; return 1 ;;
    esac
    seen_ids="${seen_ids}${id}|"
    case "$mode" in
      no-mistakes|validated-main|direct-PR|local-only) ;;
      *) printf 'PROJECT_REGISTRY_INVALID: unknown mode for %s: %s\n' "$id" "$mode" >&2; return 1 ;;
    esac

    if [ -z "$path" ]; then
      if [ -f "$FM_PROJECT_HOME/.fm-secondmate-home" ]; then
        path="$FM_PROJECT_HOME/projects/$id"
      elif [ "$id" = "$wanted" ]; then
        missing_wanted=1
        continue
      else
        # Migration is per project. Other legacy entries remain visible but do
        # not prevent an already-migrated project from resolving.
        continue
      fi
    fi
    physical=$(fm_project_validate_root "$id" "$path") || return 1
    case "$seen_paths" in
      *"|$physical|"*) printf 'PROJECT_REGISTRY_INVALID: duplicate canonical repository: %s\n' "$physical" >&2; return 1 ;;
    esac
    seen_paths="${seen_paths}${physical}|"

    if [ "$id" = "$wanted" ]; then
      # shellcheck disable=SC2034 # Resolver outputs are consumed by sourcing callers.
      FM_PROJECT_ID=$id
      FM_PROJECT_PATH=$physical
      # shellcheck disable=SC2034 # Resolver outputs are consumed by sourcing callers.
      FM_PROJECT_MODE=$mode
      # shellcheck disable=SC2034 # Resolver outputs are consumed by sourcing callers.
      FM_PROJECT_YOLO=$yolo
      found=1
    fi
  done <<EOF
$records
EOF

  [ "$missing_wanted" -eq 0 ] || {
    printf 'PROJECT_PATH_REQUIRED: %s needs an explicit canonical repository path\n' "$wanted" >&2
    return 1
  }
  [ "$found" -eq 1 ] || {
    printf 'PROJECT_NOT_FOUND: %s\n' "$wanted" >&2
    return 1
  }
}

fm_project_resolve_arg() {
  local arg=$1 records id path mode yolo physical requested_physical match_id matches seen_ids seen_paths
  case "$arg" in
    */*) ;;
    *) fm_project_resolve "$arg"; return ;;
  esac

  fm_project_init
  [ -f "$FM_PROJECT_REGISTRY" ] || {
    printf 'PROJECT_REGISTRY_MISSING: %s\n' "$FM_PROJECT_REGISTRY" >&2
    return 1
  }
  [ -d "$arg" ] || {
    printf 'PROJECT_PATH_NOT_REGISTERED: %s\n' "$arg" >&2
    return 1
  }
  requested_physical=$(fm_project_physical_dir "$arg") || return 1
  records=$(fm_project_records)
  match_id=
  matches=0
  seen_ids='|'
  seen_paths='|'
  while IFS="$(printf '\034')" read -r id path mode yolo; do
    [ -n "$id" ] || continue
    case "$seen_ids" in
      *"|$id|"*) printf 'PROJECT_REGISTRY_INVALID: duplicate project id: %s\n' "$id" >&2; return 1 ;;
    esac
    seen_ids="${seen_ids}${id}|"
    case "$mode" in
      no-mistakes|validated-main|direct-PR|local-only) ;;
      *) printf 'PROJECT_REGISTRY_INVALID: unknown mode for %s: %s\n' "$id" "$mode" >&2; return 1 ;;
    esac
    if [ -z "$path" ]; then
      [ -f "$FM_PROJECT_HOME/.fm-secondmate-home" ] || continue
      path="$FM_PROJECT_HOME/projects/$id"
    fi
    physical=$(fm_project_validate_root "$id" "$path") || return 1
    case "$seen_paths" in
      *"|$physical|"*) printf 'PROJECT_REGISTRY_INVALID: duplicate canonical repository: %s\n' "$physical" >&2; return 1 ;;
    esac
    seen_paths="${seen_paths}${physical}|"
    if [ "$physical" = "$requested_physical" ]; then
      match_id=$id
      matches=$((matches + 1))
    fi
  done <<EOF
$records
EOF
  [ "$matches" -eq 1 ] || {
    printf 'PROJECT_PATH_NOT_REGISTERED: %s\n' "$arg" >&2
    return 1
  }
  fm_project_resolve "$match_id"
}

fm_project_normalize_remote() {
  local url=$1 rest host path
  case "$url" in
    file://*)
      path=${url#file://}
      fm_project_physical_dir "$path" 2>/dev/null || printf '%s\n' "$path"
      return
      ;;
    /*)
      fm_project_physical_dir "$url" 2>/dev/null || printf '%s\n' "$url"
      return
      ;;
    git@*:* )
      rest=${url#git@}
      host=${rest%%:*}
      path=${rest#*:}
      ;;
    ssh://*|http://*|https://*)
      rest=${url#*://}
      rest=${rest#*@}
      host=${rest%%/*}
      path=${rest#*/}
      ;;
    *) printf '%s\n' "${url%/}" | sed 's/\.git$//'; return ;;
  esac
  path=${path%/}
  path=${path%.git}
  printf '%s/%s\n' "$host" "$path"
}

fm_project_remote_identity() {
  local repo=$1 url
  url=$(git -C "$repo" remote get-url origin 2>/dev/null) || return 1
  [ -n "$url" ] || return 1
  fm_project_normalize_remote "$url"
}

# Returns success only when a task recorded without project_id belongs to a
# project that has since acquired an explicit canonical path. This keeps legacy
# teardown compatibility scoped to the specific unmigrated project.
fm_project_legacy_task_requires_identity() {
  local recorded=$1 records id path _mode _yolo recorded_physical candidate
  fm_project_init
  [ -f "$FM_PROJECT_REGISTRY" ] || return 1
  recorded_physical=$(fm_project_physical_dir "$recorded" 2>/dev/null || true)
  records=$(fm_project_records)
  while IFS="$(printf '\034')" read -r id path _mode _yolo; do
    [ -n "$id" ] || continue
    if [ -n "$path" ]; then
      candidate=$(fm_project_physical_dir "$path" 2>/dev/null || true)
      if { [ -n "$recorded_physical" ] && [ "$candidate" = "$recorded_physical" ]; } \
         || [ "$path" = "$recorded" ]; then
        return 0
      fi
    else
      candidate="$FM_PROJECT_HOME/projects/$id"
      candidate=$(fm_project_physical_dir "$candidate" 2>/dev/null || printf '%s\n' "$candidate")
      if { [ -n "$recorded_physical" ] && [ "$candidate" = "$recorded_physical" ]; } \
         || [ "$FM_PROJECT_HOME/projects/$id" = "$recorded" ]; then
        return 1
      fi
    fi
  done <<EOF
$records
EOF
  return 0
}

fm_project_common_dir() {
  local common
  common=$(git -C "$1" rev-parse --git-common-dir 2>/dev/null) || return 1
  case "$common" in
    /*) fm_project_physical_dir "$common" ;;
    *) fm_project_physical_dir "$1/$common" ;;
  esac
}

fm_project_verify_task_identity() {
  local project_id=$1 recorded_project=$2 worktree=$3 canonical_common recorded_physical recorded_common worktree_common
  fm_project_resolve "$project_id" || return 1
  canonical_common=$(fm_project_common_dir "$FM_PROJECT_PATH") || return 1
  recorded_physical=$(fm_project_physical_dir "$recorded_project" 2>/dev/null || true)
  recorded_common=$(fm_project_common_dir "$recorded_project" 2>/dev/null || true)
  worktree_common=$(fm_project_common_dir "$worktree" 2>/dev/null || true)
  if [ -z "$recorded_physical" ] || [ "$recorded_physical" != "$FM_PROJECT_PATH" ] \
     || [ -z "$recorded_common" ] || [ "$recorded_common" != "$canonical_common" ]; then
    printf 'PROJECT_IDENTITY_MISMATCH: task project for %s is not the canonical repository\n' "$project_id" >&2
    return 1
  fi
  if [ -z "$worktree_common" ] || [ "$worktree_common" != "$canonical_common" ]; then
    printf 'PROJECT_IDENTITY_MISMATCH: task worktree for %s is not linked to the canonical repository\n' "$project_id" >&2
    return 1
  fi
}
