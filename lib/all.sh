#!/usr/bin/env bash
# Sources all libs. Use this in bin/ scripts.
_dir="$(dirname "${BASH_SOURCE[0]}")"
source "$_dir/config.sh"
source "$_dir/detect.sh"
source "$_dir/actions.sh"
source "$_dir/ui.sh"
source "$_dir/compute.sh"
