#!/usr/bin/env bash

_SOURCE_PATCH_TREES=()
_SOURCE_PATCH_FILES=()

require_clean_source()
{
    local tree="$1"
    if [[ "$(git -C "$tree" rev-parse --show-toplevel)" != "$(cd "$tree" && pwd -P)" ]] ||
            ! git -C "$tree" diff --quiet --ignore-submodules=none HEAD ||
            [[ -n "$(git -C "$tree" ls-files --others --exclude-standard)" ]]; then
        echo "Dependency source has local changes: $tree" >&2
        return 1
    fi
}

apply_source_patches()
{
    local tree="$1" patch
    shift
    require_clean_source "$tree" || return 1
    for patch in "$@"; do
        git -C "$tree" apply --check "$patch" || return 1
        git -C "$tree" apply "$patch" || return 1
        _SOURCE_PATCH_TREES+=("$tree")
        _SOURCE_PATCH_FILES+=("$patch")
    done
}

restore_source_patches()
{
    local index failed=0
    for ((index=${#_SOURCE_PATCH_FILES[@]}-1; index>=0; index--)); do
        if ! git -C "${_SOURCE_PATCH_TREES[index]}" apply --reverse --check "${_SOURCE_PATCH_FILES[index]}" ||
                ! git -C "${_SOURCE_PATCH_TREES[index]}" apply --reverse "${_SOURCE_PATCH_FILES[index]}"; then
            echo "Cannot restore dependency patch; preserve the tree for inspection: ${_SOURCE_PATCH_FILES[index]}" >&2
            failed=1
        fi
    done
    return "$failed"
}
