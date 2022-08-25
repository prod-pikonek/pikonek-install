#!/usr/bin/env bash
# script taken from pihole
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# Variables
ARCH=$(dpkg --print-architecture)
readonly PIKONEK_GIT_URL="https://github.com/beta-pikonek/pikonek-${ARCH}.git"
readonly PIKONEK_SCRIPTS_GIT_URL="https://github.com/beta-pikonek/pikonek-install.git"
readonly PIKONEK_FILES_DIR="/etc/pikonek"
readonly PIKONEK_SCRIPT_DIR="/etc/.pikonek"

# when --check-only is passed to this script, it will not perform the actual update
CHECK_ONLY=false
SKIP_INSTALL=true

# shellcheck disable=SC1090
source "${PIKONEK_SCRIPT_DIR}/install.sh"

GitCheckUpdateAvail() {
    local directory
    local curBranch
    directory="${1}"
    curdir=$PWD
    cd "${directory}" || return

    # Fetch latest changes in this repo
    git fetch --quiet origin

    # Check current branch. If it is master, then check for the latest available tag instead of latest commit.
    curBranch=$(git rev-parse --abbrev-ref HEAD)
    if [[ "${curBranch}" == "main" ]]; then
        # get the latest local tag
        LOCAL=$(git describe --abbrev=0 --tags main)
        # get the latest tag from remote
        REMOTE=$(git describe --abbrev=0 --tags origin/main)

    else
        # @ alone is a shortcut for HEAD. Older versions of git
        # need @{0}
        LOCAL="$(git rev-parse "@{0}")"

        # The suffix @{upstream} to a branchname
        # (short form <branchname>@{u}) refers
        # to the branch that the branch specified
        # by branchname is set to build on top of#
        # (configured with branch.<name>.remote and
        # branch.<name>.merge). A missing branchname
        # defaults to the current one.
        REMOTE="$(git rev-parse "@{upstream}")"
    fi


    if [[ "${#LOCAL}" == 0 ]]; then
        echo -e "\\n  ${COL_LIGHT_RED}Error: Local revision could not be obtained, please contact Pikonek Support"
        echo -e "  Additional debugging output:${COL_NC}"
        git status
        exit
    fi
    if [[ "${#REMOTE}" == 0 ]]; then
        echo -e "\\n  ${COL_LIGHT_RED}Error: Remote revision could not be obtained, please contact Pikonek Support"
        echo -e "  Additional debugging output:${COL_NC}"
        git status
        exit
    fi

    # Change back to original directory
    cd "${curdir}" || exit

    if [[ "${LOCAL}" != "${REMOTE}" ]]; then
        # Local branch is behind remote branch -> Update
        return 0
    else
        # Local branch is up-to-date or in a situation
        # where this updater cannot be used (like on a
        # branch that exists only locally)
        return 1
    fi
}

main() {
    local basicError="\\n  ${COL_LIGHT_RED}Unable to complete update, please contact Pikonek ${COL_NC}"
    # shellcheck disable=1090,2154
    local core_update
    local script_update

    # Install package
    install_dependent_packages "${INSTALLER_DEPS[@]}"

    # This is unlikely
    if ! is_repo "${PIKONEK_FILES_DIR}" ; then
        echo -e "\\n  ${COL_LIGHT_RED}Error: Core Pikonek repo is missing from system!"
        echo -e "  Please re-run install script from https://github.com/beta-pikonek/pikonek-install${COL_NC}"
        exit 1;
    fi

    echo -e "  ${INFO} Checking for updates..."

    if GitCheckUpdateAvail "${PIKONEK_FILES_DIR}" ; then
        core_update=true
        echo -e "  ${INFO} Pikonek Core:\\t${COL_YELLOW}update available${COL_NC}"
    else
        core_update=false
        echo -e "  ${INFO} Pikonek Core:\\t${COL_LIGHT_GREEN}up to date${COL_NC}"
    fi

    if GitCheckUpdateAvail "${PIKONEK_SCRIPT_DIR}" ; then
        script_update=true
        echo -e "  ${INFO} Pikonek Script:\\t${COL_YELLOW}update available${COL_NC}"
    else
        script_update=false
        echo -e "  ${INFO} Pikonek Script:\\t${COL_LIGHT_GREEN}up to date${COL_NC}"
    fi

    if [[ "${core_update}" == false && "${script_update}" == false ]]; then
        echo ""
        echo -e "  ${TICK} Everything is up to date!"
        exit 0
    fi

    if [[ "${CHECK_ONLY}" == true ]]; then
        echo ""
        exit 0
    fi

    if [[ "${script_update}" == true ]]; then
        echo ""
        echo -e "  ${INFO} Pikonek script files out of date, updating local repo."
        getGitFiles "${PIKONEK_SCRIPT_DIR}" "${PIKONEK_SCRIPTS_GIT_URL}"
        # echo -e "  ${INFO} If you had made any changes in '/etc/.pikonek/', they have been stashed using 'git stash'"
    fi

    if [[ "${core_update}" == true ]]; then
        echo ""
        echo -e "  ${INFO} Pikonek core files out of date, updating local repo."
        getGitFiles "${PIKONEK_FILES_DIR}" "${PIKONEK_GIT_URL}"
        # echo -e "  ${INFO} If you had made any changes in '/etc/pikonek/', they have been stashed using 'git stash'"
    fi

    if [[ "${core_update}" == true || "${script_update}" == true ]]; then
        ${PIKONEK_SCRIPT_DIR}/install.sh --update || \
            echo -e "${basicError}" && exit 1
    fi

    if [[ "${core_update}" == true || "${script_update}" == true ]]; then
        # Force an update of the updatechecker
        /etc/.pikonek/updatecheck.sh
        /etc/.pikonek/updatecheck.sh x remote
        echo -e "  ${INFO} Local version file information updated."
    fi

    echo ""
    exit 0
}

if [[ "$1" == "--check-only" ]]; then
    CHECK_ONLY=true
fi

main