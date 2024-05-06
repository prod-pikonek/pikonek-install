#!/usr/bin/env bash
#
# Checks for local or remote versions and branches
# This script if from pihole project

BUILD_ENV=prod
PIKONEK_AMD64="https://api.github.com/repos/prod-pikonek/pikonek-amd64/releases/latest"
PIKONEK_ARM64="https://api.github.com/repos/prod-pikonek/pikonek-arm64/releases/latest"
PIKONEK_ARMHF="https://api.github.com/repos/prod-pikonek/pikonek-armhf/releases/latest"
PIKONEK_INSTALL="https://api.github.com/repos/prod-pikonek/pikonek-install/releases/latest"

# Credit: https://stackoverflow.com/a/46324904
function json_extract() {
    local key=$1
    local json=$2

    local string_regex='"([^"\]|\\.)*"'
    local number_regex='-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?'
    local value_regex="${string_regex}|${number_regex}|true|false|null"
    local pair_regex="\"${key}\"[[:space:]]*:[[:space:]]*(${value_regex})"

    if [[ ${json} =~ ${pair_regex} ]]; then
        echo $(sed 's/^"\|"$//g' <<< "${BASH_REMATCH[1]}")
    else
        return 1
    fi
}

function get_local_branch() {
    # Return active branch
    cd "${1}" 2> /dev/null || return 1
    git rev-parse --abbrev-ref HEAD || return 1
}

function get_local_version() {
    # Return active version
    cd "${1}" 2> /dev/null || return 1
    git describe --long --dirty --tags 2> /dev/null || return 1
}

# Source the setupvars config file
# shellcheck disable=SC1091

if [[ "$2" == "remote" ]]; then
    ARCH=$(dpkg --print-architecture)
    GITHUB_VERSION_FILE="/etc/pikonek/GitHubVersions"

    rm -rf $GITHUB_VERSION_FILE

    if [ "$ARCH" == "amd64" ]; then
        GITHUB_CORE_VERSION="$(json_extract tag_name "$(curl -s ${PIKONEK_AMD64} 2> /dev/null)")"
    elif [ "$ARCH" == "amd64" ]; then
        GITHUB_CORE_VERSION="$(json_extract tag_name "$(curl -s ${PIKONEK_ARM64} 2> /dev/null)")"
    else
        GITHUB_CORE_VERSION="$(json_extract tag_name "$(curl -s ${PIKONEK_ARMHF} 2> /dev/null)")"
    fi
    
    echo -n "${GITHUB_CORE_VERSION}" >> "${GITHUB_VERSION_FILE}"
    chmod 644 "${GITHUB_VERSION_FILE}"

    GITHUB_SCRIPT_VERSION="$(json_extract tag_name "$(curl -s ${PIKONEK_INSTALL} 2> /dev/null)")"
    echo -n " ${GITHUB_SCRIPT_VERSION}" >> "${GITHUB_VERSION_FILE}"

else

    LOCAL_BRANCH_FILE="/etc/pikonek/localbranches"

    rm -rf $LOCAL_BRANCH_FILE

    CORE_BRANCH="$(get_local_branch /etc/pikonek)"
    echo -n "${CORE_BRANCH} " >> "${LOCAL_BRANCH_FILE}"
    chmod 644 "${LOCAL_BRANCH_FILE}"

    SCRIPT_BRANCH="$(get_local_branch /etc/.pikonek)"
    echo -n "${SCRIPT_BRANCH}" >> "${LOCAL_BRANCH_FILE}"


    LOCAL_VERSION_FILE="/etc/pikonek/localversions"

    rm -rf $LOCAL_VERSION_FILE

    CORE_VERSION="$(get_local_version /etc/pikonek)"
    echo -n "${CORE_VERSION} " >> "${LOCAL_VERSION_FILE}"
    chmod 644 "${LOCAL_VERSION_FILE}"

    SCRIPT_VERSION="$(get_local_version /etc/.pikonek)"
    echo -n "${SCRIPT_VERSION}" >> "${LOCAL_VERSION_FILE}"

fi