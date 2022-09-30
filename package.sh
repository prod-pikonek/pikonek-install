#!/usr/bin/env bash
# shellcheck disable=SC1090
# source taken from pihole 2017 Pi-hole, LLC (https://pi-hole.net)

readonly PIKONEK_FILES_DIR="/etc/pikonek"
readonly PIKONEK_SCRIPT_DIR="/etc/.pikonek"
SKIP_INSTALL="true"
source "${PIKONEK_SCRIPT_DIR}/install.sh"

main() {
    PACKAGE="${2}"

    if [[ "${INSTALL_PACKAGE}" == true ]]; then
        if [[ "${PACKAGE}" == "pppoe" ]]; then
            configurePPPoE
        fi

        if [[ "${PACKAGE}" == "sqm" ]]; then
            configureSQM
        fi
    fi
}

if [[ "$1" == "--install" ]]; then
    INSTALL_PACKAGE=true
fi

if [[ "$1" == "--uninstall" ]]; then
    INSTALL_PACKAGE=false
fi

main "$@"