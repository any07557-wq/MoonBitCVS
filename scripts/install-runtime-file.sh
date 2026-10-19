#!/usr/bin/env bash
# Same-directory rename avoids ETXTBSY and torn runtime-file replacement.
# This provides atomic visibility, not a journalled multi-file runtime upgrade.
set -euo pipefail
[[ "$#" -eq 3 ]] || { echo 'Usage: install-runtime-file.sh SOURCE DESTINATION MODE' >&2; exit 1; }
MOONVCS_INSTALL_SOURCE="$1"
MOONVCS_INSTALL_DESTINATION="$2"
MOONVCS_INSTALL_MODE="$3"
case "$MOONVCS_INSTALL_MODE" in 0644|0755) ;; *) exit 1 ;; esac
[[ -f "$MOONVCS_INSTALL_SOURCE" ]]
[[ ! -d "$MOONVCS_INSTALL_DESTINATION" ]]
MOONVCS_INSTALL_TEMP="$(mktemp "$MOONVCS_INSTALL_DESTINATION.install.XXXXXX")"
trap 'rm -f -- "$MOONVCS_INSTALL_TEMP"' EXIT
cp -- "$MOONVCS_INSTALL_SOURCE" "$MOONVCS_INSTALL_TEMP"
chmod "$MOONVCS_INSTALL_MODE" "$MOONVCS_INSTALL_TEMP"
mv -fT -- "$MOONVCS_INSTALL_TEMP" "$MOONVCS_INSTALL_DESTINATION"
