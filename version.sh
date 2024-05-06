#!/usr/bin/env bash
# Script taken from pihole
#
# Show version numbers
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# Variables
DEFAULT="-1"
COREGITDIR="/etc/pikonek/"
SCRIPTGITDIR="/etc/.pikonek/"
BUILD_ENV=prod

# Source the setupvars config file
# shellcheck disable=SC1091

getLocalVersion() {

    # Get the tagged version of the local repository
    local directory="${1}"
    local version

    cd "${directory}" 2> /dev/null || { echo "${DEFAULT}"; return 1; }
    version=$(git describe --tags --always || echo "$DEFAULT")
    if [[ "${version}" =~ ^v ]]; then
        echo "${version}"
    elif [[ "${version}" == "${DEFAULT}" ]]; then
        echo "ERROR"
        return 1
    else
        echo "Untagged"
    fi
    return 0
}

getLocalHash() {

    # Get the short hash of the local repository
    local directory="${1}"
    local hash

    cd "${directory}" 2> /dev/null || { echo "${DEFAULT}"; return 1; }
    hash=$(git rev-parse --short HEAD || echo "$DEFAULT")
    if [[ "${hash}" == "${DEFAULT}" ]]; then
        echo "ERROR"
        return 1
    else
        echo "${hash}"
    fi
    return 0
}

getRemoteHash(){
    local daemon="${1}"
    local branch="${2}"

    hash=$(git ls-remote --heads "https://github.com/prod-pikonek/${daemon}" | \
        awk -v bra="$branch" '$0~bra {print substr($0,0,8);exit}')
    if [[ -n "$hash" ]]; then
        echo "$hash"
    else
        echo "ERROR"
        return 1
    fi
    return 0
}

getRemoteVersion(){
    # Get the version from the remote origin
    local daemon="${1}"
    local version
    local cachedVersions
    local arrCache
    cachedVersions="/etc/pikonek/GitHubVersions"

    #If the above file exists, then we can read from that. Prevents overuse of GitHub API
    if [[ -f "$cachedVersions" ]]; then
        IFS=' ' read -r -a arrCache < "$cachedVersions"

        case $daemon in
            "pikonek"   )  echo "${arrCache[0]}";;
            "pikonek-install"  ) echo "${arrCache[1]}";;
        esac

        return 0
    fi

    version=$(curl --silent --fail "https://api.github.com/repos/prod-pikonek/${daemon}/releases/latest" | \
    awk -F: '$1 ~/tag_name/ { print $2 }' | \
    tr -cd '[[:alnum:]]._-')
    
    if [[ "${version}" =~ ^v ]]; then
        echo "${version}"
    else
        echo "ERROR"
        return 1
    fi
    return 0
}

getLocalBranch(){
    # Get the checked out branch of the local directory
    local directory="${1}"
    local branch

    cd "${directory}" 2> /dev/null || { echo "${DEFAULT}"; return 1; }
    branch=$(git rev-parse --abbrev-ref HEAD || echo "$DEFAULT")

    if [[ ! "${branch}" =~ ^v ]]; then
        if [[ "${branch}" == "main" ]]; then
            echo ""
        elif [[ "${branch}" == "HEAD" ]]; then
            echo "in detached HEAD state at "
        else
            echo "${branch} "
        fi
    else
        # Branch started in "v"
        echo "release "
    fi
    return 0
}

versionOutput() {

    [[ "$1" == "pikonek" ]] && GITDIR=$COREGITDIR
    [[ "$1" == "pikonek-install" ]] && GITDIR=$SCRIPTGITDIR

    [[ "$2" == "-c" ]] || [[ "$2" == "--current" ]] || [[ -z "$2" ]] && current=$(getLocalVersion $GITDIR) && branch=$(getLocalBranch $GITDIR)
    [[ "$2" == "-l" ]] || [[ "$2" == "--latest" ]] || [[ -z "$2" ]] && latest=$(getRemoteVersion "$1")
    if [[ "$2" == "-h" ]] || [[ "$2" == "--hash" ]]; then
        [[ "$3" == "-c" ]] || [[ "$3" == "--current" ]] || [[ -z "$3" ]] && curHash=$(getLocalHash "$GITDIR") && branch=$(getLocalBranch $GITDIR)
        [[ "$3" == "-l" ]] || [[ "$3" == "--latest" ]] || [[ -z "$3" ]] && latHash=$(getRemoteHash "$1" "$(cd "$GITDIR" 2> /dev/null && git rev-parse --abbrev-ref HEAD)")
    fi
    if [[ -n "$current" ]] && [[ -n "$latest" ]]; then
        output="${1^} version is $branch$current (Latest: $latest)"
    elif [[ -n "$current" ]] && [[ -z "$latest" ]]; then
        output="Current ${1^} version is $branch$current"
    elif [[ -z "$current" ]] && [[ -n "$latest" ]]; then
        output="Latest ${1^} version is $latest"
    elif [[ "$curHash" == "N/A" ]] || [[ "$latHash" == "N/A" ]]; then
        output="${1^} hash is not applicable"
    elif [[ -n "$curHash" ]] && [[ -n "$latHash" ]]; then
        output="${1^} hash is $curHash (Latest: $latHash)"
    elif [[ -n "$curHash" ]] && [[ -z "$latHash" ]]; then
        output="Current ${1^} hash is $curHash"
    elif [[ -z "$curHash" ]] && [[ -n "$latHash" ]]; then
        output="Latest ${1^} hash is $latHash"
    else
        errorOutput
        return 1
    fi

    [[ -n "$output" ]] && echo "  $output"
}

errorOutput() {
    echo "  Invalid Option! Try 'pikonek -v --help' for more information."
    exit 1
}

defaultOutput() {
    versionOutput "pikonek" "$@"
    versionOutput "pikonek-install" "$@"
}

helpFunc() {
    echo "Usage: pikonek -v [repo | option] [option]
Example: 'pikonek -v -p -l'
Show Pikonek & Pikonek Scripts versions

Repositories:
  -p, --pikonek           Only retrieve info regarding Pikonek repository
  -ps, --pikonek-install  Only retrieve info regarding Pikonek script repository

Options:
  -c, --current        Return the current version
  -l, --latest         Return the latest version
  --hash               Return the GitHub hash from your local repositories
  -h, --help           Show this help dialog"
  exit 0
}

case "${1}" in
    "-p" | "--pikonek"    ) shift; versionOutput "pikonek" "$@";;
    "-ps" | "--pikonek-install"     ) shift; versionOutput "pikonek-install" "$@";;
    "-h" | "--help"      ) helpFunc;;
    *                    ) defaultOutput "$@";;
esac