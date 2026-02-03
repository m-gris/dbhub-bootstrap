#!/usr/bin/env bash
# User interaction. Thin wrappers around gum.

confirm() { gum confirm "$1"; }
choose()  { gum choose --header "$1"; }
input()   { gum input --placeholder "$1"; }
spin()    { gum spin --title "$1" -- "${@:2}"; }
success() { gum style --border normal --padding "1 2" --foreground 2 "$@"; }
warn()    { gum style --foreground 3 "⚠ $1"; }
fail()    { gum style --foreground 1 "✗ $1" >&2; }
