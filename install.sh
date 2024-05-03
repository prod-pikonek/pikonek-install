#!/usr/bin/env bash
# shellcheck disable=SC1090
#
# Pi-hole: A black hole for Internet advertisements
# (c) Pi-hole (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Installs and Updates Pi-hole
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

set -e

# List of supported DNS servers
DNS_SERVERS=$(cat << EOM
Google (ECS);8.8.8.8;8.8.4.4;2001:4860:4860:0:0:0:0:8888;2001:4860:4860:0:0:0:0:8844
OpenDNS (ECS);208.67.222.222;208.67.220.220;2620:119:35::35;2620:119:53::53
Level3;4.2.2.1;4.2.2.2;;
Comodo;8.26.56.26;8.20.247.20;;
DNS.WATCH;84.200.69.80;84.200.70.40;2001:1608:10:25:0:0:1c04:b12f;2001:1608:10:25:0:0:9249:d69b
Quad9 (filtered, DNSSEC);9.9.9.9;149.112.112.112;2620:fe::fe;2620:fe::9
Quad9 (unfiltered, no DNSSEC);9.9.9.10;149.112.112.10;2620:fe::10;2620:fe::fe:10
Quad9 (filtered + ECS);9.9.9.11;149.112.112.11;2620:fe::11;
Cloudflare;1.1.1.1;1.0.0.1;2606:4700:4700::1111;2606:4700:4700::1001
EOM
)
ARCH=$(dpkg --print-architecture)
PIKONEK_LOCAL_REPO="/etc/pikonek"
# This directory is where the PiKonek scripts will be installed
PIKONEK_INSTALL_DIR="/etc/.pikonek"
# shellcheck disable=SC2034
webroot="/var/www/html"
pikonekScriptGitUrl="https://github.com/prod-pikonek/pikonek-install.git"
pikonekGitUrl="https://github.com/prod-pikonek/pikonek-${ARCH}.git"
pikonekPPPoeUrl="https://github.com/prod-pikonek/rp-pppoe.git"
pikonekSQMUrl="https://github.com/prod-pikonek/sqm-scripts.git"
CMDLINE=/proc/cmdline

PIKONEK_BIN_DIR="/usr/local/bin"
PIKONEK_TIME_ZONE="UTC"
useUpdate=false
if [ -z "$useUpdate" ]; then
    useUpdate=false
fi
# PiKonek needs an IP address; to begin, these variables are empty since we don't know what the IP is until
# this script can run
IPV4_ADDRESS=${IPV4_ADDRESS}
IPV6_ADDRESS=${IPV6_ADDRESS}
LIGHTTPD_USER="www-data"
LIGHTTPD_GROUP="www-data"
# and config file
LIGHTTPD_CFG="lighttpd.conf"
COUNTRY="PH"

if [ -z "${USER}" ]; then
  USER="$(id -un)"
fi

is_pi() {
  ARCH=$(dpkg --print-architecture)
  if [ "$ARCH" = "armhf" ] || [ "$ARCH" = "arm64" ] ; then
    echo 0
  else
    echo 1
  fi
}

# export license
export PYARMOR_LICENSE=/etc/pikonek/license/license.lic

# if [ $(is_pi) -eq 0 ]; then
#   if cat /etc/*release | grep -q "Raspbian"; then
#     CMDLINE=/boot/cmdline.txt
#   fi
# else
#   CMDLINE=/proc/cmdline
# fi


# Check if we are running on a real terminal and find the rows and columns
# If there is no real terminal, we will default to 80x24
if [ -t 0 ] ; then
  screen_size=$(stty size)
else
  screen_size="24 80"
fi
# Set rows variable to contain first number
printf -v rows '%d' "${screen_size%% *}"
# Set columns variable to contain second number
printf -v columns '%d' "${screen_size##* }"

# Divide by two so the dialogs take up half of the screen, which looks nice.
r=$(( rows / 2 ))
c=$(( columns / 2 ))
# Unless the screen is tiny
r=$(( r < 20 ? 20 : r ))
c=$(( c < 70 ? 70 : c ))

######## Undocumented Flags. Shhh ########
skipSpaceCheck=false

for var in "$@"; do
    case "$var" in
        "--update" ) useUpdate=true;;
    esac
done

# Set these values so the installer can still run in color
COL_NC='\e[0m' # No Color
COL_LIGHT_GREEN='\e[1;32m'
COL_LIGHT_RED='\e[1;31m'
TICK="[${COL_LIGHT_GREEN}✓${COL_NC}]"
CROSS="[${COL_LIGHT_RED}✗${COL_NC}]"
INFO="[i]"
# shellcheck disable=SC2034
DONE="${COL_LIGHT_GREEN} done!${COL_NC}"
OVER="\\r\\033[K"

# A simple function that just echoes out our logo in ASCII format
show_ascii_berry() {
    echo -e "
    ${COL_LIGHT_RED}         ____  _ _  __                _    
            |  _ \(_) |/ /___  _ __   ___| | __
            | |_) | | ' // _ \| '_ \ / _ \ |/ /
            |  __/| | . \ (_) | | | |  __/   < 
            |_|   |_|_|\_\___/|_| |_|\___|_|\_\.${COL_NC}
    "
}



is_command() {
    # Checks for existence of string passed in as only function argument.
    # Exit value of 0 when exists, 1 if not exists. Value is the result
    # of the `command` shell built-in call.
    local check_command="$1"

    command -v "${check_command}" >/dev/null 2>&1
}

os_check() {
    local remote_os_domain valid_os valid_version detected_os_pretty detected_os detected_version display_warning
    remote_os_domain="Ubuntu=18 Orange=18"
    remote_supported_arch="arm64 amd64 armhf"
    valid_os=false
    valid_version=false
    valid_architecture=false
    display_warning=true

    detected_os_pretty=$(cat /etc/*release | grep PRETTY_NAME | cut -d '=' -f2- | tr -d '"')
    detected_os="${detected_os_pretty%% *}"
    detected_version=$(cat /etc/*release | grep VERSION_ID | cut -d '=' -f2- | tr -d '"')
    detected_arch=$(dpkg --print-architecture)

    IFS=" " read -r -a supportedOS < <(echo ${remote_os_domain} | tr -d '"')
    IFS1=" " read -r -a supportedARCH < <(echo ${remote_supported_arch} | tr -d '"')

    for i in "${supportedOS[@]}"
    do
        os_part=$(echo "$i" | cut -d '=' -f1)
        versions_part=$(echo "$i" | cut -d '=' -f2-)

        if [[ "${detected_os}" =~ ${os_part} ]]; then
          OS="${detected_os}"
          valid_os=true
          IFS="," read -r -a supportedVer <<<"${versions_part}"
          for x in "${supportedVer[@]}"
          do
            if [[ "${detected_version}" =~ $x ]];then
              valid_version=true
              break
            fi
          done
          break
        fi
    done

    for i in "${supportedARCH[@]}"
    do
        arch_part=$(echo "$i")

        if [[ "${detected_arch}" =~ ${arch_part} ]]; then
          arch="${detected_arch}"
          valid_architecture=true
          break
        fi
    done

    if [ "$valid_os" = true ] && [ "$valid_version" = true ] && [ "$valid_architecture" = true ]; then
        display_warning=false
    fi

    if [ "$display_warning" = true ] && [ "$pikonek_SKIP_OS_CHECK" != true ]; then
        printf "  %b %bUnsupported OS detected%b\\n" "${CROSS}" "${COL_LIGHT_RED}" "${COL_NC}"
        printf "      Please check supported os at https://pikonek.gitbook.io/\\n"
        printf "\\n"
        exit 1
    else
        printf "  %b %bSupported OS detected%b\\n" "${TICK}" "${COL_LIGHT_GREEN}" "${COL_NC}"
    fi
}

nic_check() {
    local str="Check network interface..."
    printf "  %b %s...\\n" "${INFO}" "${str}"
    interfacesNic="$(ip --oneline link show | grep -v lo | awk '{print $2}' | cut -d':' -f1 | cut -d'@' -f1 | grep -v wl)"
    nicCount=$(wc -l <<< "${interfacesNic}")
    if [[ "${nicCount}" -ge 2 ]]; then
        printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
    else
        printf "  %b %bYou must have atleast two network lan interface%b\\n" "${CROSS}" "${COL_LIGHT_RED}" "${COL_NC}"
        printf "\\n"
        exit 1
    fi
}

# Compatibility
distro_check() {
    # If apt-get is installed, then we know it's part of the Debian family
    if is_command apt-get ; then
        # Set some global variables here
        # We don't set them earlier since the family might be Red Hat, so these values would be different
        PKG_MANAGER="apt-get"
        # A variable to store the command used to update the package cache
        UPDATE_PKG_CACHE="${PKG_MANAGER} update"
        # An array for something...
        PKG_INSTALL=("${PKG_MANAGER}" -y -qq --no-install-recommends install)
        # grep -c will return 1 retVal on 0 matches, block this throwing the set -e with an OR TRUE
        PKG_COUNT="${PKG_MANAGER} -s -o Debug::NoLocking=true upgrade | grep -c ^Inst || true"
        # Some distros vary slightly so these fixes for dependencies may apply
        # on Ubuntu 18.04.1 LTS we need to add the universe repository to gain access to dhcpcd5
        APT_SOURCES="/etc/apt/sources.list"
        if awk 'BEGIN{a=1;b=0}/bionic main/{a=0}/bionic.*universe/{b=1}END{exit a + b}' ${APT_SOURCES}; then
            if ! whiptail --defaultno --title "Dependencies Require Update to Allowed Repositories" --yesno "Would you like to enable 'universe' repository?\\n\\nThis repository is required by the following packages:\\n\\n- dhcpcd5" "${r}" "${c}"; then
                printf "  %b Aborting installation: Dependencies could not be installed.\\n" "${CROSS}"
                exit 1 # exit the installer
            else
                printf "  %b Enabling universe package repository for Ubuntu Bionic\\n" "${INFO}"
                cp -p ${APT_SOURCES} ${APT_SOURCES}.backup # Backup current repo list
                printf "  %b Backed up current configuration to %s\\n" "${TICK}" "${APT_SOURCES}.backup"
                add-apt-repository universe
                printf "  %b Enabled %s\\n" "${TICK}" "'universe' repository"
            fi
        fi
        # Update package cache. This is required already here to assure apt-cache calls have package lists available.
        update_package_cache || exit 1
        # Debian 7 doesn't have iproute2 so check if it's available first
        if apt-cache show iproute2 > /dev/null 2>&1; then
            iproute_pkg="iproute2"
        # Otherwise, check if iproute is available
        elif apt-cache show iproute > /dev/null 2>&1; then
            iproute_pkg="iproute"
        # Else print error and exit
        else
            printf "  %b Aborting installation: iproute2 and iproute packages were not found in APT repository.\\n" "${CROSS}"
            exit 1
        fi
        # Check for and determine version number (major and minor) of current python install
        if is_command python3.7 ; then
            printf "  %b Existing python3.7 installation detected\\n" "${INFO}"
            pythonNewer=true
        fi
        # Check if installed python3.7 to determine packages to install
        if [[ "$pythonNewer" != true ]]; then
            # Prefer the python3.7 metapackage if it's there
            if apt-cache show python3.7 > /dev/null 2>&1; then
                python3Ver="python3.7"
            # Else print error and exit
            else
                printf "  %b Aborting installation: No Python3.7 packages were found in APT repository.\\n" "${CROSS}"
                exit 1
            fi
        else
            python3Ver="python3.7"
        fi
        # Since our install script is so large, we need several other programs to successfully get a machine provisioned
        # These programs are stored in an array so they can be looped through later
        if [ "$ARCH" = "arm64" ] ; then
            INSTALLER_DEPS=(build-essential python3.7-dev python3-venv python3.7-venv virt-what libssl-dev libffi-dev ipcalc lighttpd python3.7 sqlite3 dnsmasq dnsmasq-utils vlan bridge-utils gawk curl cron wget iptables ipset whiptail git openssl ifupdown ntp wpasupplicant gnupg lsb-release ca-certificates mosquitto)
        else
            INSTALLER_DEPS=(build-essential gcc-multilib python3.7-dev python3-venv python3.7-venv virt-what libssl-dev libffi-dev ipcalc lighttpd python3.7 sqlite3 dnsmasq dnsmasq-utils vlan bridge-utils gawk curl cron wget iptables ipset whiptail git openssl ifupdown ntp wpasupplicant gnupg lsb-release ca-certificates mosquitto)
        fi
        # A function to check...
        test_dpkg_lock() {
            # An iterator used for counting loop iterations
            i=0
            # fuser is a program to show which processes use the named files, sockets, or filesystems
            # So while the command is true
            while fuser /var/lib/dpkg/lock >/dev/null 2>&1 ; do
                # Wait half a second
                sleep 0.5
                # and increase the iterator
                ((i=i+1))
            done
            # Always return success, since we only return if there is no
            # lock (anymore)
            return 0
        }

    # If apt-get is not found, check for rpm to see if it's a Red Hat family OS
    # If neither apt-get
    else
        # it's not an OS we can support,
        printf "  %b OS distribution not supported\\n" "${CROSS}"
        # so exit the installer
        exit
    fi
}

# A function for checking if a directory is a git repository
is_repo() {
    # Use a named, local variable instead of the vague $1, which is the first argument passed to this function
    # These local variables should always be lowercase
    local directory="${1}"
    # A variable to store the return code
    local rc
    # If the first argument passed to this function is a directory,
    if [[ -d "${directory}" ]]; then
        # move into the directory
        pushd "${directory}" &> /dev/null || return 1
        # Use git to check if the directory is a repo
        # git -C is not used here to support git versions older than 1.8.4
        git status --short &> /dev/null || rc=$?
    # If the command was not successful,
    else
        # Set a non-zero return code if directory does not exist
        rc=1
    fi
    # Move back into the directory the user started in
    popd &> /dev/null || return 1
    # Return the code; if one is not set, return 0
    return "${rc:-0}"
}

# A function to clone a repo
make_repo() {
    # Set named variables for better readability
    local directory="${1}"
    local remoteRepo="${2}"

    # The message to display when this function is running
    str="Clone ${remoteRepo} into ${directory}"
    # Display the message and use the color table to preface the message with an "info" indicator
    printf "  %b %s...\\n" "${INFO}" "${str}"
    # If the directory exists,
    if [[ -d "${directory}" ]]; then
        # delete everything in it so git can clone into it
        rm -rf "${directory}"
    fi
    # Clone the repo and return the return code from this command
    git clone -q --depth 20 "${remoteRepo}" "${directory}" &> /dev/null || return $?
    # Move into the directory that was passed as an argument
    pushd "${directory}" &> /dev/null || return 1
    # Data in the repositories is public anyway so we can make it readable by everyone (+r to keep executable permission if already set by git)
    chmod -R a+rX "${directory}"
    # Move back into the original directory
    popd &> /dev/null || return 1
    return 0
}

# We need to make sure the repos are up-to-date so we can effectively install Clean out the directory if it exists for git to clone into
update_repo() {
    # Use named, local variables
    # As you can see, these are the same variable names used in the last function,
    # but since they are local, their scope does not go beyond this function
    # This helps prevent the wrong value from being assigned if you were to set the variable as a GLOBAL one
    local directory="${1}"
    local curBranch

    # A variable to store the message we want to display;
    # Again, it's useful to store these in variables in case we need to reuse or change the message;
    # we only need to make one change here
    local str="Update repo in ${1}"
    # Move into the directory that was passed as an argument
    pushd "${directory}" &> /dev/null || return 1
    # Let the user know what's happening
    printf "  %b %s...\\n" "${INFO}" "${str}"
    # Stash any local commits as they conflict with our working code
    git stash --quiet &> /dev/null || true # Okay for stash failure
    git clean --quiet --force -d || true # Okay for already clean directory
    # Pull the latest commits
    git pull --quiet &> /dev/null || return $?
    # Check current branch. If it is master, then reset to the latest available tag.
    # In case extra commits have been added after tagging/release (i.e in case of metadata updates/README.MD tweaks)
    curBranch=$(git rev-parse --abbrev-ref HEAD)
    if [[ "${curBranch}" == "main" ]]; then
        git reset --hard "$(git describe --abbrev=0 --tags)" || return $?
    fi
    # Show a completion message
    printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
    # Data in the repositories is public anyway so we can make it readable by everyone (+r to keep executable permission if already set by git)
    chmod -R a+rX "${directory}"
    # Move back into the original directory
    popd &> /dev/null || return 1
    return 0
}

# A function that combines the functions previously made
getGitFiles() {
    # Setup named variables for the git repos
    # We need the directory
    local directory="${1}"
    # as well as the repo URL
    local remoteRepo="${2}"
    # A local variable containing the message to be displayed
    local str="Check for existing repository in ${1}"
    # Show the message
    printf "  %b %s...\\n" "${INFO}" "${str}"
    # Check if the directory is a repository
    if is_repo "${directory}"; then
        # Show that we're checking it
        printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
        # Update the repo, returning an error message on failure
        update_repo "${directory}" || { printf "\\n  %b: Could not update local repository. Contact support.%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"; exit 1; }
    # If it's not a .git repo,
    else
        # Show an error
        printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
        # Attempt to make the repository, showing an error on failure
        make_repo "${directory}" "${remoteRepo}" || { printf "\\n  %bError: Could not create local repository. Contact support.%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"; exit 1; }
    fi
    # echo a blank line
    echo ""
    # and return success?
    return 0
}

# Reset a repo to get rid of any local changed
resetRepo() {
    # Use named variables for arguments
    local directory="${1}"
    # Move into the directory
    pushd "${directory}" &> /dev/null || return 1
    # Store the message in a variable
    str="Resetting repository within ${1}..."
    # Show the message
    printf "  %b %s..." "${INFO}" "${str}"
    # Use git to remove the local changes
    git reset --hard &> /dev/null || return $?
    # Data in the repositories is public anyway so we can make it readable by everyone (+r to keep executable permission if already set by git)
    chmod -R a+rX "${directory}"
    # And show the status
    printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
    # Return to where we came from
    popd &> /dev/null || return 1
    # Returning success anyway?
    return 0
}

# install docker-cli and docker compose
installDocker() {
    local str="Installing docker engine"
    printf "%b  %b %s...\\n" "${OVER}" "${INFO}" "${str}"
     # If the directory exists,
    if [[ -d /etc/apt/keyrings ]]; then
        rm -rf /etc/apt/keyrings/**
    else
        mkdir -p /etc/apt/keyrings
    fi
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg &> /dev/null
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    # update package cache
    update_package_cache
    DOCKER_DEPS=(docker-ce docker-ce-cli containerd.io docker-compose-plugin)
    # Install packages used by this installation script
    install_dependent_packages "${DOCKER_DEPS[@]}"
    printf "%b  %b %s...\\n" "${OVER}" "${TICK}" "${str}"
}

find_IPv4_information() {
    # Detects IPv4 address used for communication to WAN addresses.
    # Accepts no arguments, returns no values.

    # Named, local variables
    local route
    local IPv4bare

    # Find IP used to route to outside world by checking the the route to Google's public DNS server
    route=$(ip route get 8.8.8.8)

    # Get just the interface IPv4 address
    # shellcheck disable=SC2059,SC2086
    # disabled as we intentionally want to split on whitespace and have printf populate
    # the variable with just the first field.
    printf -v IPv4bare "$(printf ${route#*src })"
    # Get the default gateway IPv4 address (the way to reach the Internet)
    # shellcheck disable=SC2059,SC2086
    printf -v IPv4gw "$(printf ${route#*via })"
    printf -v IPv4interface "$(printf ${route#*dev })"

    if ! valid_ip "${IPv4bare}" ; then
        IPv4bare="127.0.0.1"
    fi

    # Append the CIDR notation to the IP address, if valid_ip fails this should return 127.0.0.1/8
    IPV4_ADDRESS=$(ip -oneline -family inet address show | grep "${IPv4bare}/" |  awk '{print $4}' | awk 'END {print}')
}

# Get available interfaces that are UP
get_available_interfaces() {
    # There may be more than one so it's all stored in a variable
    # availableInterfaces="$(ip --oneline link show up | grep -v lo | awk '{print $2}' | cut -d':' -f1 | cut -d'@' -f1 | grep eth)"
    availableInterfaces="$(ip --oneline link show up | grep -v lo | awk '{print $2}' | cut -d':' -f1 | cut -d'@' -f1 | grep -v wl)"
}

# Get available interfaces
get_available_lan_interfaces() {
    # There may be more than one so it's all stored in a variable
    # availableInterfaces="$(ip --oneline link show up | grep -v lo | awk '{print $2}' | cut -d':' -f1 | cut -d'@' -f1 | grep eth)"
    availableLanInterfaces="$(ip --oneline link show | grep -v lo | awk '{print $2}' | cut -d':' -f1 | cut -d'@' -f1 | grep -v wl)"
}

get_available_wlan_interfaces() {
    # There may be more than one so it's all stored in a variable
    availableWlanInterfaces="$(ip --oneline link show | grep wl | awk '{print $2}' | cut -d':' -f1 | cut -d'@' -f1)"
}

# A function for displaying the dialogs the user sees when first running the installer
welcomeDialogs() {
    # Display the welcome dialog using an appropriately sized window via the calculation conducted earlier in the script
    whiptail --msgbox --backtitle "Welcome" --title "PiKonek automated installer" "\\n\\nWelcome to PiKonek a Coin Operated Wifi Vending Machine!" "${r}" "${c}"

    # Explain the need for a static address
    whiptail --msgbox --backtitle "Welcome" --title "PiKonek automated installer" "\\n\\nThe PiKonek is a SERVER so it needs an internet and STATIC IP ADDRESS to function properly." "${r}" "${c}"
}

# We need to make sure there is enough space before installing, so there is a function to check this
verifyFreeDiskSpace() {
    # 50MB is the minimum space needed (45MB install (includes web admin bootstrap/jquery libraries etc) + 5MB one day of logs.)
    # - Fourdee: Local ensures the variable is only created, and accessible within this function/void. Generally considered a "good" coding practice for non-global variables.
    local str="Disk space check"
    # Required space in KB
    local required_free_kilobytes=3000000
    # Calculate existing free space on this machine
    local existing_free_kilobytes
    existing_free_kilobytes=$(df -Pk | grep -m1 '\/$' | awk '{print $4}')

    # If the existing space is not an integer,
    if ! [[ "${existing_free_kilobytes}" =~ ^([0-9])+$ ]]; then
        # show an error that we can't determine the free space
        printf "  %b %s\\n" "${CROSS}" "${str}"
        printf "  %b Unknown free disk space! \\n" "${INFO}"
        printf "      We were unable to determine available free disk space on this system.\\n"
        # exit with an error code
        exit 1
    # If there is insufficient free disk space,
    elif [[ "${existing_free_kilobytes}" -lt "${required_free_kilobytes}" ]]; then
        # show an error message
        printf "  %b %s\\n" "${CROSS}" "${str}"
        printf "  %b Your system disk appears to only have %s KB free\\n" "${INFO}" "${existing_free_kilobytes}"
        printf "      It is recommended to have a minimum of %s KB to run the PiKonek\\n" "${required_free_kilobytes}"
        # Show there is not enough free space
        printf "\\n      %bInsufficient free space, exiting...%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"
        # and exit with an error
        exit 1
    # Otherwise,
    else
        # Show that we're running a disk space check
        printf "  %b %s\\n" "${TICK}" "${str}"
    fi
}

# A function to setup the wlan interface
setupWlanInterface() {
    WLAN_AP=0
    local countIface=0
    # Turn the available interfaces into an array so it can be used with a whiptail dialog
    local interfacesArray=()
    # Number of available interfaces
    local interfaceCount
    # Whiptail variable storage
    local chooseInterfaceCmd
    # Temporary Whiptail options storage
    local chooseInterfaceOptions
    # Loop sentinel variable
    local firstLoop=1
    local str="Checking for available wireless interface"
    printf "%b  %b %s...\\n" "${OVER}" "${INFO}" "${str}"
    # Find out how many interfaces are available to choose from
    interfaceCount=$(wc -l <<< "${availableWlanInterfaces}")

    # If there is one interface,
    if ip --oneline link show | grep -q wl; then
        if [[ "${interfaceCount}" -ge 1 ]]; then
        # While reading through the available interfaces
            if whiptail --backtitle "Setting up wireless interface" --title "Wireless Access Point Configuration" --yesno "Do you want to enable wireless access point?" "${r}" "${c}"; then
                while read -r line; do
                    # use a variable to set the option as OFF to begin with
                    mode="OFF"
                    # If it's the first loop,
                    if [[ "${firstLoop}" -eq 1 ]]; then
                        # set this as the interface to use (ON)
                        firstLoop=0
                        mode="ON"
                    fi
                    # Put all these interfaces into an array
                    interfacesArray+=("${line}" "available" "${mode}")
                # Feed the available interfaces into this while loop
                done <<< "${availableWlanInterfaces}"
                # The whiptail command that will be run, stored in a variable
                chooseInterfaceCmd=(whiptail --separate-output --radiolist "Choose the WLAN Interface (press space to toggle selection)" "${r}" "${c}" "${interfaceCount}")
                # Now run the command using the interfaces saved into the array
                chooseInterfaceOptions=$("${chooseInterfaceCmd[@]}" "${interfacesArray[@]}" 2>&1 >/dev/tty) || \
                # If the user chooses Cancel, exit
                { printf "  %bCancel was selected, exiting installer%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"; exit 1; }
                # For each interface
                for desiredInterface in ${chooseInterfaceOptions}; do
                    # Set the one the user selected as the interface to use
                    PIKONEK_WLAN_INTERFACE=${desiredInterface}
                    PIKONEK_WLAN_MAC_INTERFACE=$(cat /sys/class/net/$PIKONEK_WLAN_INTERFACE/address)
                    PIKONKE_WLAN_ORIG_INTERFACE=${desiredInterface}
                    PIKONEK_WLAN_DEVICE_ID=$(ethtool -i $PIKONEK_WLAN_INTERFACE | grep bus-info | awk '{print $2}')
                    PIKONEK_WLAN_ALIAS="wifi-net"
                    # and show this information to the user
                    printf "  %b Using WLAN interface: %s\\n" "${INFO}" "${PIKONEK_WLAN_INTERFACE}"
                done
                WLAN_AP=1
                # set up ip
                getStaticIPv4WlanSettings
                # Set up ap
                do_wifi_ap           
            else
                printf "%b  %b %s...\\n" "${OVER}" "${INFO}" "${str}"
            fi
        fi
    else
        str="No available wireless interface"
        printf "%b  %b %s...\\n" "${OVER}" "${INFO}" "${str}"
    fi
}

configureWirelessAP() {
    local str="Configuring wireless access point"
    printf "  %b %s...\\n" "${INFO}" "${str}"
    if /usr/local/bin/pikonek -a -w ${PIKONEK_LOCAL_REPO}/configs/pikonek_wpa_mapping.yaml &> /dev/null; then
        printf "%b  %b %s...\\n" "${OVER}" "${TICK}" "${str}"
    else
        printf "\\t\\t%bError: Unable to configure wireless access point, exiting installer%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"
        return 1
    fi
}

configurePikonekCore() {
    local str="Configuring pikonek core"
    printf "  %b %s...\\n" "${INFO}" "${str}"
    if /usr/local/bin/pikonek -a -c ${PIKONEK_LOCAL_REPO}/configs/pikonek.yaml &> /dev/null; then
        printf "%b  %b %s...\\n" "${OVER}" "${TICK}" "${str}"
    else
        printf "\\t\\t%bError: Unable to configure pikonek core, exiting installer%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"
        return 1
    fi
}

configurePihole() {
    # create docker compose file
    local str="Configuring pihole docker"
    printf "  %b %s...\\n" "${INFO}" "${str}"
    {
    echo -e "services:"
    echo -e "   pihole:"
    echo -e "       container_name: pihole"
    echo -e "       image: pihole/pihole:latest"
    echo -e "       ports:"
    echo -e "           - '53:53/tcp'"
    echo -e "           - '53:53/udp'"
    echo -e "           - '8080:8080/tcp'"
    echo -e "       environment:"
    echo -e "           TZ: '${PIKONEK_TIME_ZONE}'"
    echo -e "           DNSMASQ_LISTENING: 'all'"
    echo -e "           WEB_PORT: 8080"
    echo -e "           WEBPASSWORD: ${1}"
    echo -e "       volumes:"
    echo -e "           - './etc-pihole:/etc/pihole'"
    echo -e "           - './etc-dnsmasq.d:/etc/dnsmasq.d'"
    echo -e "           - '/etc/pikonek/configs/pikonek.host:/etc/pikonek/configs/pikonek.host'"
    echo -e "       cap_add:"
    echo -e "           - NET_ADMIN"
    echo -e "       restart: unless-stopped"
    echo -e "       network_mode: host"
    } > "${PIKONEK_LOCAL_REPO}/pihole/docker-compose.yaml"
    # set 02-pikonek.conf
    # create directory 
    mkdir -p "${PIKONEK_LOCAL_REPO}/pihole/etc-dnsmasq.d"
    {
    echo -e "addn-hosts=/etc/pikonek/configs/pikonek.host"
    echo -e "ipset=/walledgarden"
    } > "${PIKONEK_LOCAL_REPO}/pihole/etc-dnsmasq.d/02-pikonek.conf"
    # disable the dnsstublistener this will disable systemd-resolved
    # backup /etc/systemd/resolved.conf
    cp /etc/systemd/resolved.conf /etc/systemd/resolved.conf.orig
    sed -r -i.orig 's/#?DNSStubListener=yes/DNSStubListener=no/g' /etc/systemd/resolved.conf
    # remove /etc/resolv.conf
    # backup /etc/resolv.conf
    cp /etc/resolv.conf /etc/resolv.conf.orig
    rm /etc/resolv.conf
    # add symbolic
    ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
    printf "%b  %b %s...\\n" "${OVER}" "${TICK}" "${str}"
}

configureCaptivePortalRule() {
    local str="Configuring captive portal rule"
    printf "  %b %s...\\n" "${INFO}" "${str}"
    if /usr/local/bin/pikonek -a -r ${PIKONEK_LOCAL_REPO}/configs/packages/captive_portal.yaml &> /dev/null; then
        printf "%b  %b %s...\\n" "${OVER}" "${TICK}" "${str}"
    else
        printf "\\t\\t%bError: Unable to configure captive portal, exiting installer%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"
        return 1
    fi
}

get_wifi_country() {
    CODE=${1:-0}
    if ! wpa_cli -i "$PIKONEK_WLAN_INTERFACE" status > /dev/null 2>&1; then
        whiptail --msgbox "Could not communicate with wpa_supplicant" 20 60
        return 1
    fi
    wpa_cli -i "$PIKONEK_WLAN_INTERFACE" save_config > /dev/null 2>&1
    COUNTRY="$(wpa_cli -i "$PIKONEK_WLAN_INTERFACE" get country)"
    if [ "$COUNTRY" = "FAIL" ]; then
        return 1
    fi

    if [ $CODE = 0 ]; then
        echo "$COUNTRY"
    fi

    return 0
}

list_wlan_interfaces() {
  for dir in /sys/class/net/*/wireless; do
    if [ -d "$dir" ]; then
      basename "$(dirname "$dir")"
    fi
  done
}

do_wifi_ap() {
    ap_mode=2
    psk=""
    # Install wpa_supplicant.conf       
    install -m 0644 ${PIKONEK_LOCAL_REPO}/configs/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf

    # if [ -z "$(get_wifi_country)" ]; then
    #     do_wifi_country
    # fi

    # do_wifi_country

    SSID="$1"
    while [ -z "$SSID" ]; do
        SSID=$(whiptail --inputbox "Please enter SSID" "${r}" "${c}" 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            return 0
        elif [ -z "$SSID" ]; then
            whiptail --msgbox "SSID cannot be empty. Please try again." "${r}" "${c}"
        fi
    done

    if whiptail --yesno "Do you want to enable passphrase?" "${r}" "${c}"; then
        PASSPHRASE=""
        local pass_length=$(expr length "$PASSPHRASE")
        while [ "$pass_length" -lt 8 ]; do
            PASSPHRASE=$(whiptail --passwordbox "Please enter passphrase. Must be min of 8 characters in length." "${r}" "${c}" 3>&1 1>&2 2>&3)
            pass_length=$(expr length "$PASSPHRASE")
            if [ $? -ne 0 ]; then
                return 0
            elif [ -z "$PASSPHRASE" ]; then
                whiptail --msgbox "PASSPHRASE cannot be empty. Please try again." "${r}" "${c}"
            fi
        done
    fi

    # Escape special characters for embedding in regex below
    local ssid="$(echo "$SSID" \
    | sed 's;\\;\\\\;g' \
    | sed -e 's;\.;\\\.;g' \
            -e 's;\*;\\\*;g' \
            -e 's;\+;\\\+;g' \
            -e 's;\?;\\\?;g' \
            -e 's;\^;\\\^;g' \
            -e 's;\$;\\\$;g' \
            -e 's;\/;\\\/;g' \
            -e 's;\[;\\\[;g' \
            -e 's;\];\\\];g' \
            -e 's;{;\\{;g'   \
            -e 's;};\\};g'   \
            -e 's;(;\\(;g'   \
            -e 's;);\\);g'   \
            -e 's;";\\\\\";g')"

    if [ -z "$PASSPHRASE" ]; then
        key_mgmt="NONE"
    else
        psk="$PASSPHRASE"
        key_mgmt="WPA-PSK"
    fi
}

do_wifi_country() {
    # if ! wpa_cli -i "$PIKONEK_WLAN_INTERFACE" status > /dev/null 2>&1; then
    #     whiptail --msgbox "Could not communicate with wpa_supplicant" 20 60
    #     return 1
    # fi

    oIFS="$IFS"
    IFS="/"
    value=$(cat /usr/share/zoneinfo/iso3166.tab | tail -n +26 | tr '\t' '/' | tr '\n' '/')
    COUNTRY=$(whiptail --menu "Select the country in which the PiKonek is to be used" 20 60 10 ${value} 3>&1 1>&2 2>&3)

    # if [ $? -eq 0 ];then
    #     wpa_cli -i "$PIKONEK_WLAN_INTERFACE" set country "$COUNTRY" > /dev/null 2>&1
    #     wpa_cli -i "$PIKONEK_WLAN_INTERFACE" save_config > /dev/null 2>&1
    # fi

    whiptail --msgbox "Wireless LAN country set to $COUNTRY" 20 60 1
    str="Wireless LAN country set to $COUNTRY"
    printf "%b  %b %s...\\n" "${OVER}" "${INFO}" "${str}"
}

# A function to setup the wan interface
setupWanInterface() {
    local countIface=0
    # Turn the available interfaces into an array so it can be used with a whiptail dialog
    local interfacesArray=()
    # Number of available interfaces
    local interfaceCount
    # Whiptail variable storage
    local chooseInterfaceCmd
    # Temporary Whiptail options storage
    local chooseInterfaceOptions
    # Loop sentinel variable
    local firstLoop=1

    # Find out how many interfaces are available to choose from
    interfaceCount=$(wc -l <<< "${availableInterfaces}")

    # If there is one interface,
    if [[ "${interfaceCount}" -eq 1 ]]; then
        countIface=1
        # Set it as the interface to use since there is no other option
        # PIKONEK_WAN_INTERFACE="${availableInterfaces}"
        # printf "  %b Using WAN interface: %s\\n" "${INFO}" "${PIKONEK_WAN_INTERFACE}"
    fi
    # Otherwise,
    # While reading through the available interfaces
    while read -r line; do
        # use a variable to set the option as OFF to begin with
        mode="OFF"
        # If it's the first loop,
        if [[ "${firstLoop}" -eq 1 ]]; then
            # set this as the interface to use (ON)
            firstLoop=0
            mode="ON"
        fi
        # Put all these interfaces into an array
        interfacesArray+=("${line}" "available" "${mode}")
    # Feed the available interfaces into this while loop
    done <<< "${availableInterfaces}"
    # The whiptail command that will be run, stored in a variable
    chooseInterfaceCmd=(whiptail --separate-output --radiolist "Choose the WAN Interface (press space to toggle selection)" "${r}" "${c}" "${interfaceCount}")
    # Now run the command using the interfaces saved into the array
    chooseInterfaceOptions=$("${chooseInterfaceCmd[@]}" "${interfacesArray[@]}" 2>&1 >/dev/tty) || \
    # If the user chooses Cancel, exit
    { printf "  %bCancel was selected, exiting installer%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"; exit 1; }
    # For each interface
    for desiredInterface in ${chooseInterfaceOptions}; do
        # Set the one the user selected as the interface to use
        PIKONEK_WAN_INTERFACE=${desiredInterface}
        PIKONKE_WAN_ORIG_INTERFACE=${desiredInterface}
        PIKONEK_WAN_MAC_INTERFACE=$(cat /sys/class/net/$PIKONEK_WAN_INTERFACE/address)
        PIKONEK_WAN_DEVICE_ID=$(ethtool -i $PIKONEK_WAN_INTERFACE | grep bus-info | awk '{print $2}')
        PIKONEK_WAN_ALIAS="internet"
        # and show this information to the user
        printf "  %b Using WAN interface: %s\\n" "${INFO}" "${PIKONEK_WAN_INTERFACE}"
    done

    find_IPv4_information
    getStaticIPv4WanSettings
}

count=0
# A function to setup the lan interface
setupLanInterface() {
    local countIface=0
    # Turn the available interfaces into an array so it can be used with a whiptail dialog
    local interfacesArray=()
    # Number of available interfaces
    local interfaceCount
    # Whiptail variable storage
    local chooseInterfaceCmd
    # Temporary Whiptail options storage
    local chooseInterfaceOptions
    # Loop sentinel variable
    local firstLoop=1

    # Find out how many interfaces are available to choose from
    interfaceCount=$(wc -l <<< "${availableLanInterfaces}")

    # If there is one interface,
    if [[ "${interfaceCount}" -eq 1 ]]; then
        # Set it as the interface to use since there is no other option
        countIface=1
        # interfaceCount=2
        # printf "  %b Using LAN interface: %s\\n" "${INFO}" "${PIKONEK_LAN_INTERFACE}"
    fi
    # Otherwise,
    # While reading through the available interfaces
    # mode="OFF"
    while read -r line; do
        # use a variable to set the option as OFF to begin with
        mode="OFF"
        # If it's the first loop,
        if [[ "${firstLoop}" -eq 1 ]]; then
            # set this as the interface to use (ON)
            firstLoop=0
            mode="ON"
        fi
        # Put all these interfaces into an array
        if [[ "$line" != "$PIKONEK_WAN_INTERFACE" ]]; then
            interfacesArray+=("${line}" "available" "${mode}")
        fi
    # Feed the available interfaces into this while loop
    done <<< "${availableLanInterfaces}"
    # while read -r line; do
    #     # use a variable to set the option as OFF to begin with
    #     # Put all these interfaces into an array

    #     if [ "$countIface" -eq 1 ]; then
    #         # Put all these interfaces into an array
    #         interfacesArray+=("lan1" "available" "ON")
    #     else
    #         if [ "$line" != "$PIKONEK_WAN_INTERFACE" ]; then
    #             if [ $mode == "OFF" ]; then
    #                 mode="ON"
    #                 count=$((count+1))
    #             fi
    #             # If it equals 1,
    #             # if [[ "${count}" == 1 ]]; then
    #             #     #
    #             #     mode="OFF"
    #             # fi

    #             interfacesArray+=("${line}" "available" "${mode}")
    #         fi
    #     fi

    # # Feed the available interfaces into this while loop
    # done <<< "${availableLanInterfaces}"
    # The whiptail command that will be run, stored in a variable
    chooseInterfaceCmd=(whiptail --separate-output --radiolist "Choose the LAN Interface (press space to toggle selection)" "${r}" "${c}" "${interfaceCount}")
    # Now run the command using the interfaces saved into the array
    chooseInterfaceOptions=$("${chooseInterfaceCmd[@]}" "${interfacesArray[@]}" 2>&1 >/dev/tty) || \
    # If the user chooses Cancel, exit
    { printf "  %bCancel was selected, exiting installer%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"; exit 1; }
    # For each interface
    for desiredInterface in ${chooseInterfaceOptions}; do
        # Set the one the user selected as the interface to use
        PIKONEK_LAN_INTERFACE=${desiredInterface}
        PIKONEK_LAN_MAC_INTERFACE=$(cat /sys/class/net/$PIKONEK_LAN_INTERFACE/address)
        PIKONKE_LAN_ORIG_INTERFACE=${desiredInterface}
        PIKONEK_LAN_DEVICE_ID=$(ethtool -i $PIKONEK_LAN_INTERFACE | grep bus-info | awk '{print $2}')
        PIKONEK_LAN_ALIAS="lan-connection"
        # and show this information to the user
        printf "  %b Using LAN interface: %s\\n" "${INFO}" "${PIKONEK_LAN_INTERFACE}"
    done

    getStaticIPv4LanSettings
}

getStaticIPv4WanSettings() {
    # Local, named variables
    local ipSettingsCorrect
    # Ask if the user wants to use DHCP settings as their static IP
    # This is useful for users that are using DHCP reservations; then we can just use the information gathered via our functions
    if whiptail --backtitle "Calibrating network interface" --title "WAN IP Address Assignment" --yesno "Do you want to use DHCP to assign ip address for WAN Interface?" "${r}" "${c}"; then
        PIKONEK_WAN_DHCP_INTERFACE=true
    else
    # Otherwise, we need to ask the user to input thesir deired settings.
    # Start by getting the IPv4 address (pre-filling it with info gathered from DHCP)
    # Start a loop to let the user enter their information with the chance to go back and edit it if necessary
        until [[ "${ipSettingsCorrect}" = True ]]; do
            # Ask for the IPv4 address
            WAN_IPV4_ADDRESS=$(whiptail --backtitle "Calibrating network interface" --title "IPv4 address" --inputbox "Enter your desired IPv4 address" "${r}" "${c}" "${IPV4_ADDRESS}" 3>&1 1>&2 2>&3) || \
            # Canceling IPv4 settings window
            { ipSettingsCorrect=False; echo -e "  ${COL_LIGHT_RED}Cancel was selected, exiting installer${COL_NC}"; exit 1; }
            printf "  %b Your static IPv4 address: %s\\n" "${INFO}" "${IPV4_ADDRESS}"

            # Ask for the gateway
            WAN_IPv4gw=$(whiptail --backtitle "Calibrating network interface" --title "IPv4 gateway (router)" --inputbox "Enter your desired IPv4 default gateway" "${r}" "${c}" "${IPv4gw}" 3>&1 1>&2 2>&3) || \
            # Canceling gateway settings window
            { ipSettingsCorrect=False; echo -e "  ${COL_LIGHT_RED}Cancel was selected, exiting installer${COL_NC}"; exit 1; }
            printf "  %b Your static IPv4 gateway: %s\\n" "${INFO}" "${IPv4gw}"
            PIKONEK_WAN_DHCP_INTERFACE=false
            # Give the user a chance to review their settings before moving on
            if whiptail --backtitle "Calibrating network interface" --title "Static IP Address" --yesno "Are these settings correct?
                IP address: ${WAN_IPV4_ADDRESS}
                Gateway:    ${WAN_IPv4gw}" "${r}" "${c}"; then
                    # After that's done, the loop ends and we move on
                    ipSettingsCorrect=True
            else
                # If the settings are wrong, the loop continues
                ipSettingsCorrect=False
            fi
        done
    fi
}

getStaticIPv4WlanSettings() {
    # Local, named variables
    local ipSettingsCorrect
    local ipRangeSettingsCorrect
    PIKONEK_WLAN_DHCP_INTERFACE=false
    WLAN_IPV4_ADDRESS="192.168.0.1/24"
    # Ask if the user wants to use DHCP settings as their static IP
    # This is useful for users that are using DHCP reservations; then we can just use the information gathered via our functions
    whiptail --title "WLAN Static IP Address" --msgbox "Configure IPv4 Static Address for WLAN Interface." "${r}" "${c}"
    # Otherwise, we need to ask the user to input their desired settings.
    # Start by getting the IPv4 address (pre-filling it with info gathered from DHCP)
    # Start a loop to let the user enter their information with the chance to go back and edit it if necessary
    until [[ "${ipSettingsCorrect}" = True ]]; do
        # Ask for the IPv4 address
        WLAN_IPV4_ADDRESS=$(whiptail --backtitle "Calibrating network interface" --title "IPv4 address" --inputbox "Enter your desired IPv4 address ie. 192.168.0.1/24" "${r}" "${c}" "${WLAN_IPV4_ADDRESS}" 3>&1 1>&2 2>&3) || \
        # Canceling IPv4 settings window
        { ipSettingsCorrect=False; echo -e "  ${COL_LIGHT_RED}Cancel was selected, exiting installer${COL_NC}"; exit 1; }
        printf "  %b Your WLAN static IPv4 address: %s\\n" "${INFO}" "${WLAN_IPV4_ADDRESS}"
        PIKONEK_WLAN_DHCP_INTERFACE=false
        # Give the user a chance to review their settings before moving on
        if whiptail --backtitle "Calibrating network interface" --title "Static IP Address" --yesno "Are these settings correct?
            IP address: ${WLAN_IPV4_ADDRESS}" "${r}" "${c}"; then
                # After that's done, the loop ends and we move on
                ipSettingsCorrect=True
        else
            # If the settings are wrong, the loop continues
            ipSettingsCorrect=False
        fi
    done
    # Set dhcp range
    until [[ "${ipRangeSettingsCorrect}" = True ]]; do
        #
        strInvalid="Invalid"
        # If the first
        if [[ ! "${wpikonek_RANGE_1}" ]]; then
            # and second upstream servers do not exist
            if [[ ! "${wpikonek_RANGE_2}" ]]; then
                prePopulate=""
            # Otherwise,
            else
                prePopulate=", ${wpikonek_RANGE_2}"
            fi
        elif  [[ "${wpikonek_RANGE_1}" ]] && [[ ! "${wpikonek_RANGE_2}" ]]; then
            prePopulate="${wpikonek_RANGE_1}"
        elif [[ "${wpikonek_RANGE_1}" ]] && [[ "${wpikonek_RANGE_2}" ]]; then
            prePopulate="${wpikonek_RANGE_1}, ${wpikonek_RANGE_2}"
        fi

        # Dialog for the user to enter custom upstream servers
        wpikonekRange=$(whiptail --backtitle "Specify the dhcp range"  --inputbox "Enter your desired dhcp range, separated by a comma.\\n\\nFor example '192.168.0.100, 192.168.0.200'" "${r}" "${c}" "${prePopulate}" 3>&1 1>&2 2>&3) || \
        { printf "  %bCancel was selected, exiting installer%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"; exit 1; }
        # Clean user input and replace whitespace with comma.
        wpikonekRange=$(sed 's/[, \t]\+/,/g' <<< "${wpikonekRange}")

        printf -v wpikonek_RANGE_1 "%s" "${wpikonekRange%%,*}"
        printf -v wpikonek_RANGE_2 "%s" "${wpikonekRange##*,}"

        # If the IP is valid,
        if ! valid_ip "${wpikonek_RANGE_1}" || [[ ! "${wpikonek_RANGE_1}" ]]; then
            # store it in the variable so we can use it
            wpikonek_RANGE_1=${strInvalid}
        fi
        # Do the same for the secondary server
        if ! valid_ip "${wpikonek_RANGE_2}" && [[ "${wpikonek_RANGE_2}" ]]; then
            wpikonek_RANGE_2=${strInvalid}
        fi
        # If either of the IP Address are invalid,
        if [[ "${wpikonek_RANGE_1}" == "${strInvalid}" ]] || [[ "${wpikonek_RANGE_2}" == "${strInvalid}" ]]; then
            # explain this to the user
            whiptail --msgbox --backtitle "Invalid IP" --title "Invalid IP" "One or both entered IP addresses were invalid. Please try again.\\n\\n    IP Address 1:   $wpikonek_RANGE_2\\n    IP Address 2:   ${wpikonek_RANGE_2}" ${r} ${c}
            # and set the variables back to nothing
            if [[ "${wpikonek_RANGE_1}" == "${strInvalid}" ]]; then
                wpikonek_RANGE_1=""
            fi
            if [[ "${wpikonek_RANGE_2}" == "${strInvalid}" ]]; then
                wpikonek_RANGE_2=""
            fi
            # Since the settings will not work, stay in the loop
            ipRangeSettingsCorrect=False
        # Otherwise,
        else
            # Show the settings
            if (whiptail --backtitle "Specify DHCP Range(s)" --title "DHCP Range(s)" --yesno "Are these settings correct?\\n    IP Address 1:   $wpikonek_RANGE_1\\n    IP Address 2:   ${wpikonek_RANGE_2}" "${r}" "${c}"); then
                # and break from the loop since the servers are valid
                ipRangeSettingsCorrect=True
            # Otherwise,
            else
                # If the settings are wrong, the loop continues
                ipRangeSettingsCorrect=False
            fi
        fi
    done
}

getStaticIPv4LanSettings() {
    # Local, named variables
    local ipSettingsCorrect
    local ipRangeSettingsCorrect
    PIKONEK_LAN_DHCP_INTERFACE=false
    LAN_IPV4_ADDRESS="10.0.0.1/24"
    # Ask if the user wants to use DHCP settings as their static IP
    # This is useful for users that are using DHCP reservations; then we can just use the information gathered via our functions
    whiptail --title "LAN Static IP Address" --msgbox "Configure IPv4 Static Address for LAN Interface." "${r}" "${c}"
    # Otherwise, we need to ask the user to input their desired settings.
    # Start by getting the IPv4 address (pre-filling it with info gathered from DHCP)
    # Start a loop to let the user enter their information with the chance to go back and edit it if necessary
    until [[ "${ipSettingsCorrect}" = True ]]; do
        # Ask for the IPv4 address
        LAN_IPV4_ADDRESS=$(whiptail --backtitle "Calibrating network interface" --title "IPv4 address" --inputbox "Enter your desired IPv4 address ie. 10.0.0.1/24" "${r}" "${c}" "${LAN_IPV4_ADDRESS}" 3>&1 1>&2 2>&3) || \
        # Canceling IPv4 settings window
        { ipSettingsCorrect=False; echo -e "  ${COL_LIGHT_RED}Cancel was selected, exiting installer${COL_NC}"; exit 1; }
        printf "  %b Your LAN static IPv4 address: %s\\n" "${INFO}" "${LAN_IPV4_ADDRESS}"
        PIKONEK_LAN_DHCP_INTERFACE=false
        # Give the user a chance to review their settings before moving on
        if whiptail --backtitle "Calibrating network interface" --title "Static IP Address" --yesno "Are these settings correct?
            IP address: ${LAN_IPV4_ADDRESS}" "${r}" "${c}"; then
                # After that's done, the loop ends and we move on
                ipSettingsCorrect=True
        else
            # If the settings are wrong, the loop continues
            ipSettingsCorrect=False
        fi
    done
    # Set dhcp range
    until [[ "${ipRangeSettingsCorrect}" = True ]]; do
        #
        strInvalid="Invalid"
        # If the first
        if [[ ! "${pikonek_RANGE_1}" ]]; then
            # and second upstream servers do not exist
            if [[ ! "${pikonek_RANGE_2}" ]]; then
                prePopulate=""
            # Otherwise,
            else
                prePopulate=", ${pikonek_RANGE_2}"
            fi
        elif  [[ "${pikonek_RANGE_1}" ]] && [[ ! "${pikonek_RANGE_2}" ]]; then
            prePopulate="${pikonek_RANGE_1}"
        elif [[ "${pikonek_RANGE_1}" ]] && [[ "${pikonek_RANGE_2}" ]]; then
            prePopulate="${pikonek_RANGE_1}, ${pikonek_RANGE_2}"
        fi

        # Dialog for the user to enter custom upstream servers
        pikonekRange=$(whiptail --backtitle "Specify the dhcp range"  --inputbox "Enter your desired dhcp range, separated by a comma.\\n\\nFor example '10.0.0.100, 10.0.0.200'" "${r}" "${c}" "${prePopulate}" 3>&1 1>&2 2>&3) || \
        { printf "  %bCancel was selected, exiting installer%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"; exit 1; }
        # Clean user input and replace whitespace with comma.
        pikonekRange=$(sed 's/[, \t]\+/,/g' <<< "${pikonekRange}")

        printf -v pikonek_RANGE_1 "%s" "${pikonekRange%%,*}"
        printf -v pikonek_RANGE_2 "%s" "${pikonekRange##*,}"

        # If the IP is valid,
        if ! valid_ip "${pikonek_RANGE_1}" || [[ ! "${pikonek_RANGE_1}" ]]; then
            # store it in the variable so we can use it
            pikonek_RANGE_1=${strInvalid}
        fi
        # Do the same for the secondary server
        if ! valid_ip "${pikonek_RANGE_2}" && [[ "${pikonek_RANGE_2}" ]]; then
            pikonek_RANGE_2=${strInvalid}
        fi
        # If either of the IP Address are invalid,
        if [[ "${pikonek_RANGE_1}" == "${strInvalid}" ]] || [[ "${pikonek_RANGE_2}" == "${strInvalid}" ]]; then
            # explain this to the user
            whiptail --msgbox --backtitle "Invalid IP" --title "Invalid IP" "One or both entered IP addresses were invalid. Please try again.\\n\\n    IP Address 1:   $pikonek_RANGE_2\\n    IP Address 2:   ${pikonek_RANGE_2}" ${r} ${c}
            # and set the variables back to nothing
            if [[ "${pikonek_RANGE_1}" == "${strInvalid}" ]]; then
                pikonek_RANGE_1=""
            fi
            if [[ "${pikonek_RANGE_2}" == "${strInvalid}" ]]; then
                pikonek_RANGE_2=""
            fi
            # Since the settings will not work, stay in the loop
            ipRangeSettingsCorrect=False
        # Otherwise,
        else
            # Show the settings
            if (whiptail --backtitle "Specify DHCP Range(s)" --title "DHCP Range(s)" --yesno "Are these settings correct?\\n    IP Address 1:   $pikonek_RANGE_1\\n    IP Address 2:   ${pikonek_RANGE_2}" "${r}" "${c}"); then
                # and break from the loop since the servers are valid
                ipRangeSettingsCorrect=True
            # Otherwise,
            else
                # If the settings are wrong, the loop continues
                ipRangeSettingsCorrect=False
            fi
        fi
    done
}

getStaticIPv4Settings() {
    # Local, named variables
    local ipSettingsCorrect
    # Ask if the user wants to use DHCP settings as their static IP
    # This is useful for users that are using DHCP reservations; then we can just use the information gathered via our functions
    if whiptail --backtitle "Calibrating network interface" --title "Static IP Address" --yesno "Do you want to use your current network settings as a static address?
          IP address:    ${IPV4_ADDRESS}
          Gateway:       ${IPv4gw}" "${r}" "${c}"; then
        # If they choose yes, let the user know that the IP address will not be available via DHCP and may cause a conflict.
        whiptail --msgbox --backtitle "IP information" --title "FYI: IP Conflict" "It is possible your router could still try to assign this IP to a device, which would cause a conflict.  But in most cases the router is smart enough to not do that.
If you are worried, either manually set the address, or modify the DHCP reservation pool so it does not include the IP you want.
It is also possible to use a DHCP reservation, but if you are going to do that, you might as well set a static address." "${r}" "${c}"
    # Nothing else to do since the variables are already set above
    else
    # Otherwise, we need to ask the user to input their desired settings.
    # Start by getting the IPv4 address (pre-filling it with info gathered from DHCP)
    # Start a loop to let the user enter their information with the chance to go back and edit it if necessary
    until [[ "${ipSettingsCorrect}" = True ]]; do

        # Ask for the IPv4 address
        IPV4_ADDRESS=$(whiptail --backtitle "Calibrating network interface" --title "IPv4 address" --inputbox "Enter your desired IPv4 address" "${r}" "${c}" "${IPV4_ADDRESS}" 3>&1 1>&2 2>&3) || \
        # Canceling IPv4 settings window
        { ipSettingsCorrect=False; echo -e "  ${COL_LIGHT_RED}Cancel was selected, exiting installer${COL_NC}"; exit 1; }
        printf "  %b Your static IPv4 address: %s\\n" "${INFO}" "${IPV4_ADDRESS}"

        # Ask for the gateway
        IPv4gw=$(whiptail --backtitle "Calibrating network interface" --title "IPv4 gateway (router)" --inputbox "Enter your desired IPv4 default gateway" "${r}" "${c}" "${IPv4gw}" 3>&1 1>&2 2>&3) || \
        # Canceling gateway settings window
        { ipSettingsCorrect=False; echo -e "  ${COL_LIGHT_RED}Cancel was selected, exiting installer${COL_NC}"; exit 1; }
        printf "  %b Your static IPv4 gateway: %s\\n" "${INFO}" "${IPv4gw}"

        # Give the user a chance to review their settings before moving on
        if whiptail --backtitle "Calibrating network interface" --title "Static IP Address" --yesno "Are these settings correct?
            IP address: ${IPV4_ADDRESS}
            Gateway:    ${IPv4gw}" "${r}" "${c}"; then
                # After that's done, the loop ends and we move on
                ipSettingsCorrect=True
        else
            # If the settings are wrong, the loop continues
            ipSettingsCorrect=False
        fi
    done
    # End the if statement for DHCP vs. static
    fi
}

# Check an IP address to see if it is a valid one
valid_ip() {
    # Local, named variables
    local ip=${1}
    local stat=1

    # One IPv4 element is 8bit: 0 - 256
    local ipv4elem="(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)";
    # optional port number starting '#' with range of 1-65536
    local portelem="(#([1-9]|[1-8][0-9]|9[0-9]|[1-8][0-9]{2}|9[0-8][0-9]|99[0-9]|[1-8][0-9]{3}|9[0-8][0-9]{2}|99[0-8][0-9]|999[0-9]|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-6]))?"
    # build a full regex string from the above parts
    local regex="^${ipv4elem}\.${ipv4elem}\.${ipv4elem}\.${ipv4elem}${portelem}$"

    [[ $ip =~ ${regex} ]]

    stat=$?
    # Return the exit code
    return "${stat}"
}

# A function to set the timezone use timedatectl
setTimezone() {
    local str="Setting timezone"
    printf "  %b %s...\\n" "${INFO}" "${str}"
    local TIMEZONES="$(timedatectl list-timezones)"
    TimeChooseOptions=()
    local TimeZoneCount=0
    # Save the old Internal Field Separator in a variable
    OIFS=$IFS
    # and set the new one to newline
    IFS=$'\n'
    # Loop the timezone
    for Timezone in ${TIMEZONES}
    do
        TimeChooseOptions[TimeZoneCount]="${Timezone}"
        (( TimeZoneCount=TimeZoneCount+1 ))
        TimeChooseOptions[TimeZoneCount]=""
        (( TimeZoneCount=TimeZoneCount+1 ))
    done
    # In a whiptail dialog, show the options
    TimezoneChoices=$(whiptail --separate-output --menu "Select your timezone." "${r}" "${c}" 7 \
    "${TimeChooseOptions[@]}" 2>&1 >/dev/tty) || \
    # exit if Cancel is selected
    { printf "  %bCancel was selected, using default timezone: %s %b\\n" "${INFO}" "${PIKONEK_TIME_ZONE}" "${COL_NC}"; }
    # Save the old Internal Field Separator in a variable
    OIFS=$IFS
    # and set the new one to newline
    IFS=$'\n'
    for Timezone in ${TIMEZONES}
    do
        if [[ "${TimezoneChoices}" == "${Timezone}" ]]
        then
            PIKONEK_TIME_ZONE=${Timezone}
            printf "  %b Using timezone: %s\\n" "${INFO}" "${PIKONEK_TIME_ZONE}"
            break
        fi
    done
    # Restore the IFS to what it was
    IFS=${OIFS}
    #set timezone using timedatectl
    timedatectl set-timezone "${PIKONEK_TIME_ZONE}"
    printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"

}

# A function to choose the upstream DNS provider(s)
setDNS() {
    # Local, named variables
    local DNSSettingsCorrect

    # In an array, list the available upstream providers
    DNSChooseOptions=()
    local DNSServerCount=0
    # Save the old Internal Field Separator in a variable
    OIFS=$IFS
    # and set the new one to newline
    IFS=$'\n'
    # Put the DNS Servers into an array
    for DNSServer in ${DNS_SERVERS}
    do
        DNSName="$(cut -d';' -f1 <<< "${DNSServer}")"
        DNSChooseOptions[DNSServerCount]="${DNSName}"
        (( DNSServerCount=DNSServerCount+1 ))
        DNSChooseOptions[DNSServerCount]=""
        (( DNSServerCount=DNSServerCount+1 ))
    done
    DNSChooseOptions[DNSServerCount]="Custom"
    (( DNSServerCount=DNSServerCount+1 ))
    DNSChooseOptions[DNSServerCount]=""
    # Restore the IFS to what it was
    IFS=${OIFS}
    # In a whiptail dialog, show the options
    DNSchoices=$(whiptail --separate-output --menu "Select Upstream DNS Provider. To use your own, select Custom." "${r}" "${c}" 7 \
    "${DNSChooseOptions[@]}" 2>&1 >/dev/tty) || \
    # exit if Cancel is selected
    { printf "  %bCancel was selected, exiting installer%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"; exit 1; }

    # Depending on the user's choice, set the GLOBAl variables to the IP of the respective provider
    if [[ "${DNSchoices}" == "Custom" ]]
    then
        # Until the DNS settings are selected,
        until [[ "${DNSSettingsCorrect}" = True ]]; do
            #
            strInvalid="Invalid"
            # If the first
            if [[ ! "${pikonek_DNS_1}" ]]; then
                # and second upstream servers do not exist
                if [[ ! "${pikonek_DNS_2}" ]]; then
                    prePopulate=""
                # Otherwise,
                else
                    prePopulate=", ${pikonek_DNS_2}"
                fi
            elif  [[ "${pikonek_DNS_1}" ]] && [[ ! "${pikonek_DNS_2}" ]]; then
                prePopulate="${pikonek_DNS_1}"
            elif [[ "${pikonek_DNS_1}" ]] && [[ "${pikonek_DNS_2}" ]]; then
                prePopulate="${pikonek_DNS_1}, ${pikonek_DNS_2}"
            fi

            # Dialog for the user to enter custom upstream servers
            pikonekDNS=$(whiptail --backtitle "Specify Upstream DNS Provider(s)"  --inputbox "Enter your desired upstream DNS provider(s), separated by a comma.\\n\\nFor example '8.8.8.8, 8.8.4.4'" "${r}" "${c}" "${prePopulate}" 3>&1 1>&2 2>&3) || \
            { printf "  %bCancel was selected, exiting installer%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"; exit 1; }
            # Clean user input and replace whitespace with comma.
            pikonekDNS=$(sed 's/[, \t]\+/,/g' <<< "${pikonekDNS}")

            printf -v pikonek_DNS_1 "%s" "${pikonekDNS%%,*}"
            printf -v pikonek_DNS_2 "%s" "${pikonekDNS##*,}"

            # If the IP is valid,
            if ! valid_ip "${pikonek_DNS_1}" || [[ ! "${pikonek_DNS_1}" ]]; then
                # store it in the variable so we can use it
                pikonek_DNS_1=${strInvalid}
            fi
            # Do the same for the secondary server
            if ! valid_ip "${pikonek_DNS_2}" && [[ "${pikonek_DNS_2}" ]]; then
                pikonek_DNS_2=${strInvalid}
            fi
            # If either of the DNS servers are invalid,
            if [[ "${pikonek_DNS_1}" == "${strInvalid}" ]] || [[ "${pikonek_DNS_2}" == "${strInvalid}" ]]; then
                # explain this to the user
                whiptail --msgbox --backtitle "Invalid IP" --title "Invalid IP" "One or both entered IP addresses were invalid. Please try again.\\n\\n    DNS Server 1:   $pikonek_DNS_1\\n    DNS Server 2:   ${pikonek_DNS_2}" ${r} ${c}
                # and set the variables back to nothing
                if [[ "${pikonek_DNS_1}" == "${strInvalid}" ]]; then
                    pikonek_DNS_1=""
                fi
                if [[ "${pikonek_DNS_2}" == "${strInvalid}" ]]; then
                    pikonek_DNS_2=""
                fi
                # Since the settings will not work, stay in the loop
                DNSSettingsCorrect=False
            # Otherwise,
            else
                # Show the settings
                if (whiptail --backtitle "Specify Upstream DNS Provider(s)" --title "Upstream DNS Provider(s)" --yesno "Are these settings correct?\\n    DNS Server 1:   $pikonek_DNS_1\\n    DNS Server 2:   ${pikonek_DNS_2}" "${r}" "${c}"); then
                    # and break from the loop since the servers are valid
                    DNSSettingsCorrect=True
                # Otherwise,
                else
                    # If the settings are wrong, the loop continues
                    DNSSettingsCorrect=False
                fi
            fi
        done
    else
        # Save the old Internal Field Separator in a variable
        OIFS=$IFS
        # and set the new one to newline
        IFS=$'\n'
        for DNSServer in ${DNS_SERVERS}
        do
            DNSName="$(cut -d';' -f1 <<< "${DNSServer}")"
            if [[ "${DNSchoices}" == "${DNSName}" ]]
            then
                pikonek_DNS_1="$(cut -d';' -f2 <<< "${DNSServer}")"
                pikonek_DNS_2="$(cut -d';' -f3 <<< "${DNSServer}")"
                break
            fi
        done
        # Restore the IFS to what it was
        IFS=${OIFS}
    fi

    # Display final selection
    local DNSIP=${pikonek_DNS_1}
    [[ -z ${pikonek_DNS_2} ]] || DNSIP+=", ${pikonek_DNS_2}"
    printf "  %b Using upstream DNS: %s (%s)\\n" "${INFO}" "${DNSchoices}" "${DNSIP}"
}

# Check if /etc/dnsmasq.conf is from PiKonek.  If so replace with an original and install new in .d directory
version_check_dnsmasq() {
    # Local, named variables
    local dnsmasq_conf="/etc/dnsmasq.conf"
    local dnsmasq_original_config="${PIKONEK_LOCAL_REPO}/configs/dnsmasq.conf.original"
    local dnsmasq_pikonek_01_snippet="${PIKONEK_LOCAL_REPO}/configs/01-pikonek.conf"
    local dnsmasq_pikonek_01_location="/etc/dnsmasq.d/01-pikonek.conf"

    # If the dnsmasq config file exists
    if [[ -f "${dnsmasq_conf}" ]]; then
        printf "  %b Existing dnsmasq.conf found..." "${INFO}"
        # Don't to anything
        printf " it is not a PiKonek file, leaving alone!\\n"
    else
        # If a file cannot be found,
        printf "  %b No dnsmasq.conf found... restoring default dnsmasq.conf..." "${INFO}"
        # restore the default one
        install -D -m 644 -T "${dnsmasq_original_config}" "${dnsmasq_conf}"
        printf "%b  %b No dnsmasq.conf found... restoring default dnsmasq.conf...\\n" "${OVER}"  "${TICK}"
    fi

    printf "  %b Copying 01-pikonek.conf to /etc/dnsmasq.d/01-pikonek.conf..." "${INFO}"
    # Check to see if dnsmasq directory exists (it may not due to being a fresh install and dnsmasq no longer being a dependency)
    if [[ ! -d "/etc/dnsmasq.d"  ]];then
        install -d -m 755 "/etc/dnsmasq.d"
    fi
    # Empty dnsmasq directory
    rm -rf /etc/dnsmasq.d/**
    # Copy the new PiKonek DNS config file into the dnsmasq.d directory
    install -D -m 644 -T "${dnsmasq_pikonek_01_snippet}" "${dnsmasq_pikonek_01_location}"
    printf "%b  %b Copying 01-pikonek.conf to /etc/dnsmasq.d/01-pikonek.conf\\n" "${OVER}"  "${TICK}"
    #
    echo "conf-dir=/etc/dnsmasq.d" > "${dnsmasq_conf}"
    chmod 644 "${dnsmasq_conf}"
}

# Clean an existing installation to prepare for upgrade/reinstall
clean_existing() {
    # Local, named variables
    # ${1} Directory to clean
    local clean_directory="${1}"
    # Make ${2} the new one?
    shift
    # ${2} Array of files to remove
    local old_files=( "$@" )

    # For each script found in the old files array
    for script in "${old_files[@]}"; do
        # Remove them
        rm -f "${clean_directory}/${script}.sh"
    done
}


configureMosquitto() {
    local str="Configuring mqtt server..."
    printf "  %b %s...\\n" "${INFO}" "${str}"

    if [[ ! -f /etc/mosquitto/passwd ]]; then
    
        touch /etc/mosquitto/passwd
        mqtt_username=$(tr -dc _A-Z-a-z-0-9 < /dev/urandom | head -c 11)
        mqtt_password=$(tr -dc _A-Z-a-z-0-9 < /dev/urandom | head -c 11)
        mosquitto_passwd -b /etc/mosquitto/passwd ${mqtt_username} ${mqtt_password} > /dev/null 2>&1
        
        {
        echo -e "services:"
        echo -e "- name: mqtt"
        echo -e "  username: ${mqtt_username}"
        echo -e "  password: ${mqtt_password}" 
        echo -e "  port: 1883"
        echo -e "  tls: false"
        echo -e "  keep_alive: 5"
        } >> "${PIKONEK_LOCAL_REPO}/configs/pikonek.yaml"
    fi

    install -m 0644 ${PIKONEK_LOCAL_REPO}/configs/01-mosquitto.conf /etc/mosquitto/conf.d/01-mosquitto.conf
    printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
}   


# Install base files and web interface
installpikonek() {
    if [[ ! -d "${webroot}" ]]; then
        # make the Web directory if necessary
        install -d -m 0755 ${webroot}
    fi

    # cp -r ${PIKONEK_LOCAL_REPO}/pikonek-ui-react/build/** /var/www/html

    chown ${LIGHTTPD_USER}:${LIGHTTPD_GROUP} ${webroot}
    chmod 0775 ${webroot}
    # Repair permissions if /var/www/html is not world readable
    chmod a+rx /var/www
    chmod a+rx /var/www/html
    # Give lighttpd access to the pikonek group so the web interface can acces the db
    usermod -a -G pikonek ${LIGHTTPD_USER} &> /dev/null

    # install pikonek core web service
    if [[ ! -d "${PIKONEK_LOCAL_REPO}" ]]; then
        install -o "${USER}" -Dm755 -d "${PIKONEK_LOCAL_REPO}"
    fi
    # install pikonek core init script to /etc/init.d
    # if [[ ! -f /etc/init.d/S70piknkmain ]]; then
    #     install -m 0755 ${PIKONEK_LOCAL_REPO}/etc/init.d/S70piknkmain /etc/init.d/S70piknkmain
    # fi
    install -m 0755 ${PIKONEK_LOCAL_REPO}/etc/init.d/S70piknkmain /etc/init.d/S70piknkmain 
    # Check if there is /etc/sysctl.conf
    if [ -e /etc/sysctl.conf ];
    then
        # Check if there is a match
        # Backup sysctl.conf
        cp /etc/sysctl.conf /etc/sysctl.conf.old
        install -m 0644 ${PIKONEK_LOCAL_REPO}/configs/sysctl.conf /etc/sysctl.conf
        # if grep -qE '#net.ipv4.ip_forward=1' /etc/sysctl.conf; then
        #     sed -i '/#net.ipv4.ip_forward=1/a\net.ipv4.ip_forward=1' /etc/sysctl.conf
        # fi
    else
        install -m 0644 ${PIKONEK_LOCAL_REPO}/configs/sysctl.conf /etc/sysctl.conf
    fi

    # install kernel modules
    install -m 0644 ${PIKONEK_LOCAL_REPO}/configs/modules /etc/modules

    # Install base files and web interface
    if ! installScripts; then
        printf "  %b Failure in dependent script copy function.\\n" "${CROSS}"
        exit 1
    fi
    # Install config files
    if ! installConfigs; then
        printf "  %b Failure in dependent config copy function.\\n" "${CROSS}"
        exit 1
    fi

    # rename license.lic.trial to license.lic
    if [[ ! -f /etc/pikonek/license/license.lic ]]; then
        cp ${PIKONEK_LOCAL_REPO}/license/license.lic.trial ${PIKONEK_LOCAL_REPO}/license/license.lic
    fi

    export PYARMOR_LICENSE="${PIKONEK_LOCAL_REPO}/license/license.lic"
    
    # install web server
    installpikonekWebServer
    # install logrotate
    installLogrotate
    # change the user to pikonek
    chown -R pikonek:pikonek ${PIKONEK_LOCAL_REPO}
    # Install the cron file
    installCron
}

# Install the scripts from repository to their various locations
installScripts() {
    # Local, named variables
    local str="Installing scripts from ${PIKONEK_LOCAL_REPO}"
    printf "  %b %s...\\n" "${INFO}" "${str}"

    # Install files from local core repository
    if [[ -d "${PIKONEK_LOCAL_REPO}" ]]; then
        # move into the directory
        cd "${PIKONEK_LOCAL_REPO}"
        # Install the scripts by:
        #  -o setting the owner to the user
        #  -Dm755 create all leading components of destination except the last, then copy the source to the destination and setting the permissions to 755
        #
        # This first one is the directory
        install -o "${USER}" -Dm755 -d "${PIKONEK_LOCAL_REPO}/scripts"
        # The rest are the scripts PiKonek needs
        install -o "${USER}" -Dm755 -t "${PIKONEK_LOCAL_REPO}/scripts" ./scripts/tcsave.sh &> /dev/null
        # Create symbolic link for pikonek cli
        ln -s ${PIKONEK_LOCAL_REPO}/pikonek.sh /usr/local/bin/pikonek &> /dev/null
        printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"

    # Otherwise,
    else
        # Show an error and exit
        printf "%b  %b %s\\n" "${OVER}"  "${CROSS}" "${str}"
        printf "\\t\\t%bError: Local repo %s not found, exiting installer%b\\n" "${COL_LIGHT_RED}" "${PIKONEK_LOCAL_REPO}" "${COL_NC}"
        return 1
    fi
}

# Install the configs from PIKONEK_LOCAL_REPO to their various locations
installConfigs() {
    printf "\\n  %b Installing configs from %s...\\n" "${INFO}" "${PIKONEK_LOCAL_REPO}"
    
    # Make sure PiKonek's config files are in place
    if [[ "${useUpdate}" == false ]]; then
        version_check_dnsmasq
    fi

    install -o "${USER}" -Dm755 -d "${PIKONEK_LOCAL_REPO}/configs"
    cp -r  ${PIKONEK_LOCAL_REPO}/configs/** ${PIKONEK_LOCAL_REPO}/configs &> /dev/null
    # and if the Web server conf directory does not exist,
    if [[ ! -d "/etc/lighttpd" ]]; then
        # make it and set the owners
        install -d -m 755 -o "${USER}" -g root /etc/lighttpd
    # Otherwise, if the config file already exists
    elif [[ -f "/etc/lighttpd/lighttpd.conf" ]]; then
        # back up the original
        mv /etc/lighttpd/lighttpd.conf /etc/lighttpd/lighttpd.conf.orig
    fi
    # and copy in the config file PiKonek needs
    install -D -m 644 -T "${PIKONEK_LOCAL_REPO}/configs/${LIGHTTPD_CFG}" /etc/lighttpd/lighttpd.conf
    # Make sure the external.conf file exists, as lighttpd v1.4.50 crashes without it
    touch /etc/lighttpd/external.conf
    chmod 644 /etc/lighttpd/external.conf
    # Make the directories if they do not exist and set the owners
    mkdir -p /run/lighttpd
    chown ${LIGHTTPD_USER}:${LIGHTTPD_GROUP} /run/lighttpd
    mkdir -p /var/cache/lighttpd/compress
    chown ${LIGHTTPD_USER}:${LIGHTTPD_GROUP} /var/cache/lighttpd/compress
    mkdir -p /var/cache/lighttpd/uploads
    chown ${LIGHTTPD_USER}:${LIGHTTPD_GROUP} /var/cache/lighttpd/uploads
}

configureDatabase() {
    local str="Installing pikonek database"
    printf "  %b %s...\\n" "${INFO}" "${str}"
    
    DB_PIKONEK="${PIKONEK_LOCAL_REPO}/database/db.wifirouter"
    if [[ ! -f "$DB_PIKONEK" ]]; then
        touch "${PIKONEK_LOCAL_REPO}/database/db.wifirouter"
    fi

    pushd "${PIKONEK_LOCAL_REPO}" &> /dev/null || return 1
    if ${PIKONEK_LOCAL_REPO}/venv/bin/flask db migrate &> /dev/null; then
        if ${PIKONEK_LOCAL_REPO}/venv/bin/flask db upgrade &> /dev/null; then
            printf "%b  %b %s...\\n" "${OVER}" "${TICK}" "${str}"
        else
            printf "\\t\\t%bError: Unable to install pikonek database, exiting installer%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"
            return 1
        fi
    else
        printf "\\t\\t%bError: Unable to install pikonek database, exiting installer%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"
        return 1
    fi
    # Move back into the directory the user started in
    popd &> /dev/null || return 1
}

configureDhcp() {
    local str="Configuring dhcp and dns"
    printf "  %b %s...\\n" "${INFO}" "${str}"
    if /usr/local/bin/pikonek -a -d ${PIKONEK_LOCAL_REPO}/configs/pikonek_dhcp_mapping.yaml &> /dev/null; then
        printf "%b  %b %s...\\n" "${OVER}" "${TICK}" "${str}"
    else
        printf "\\t\\t%bError: Unable to configure dhcp and dns, exiting installer%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"
        return 1
    fi
}

configureNetwork() {
    local str="Configuring network interface"
    printf "  %b %s...\\n" "${INFO}" "${str}"
    if /usr/local/bin/pikonek -a -n ${PIKONEK_LOCAL_REPO}/configs/pikonek_net_mapping.yaml &> /dev/null; then
        printf "%b  %b %s...\\n" "${OVER}" "${TICK}" "${str}"
    else
        printf "\\t\\t%bError: Unable to configure network interface, exiting installer%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"
        return 1
    fi
}

stop_service() {
    # Stop service passed in as argument.
    # Can softfail, as process may not be installed when this is called
    local str="Stopping ${1} service"
    printf "  %b %s..." "${INFO}" "${str}"
    if is_command systemctl ; then
        systemctl stop "${1}" &> /dev/null || true
    else
        service "${1}" stop &> /dev/null || true
    fi
    printf "%b  %b %s...\\n" "${OVER}" "${TICK}" "${str}"
}

# Start/Restart service passed in as argument
restart_service() {
    # Local, named variables
    local str="Restarting ${1} service"
    printf "  %b %s...\\n" "${INFO}" "${str}"
    # If systemctl exists,
    if is_command systemctl ; then
        # use that to restart the service
        systemctl restart "${1}" &> /dev/null
    # Otherwise,
    else
        # fall back to the service command
        service "${1}" restart &> /dev/null
    fi
    printf "%b  %b %s...\\n" "${OVER}" "${TICK}" "${str}"
}

# Enable service so that it will start with next reboot
enable_service() {
    # Local, named variables
    local str="Enabling ${1} service to start on reboot"
    printf "  %b %s..." "${INFO}" "${str}"
    # If systemctl exists,
    if is_command systemctl ; then
        # use that to enable the service
        systemctl enable "${1}" &> /dev/null
    # Otherwise,
    else
        # use update-rc.d to accomplish this
        update-rc.d "${1}" defaults &> /dev/null
    fi
    printf "%b  %b %s...\\n" "${OVER}" "${TICK}" "${str}"
}

# Disable service so that it will not with next reboot
disable_service() {
    # Local, named variables
    local str="Disabling ${1} service"
    printf "  %b %s..." "${INFO}" "${str}"
    # If systemctl exists,
    if is_command systemctl ; then
        # use that to disable the service
        systemctl disable "${1}" &> /dev/null
    # Otherwise,
    else
        # use update-rc.d to accomplish this
        update-rc.d "${1}" disable &> /dev/null
    fi
    printf "%b  %b %s...\\n" "${OVER}" "${TICK}" "${str}"
}

check_service_active() {
    # If systemctl exists,
    if is_command systemctl ; then
        # use that to check the status of the service
        systemctl is-enabled "${1}" &> /dev/null
    # Otherwise,
    else
        # fall back to service command
        service "${1}" status &> /dev/null
    fi
}

update_package_cache() {
    # Running apt-get update/upgrade with minimal output can cause some issues with
    # requiring user input (e.g password for phpmyadmin see #218)

    # Update package cache on apt based OSes. Do this every time since
    # it's quick and packages can be updated at any time.

    # Local, named variables
    local str="Update local cache of available packages"
    printf "  %b %s..." "${INFO}" "${str}"
    # Create a command from the package cache variable
    if eval "${UPDATE_PKG_CACHE}" &> /dev/null; then
        printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
    # Otherwise,
    else
        # show an error and exit
        printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
        printf "  %bError: Unable to update package cache. Please try \"%s\"%b" "${COL_LIGHT_RED}" "${UPDATE_PKG_CACHE}" "${COL_NC}"
        return 1
    fi
}

# Let user know if they have outdated packages on their system and
# advise them to run a package update at soonest possible.
notify_package_updates_available() {
    # Local, named variables
    local str="Checking ${PKG_MANAGER} for upgraded packages"
    printf "\\n  %b %s..." "${INFO}" "${str}"
    # Store the list of packages in a variable
    updatesToInstall=$(eval "${PKG_COUNT}")

    if [[ -d "/lib/modules/$(uname -r)" ]]; then
        if [[ "${updatesToInstall}" -eq 0 ]]; then
            printf "%b  %b %s... up to date!\\n\\n" "${OVER}" "${TICK}" "${str}"
        else
            printf "%b  %b %s... %s updates available\\n" "${OVER}" "${TICK}" "${str}" "${updatesToInstall}"
            printf "  %b %bIt is recommended to update your OS after installing the PiKonek!%b\\n\\n" "${INFO}" "${COL_LIGHT_GREEN}" "${COL_NC}"
        fi
    else
        printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
        printf "      Kernel update detected. If the install fails, please reboot and try again\\n"
    fi
}

# Install python requirements using requirements.txt
pip_install_packages() {
    printf "  %b Installing required package for pikonek core...\\n" "${INFO}"
    printf "  %b Please wait and have some coffee...\\n" "${INFO}"
    # printf '%*s\n' "$columns" '' | tr " " -;
    # create virtual env
    printf "  %b Creating virtual environment...\\n" "${INFO}"
    python3.7 -m venv "${PIKONEK_LOCAL_REPO}/venv" &> /dev/null
    # upgrade pip
    printf "  %b Upgrading pip...\\n" "${INFO}"
    "${PIKONEK_LOCAL_REPO}"/venv/bin/python3.7 -m pip install -U pip==22.2.2 &> /dev/null
    # Install wheel
    printf "  %b Installing wheel...\\n" "${INFO}"
    "${PIKONEK_LOCAL_REPO}"/venv/bin/python3.7 -m pip install wheel==0.37.1 &> /dev/null
    # Upgrade setuptools
    printf "  %b Upgrading setuptools...\\n" "${INFO}"
    "${PIKONEK_LOCAL_REPO}"/venv/bin/python3.7 -m pip install -U setuptools==59.6.0 &> /dev/null
    "${PIKONEK_LOCAL_REPO}"/venv/bin/python3.7 -m pip install -U simplejson==3.17.6 &> /dev/null


    # Install tcconfig outside of venv
    # python3.7 -m pip install tcconfig==0.25.2 &> /dev/null
    printf "  %b Installing dependencies...\\n" "${INFO}"
    "${PIKONEK_LOCAL_REPO}"/venv/bin/python3.7 -m pip install -r "${PIKONEK_LOCAL_REPO}/requirements.txt" &> /dev/null || \
    { printf "  %bUnable to install required pikonek core dependencies, unable to continue%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"; \
    exit 1; \
    }
    # printf '%*s\n' "$columns" '' | tr " " -;
    printf "\\n"
}

# Uninstall python requirements using requirements.txt
pip_uninstall_packages() {
    printf "  %b Uninstalling required package for pikonek core..." "${INFO}"
    # Remove pyroute2.* file
    # rm -rf /usr/local/lib/python3.7/dist-packages/pyroute2.*
    "${PIKONEK_LOCAL_REPO}"/venv/bin/python3.7 pip uninstall -y -r "${PIKONEK_LOCAL_REPO}/requirements.txt" || \
    { printf "  %bUnable to uninstall required pikonek core dependencies, unable to continue%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"; \
    exit 1; \
    }
}


# What's this doing outside of a function in the middle of nowhere?
counter=0

install_dependent_packages() {
    # Local, named variables should be used here, especially for an iterator
    # Add one to the counter
    counter=$((counter+1))
    # If it equals 1,
    if [[ "${counter}" == 1 ]]; then
        #
        printf "  %b Installer Dependency checks...\\n" "${INFO}"
    else
        #
        printf "  %b Main Dependency checks...\\n" "${INFO}"
    fi

    # Install packages passed in via argument array
    # No spinner - conflicts with set -e
    declare -a installArray

    # Debian based package install - debconf will download the entire package list
    # so we just create an array of packages not currently installed to cut down on the
    # amount of download traffic.
    # NOTE: We may be able to use this installArray in the future to create a list of package that were
    # installed by us, and remove only the installed packages, and not the entire list.
    if is_command apt-get ; then
        # For each package,
        for i in "$@"; do
            printf "  %b Checking for %s..." "${INFO}" "${i}"
            if dpkg-query -W -f='${Status}' "${i}" 2>/dev/null | grep "ok installed" &> /dev/null; then
                printf "%b  %b Checking for %s\\n" "${OVER}" "${TICK}" "${i}"
            else
                printf "%b  %b Checking for %s (will be installed)\\n" "${OVER}" "${INFO}" "${i}"
                installArray+=("${i}")
            fi
        done
        if [[ "${#installArray[@]}" -gt 0 ]]; then
            test_dpkg_lock
            printf "  %b Processing %s install(s) for: %s, please wait...\\n" "${INFO}" "${PKG_MANAGER}" "${installArray[*]}"
            printf '%*s\n' "$columns" '' | tr " " -;
            "${PKG_INSTALL[@]}" "${installArray[@]}"
            printf '%*s\n' "$columns" '' | tr " " -;
            return
        fi
        printf "\\n"
        return 0
    fi

    # Install Fedora/CentOS packages
    for i in "$@"; do
        printf "  %b Checking for %s..." "${INFO}" "${i}"
        if "${PKG_MANAGER}" -q list installed "${i}" &> /dev/null; then
            printf "%b  %b Checking for %s\\n" "${OVER}" "${TICK}" "${i}"
        else
            printf "%b  %b Checking for %s (will be installed)\\n" "${OVER}" "${INFO}" "${i}"
            installArray+=("${i}")
        fi
    done
    if [[ "${#installArray[@]}" -gt 0 ]]; then
        printf "  %b Processing %s install(s) for: %s, please wait...\\n" "${INFO}" "${PKG_MANAGER}" "${installArray[*]}"
        printf '%*s\n' "$columns" '' | tr " " -;
        "${PKG_INSTALL[@]}" "${installArray[@]}"
        printf '%*s\n' "$columns" '' | tr " " -;
        return
    fi
    printf "\\n"
    return 0
}


# Install the Web interface dashboard
installpikonekWebServer() {
    local str="Backing up index.lighttpd.html"
    printf "  %b %s..." "${INFO}" "${str}"
    # If the default index file exists,
    if [[ -f "${webroot}/index.lighttpd.html" ]]; then
        # back it up
        mv ${webroot}/index.lighttpd.html ${webroot}/index.lighttpd.orig
        printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
    # Otherwise,
    else
        # don't do anything
        printf "%b  %b %s\\n" "${OVER}" "${INFO}" "${str}"
        printf "      No default index.lighttpd.html file found... not backing up\\n"
    fi
    
    printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"

    # Install Sudoers file
    local str="Installing sudoer file"
    printf "\\n  %b %s..." "${INFO}" "${str}"
    # Make the .d directory if it doesn't exist
    install -d -m 755 /etc/sudoers.d/
    # and copy in the pikonek sudoers file
    install -m 0640 ${PIKONEK_LOCAL_REPO}/scripts/pikonek.sudo /etc/sudoers.d/pikonek
    # Add lighttpd user (OS dependent) to sudoers file
    echo "${LIGHTTPD_USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/pikonek
    echo "pikonek ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/pikonek

    # If the Web server user is lighttpd,
    if [[ "$LIGHTTPD_USER" == "lighttpd" ]]; then
        # Allow executing pikonek via sudo with Fedora
        # Usually /usr/local/bin ${PIKONEK_BIN_DIR} is not permitted as directory for sudoable programs
        echo "Defaults secure_path = /sbin:/bin:/usr/sbin:/usr/bin:${PIKONEK_BIN_DIR}" >> /etc/sudoers.d/pikonek
    fi
    # Set the strict permissions on the file
    chmod 0440 /etc/sudoers.d/pikonek
    printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
}

# Install the logrotate script
installLogrotate() {
    local str="Installing latest logrotate script"
    printf "\\n  %b %s..." "${INFO}" "${str}"
    # Copy the file over from the local repo
    install -D -m 644 -T ${PIKONEK_LOCAL_REPO}/scripts/logrotate /etc/logrotate.d/pikonek
    logusergroup="$(stat -c '%U %G' /var/log)"
    # If the variable has a value,
    if [[ ! -z "${logusergroup}" ]]; then
        #
        sed -i "s/# su #/su ${logusergroup}/g;" /etc/logrotate.d/pikonek
    fi
    printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
}

# Installs a cron file
installCron() {
    # Install the cron job
    local str="Installing latest Cron script"
    printf "\\n  %b %s..." "${INFO}" "${str}"
    # Copy the cron file over from the local repo
    # File must not be world or group writeable and must be owned by root
    install -D -m 644 -T -o root -g root ${PIKONEK_LOCAL_REPO}/scripts/pikonek.cron /etc/cron.d/pikonek
    printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
}

# Check if the pikonek user exists and create if it does not
create_pikonek_user() {
    local str="Checking for user 'pikonek'"
    printf "  %b %s..." "${INFO}" "${str}"
    # If the user pikonek exists,
    if id -u pikonek &> /dev/null; then
        # if group exists
        if getent group pikonek > /dev/null 2>&1; then
            # just show a success
            printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
        else
            local str="Checking for group 'pikonek'"
            printf "  %b %s..." "${INFO}" "${str}"
            local str="Creating group 'pikonek'"
            # if group can be created
            if groupadd pikonek; then
                printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
                local str="Adding user 'pikonek' to group 'pikonek'"
                printf "  %b %s..." "${INFO}" "${str}"
                # if pikonek user can be added to group pikonek
                if usermod -g pikonek pikonek; then
                    printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
                else
                    printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
                fi
            else
                printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
            fi
        fi
    # Otherwise,
    else
        printf "%b  %b %s" "${OVER}" "${CROSS}" "${str}"
        local str="Creating user 'pikonek'"
        printf "%b  %b %s..." "${OVER}" "${INFO}" "${str}"
        # create her with the useradd command
        if getent group pikonek > /dev/null 2>&1; then
            # add primary group pikonek as it already exists
            if useradd -r --no-user-group -g pikonek -s /usr/sbin/nologin pikonek; then
                printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
            else
                printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
            fi
        else
            # add user pikonek with default group settings
            if useradd -r -s /usr/sbin/nologin pikonek; then
                printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
            else
                printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
            fi
        fi
    fi
}

# Get predictable name
get_net_names() {
    if grep -q "net.ifnames=0" $CMDLINE || [ "$(readlink -f /etc/systemd/network/99-default.link)" = "/dev/null" ] ; then
        echo 0
    else
        echo 1
    fi
}

do_net_names () {
    local str="Checking for predictable names"
    printf "%b  %b %s..." "${OVER}" "${INFO}" "${str}"
    if [ $(get_net_names) -eq 1 ]; then
        str="Disabling predictable names"
        printf "%b  %b %s...\\n" "${OVER}" "${INFO}" "${str}"
        if [ $(is_pi) -eq 1 ]; then
            if [ -f /etc/default/grub ]; then
                sed -i "s/GRUB_CMDLINE_LINUX=\"\(.*\)\"/GRUB_CMDLINE_LINUX=\"\1net.ifnames=0 biosdevname=0\"/" /etc/default/grub
                update-grub > /dev/null 2>&1
            fi
        fi
        ln -sf /dev/null /etc/systemd/network/99-default.link
        printf "%b  %b %s...\\n" "${OVER}" "${TICK}" "${str}"
        printf "\\n  %bPredictables name detected, exiting installer. Please reboot the system now to continue then run the installer again.%b\\n" "${COL_LIGHT_RED}" "${COL_NC}";
        sleep 3
        printf "\\n  %bRebooting now.%b\\n" "${COL_LIGHT_RED}" "${COL_NC}";
        reboot
        exit 1
    else
        str="Predictable names is disabled"
    fi
    printf "%b  %b %s...\\n" "${OVER}" "${TICK}" "${str}"
}

# Final export of variables
finalExports() {
    ARCH=$(dpkg --print-architecture)
    local lan_subnet=$(ipcalc -cn $LAN_IPV4_ADDRESS | awk 'FNR == 2 {print $2}')
    local lan_ip_v4=$(ipcalc -cn $LAN_IPV4_ADDRESS | awk 'FNR == 1 {print $2}')
    if [ "$WLAN_AP" -eq 1 ]; then
    local wlan_subnet=$(ipcalc -cn $WLAN_IPV4_ADDRESS | awk 'FNR == 2 {print $2}')
    local wlan_ip_v4=$(ipcalc -cn $WLAN_IPV4_ADDRESS | awk 'FNR == 1 {print $2}')
    fi

    # Set the pikonek_net_mapping.yaml
    PIKONEK_LAN_INTERFACE="${PIKONKE_LAN_ORIG_INTERFACE}"
    PIKONEK_WLAN_INTERFACE="${PIKONKE_WLAN_ORIG_INTERFACE}"
    PIKONEK_WAN_INTERFACE="${PIKONKE_WAN_ORIG_INTERFACE}"
    {
    echo -e "network_config:"
    echo -e "- addresses:"
    echo -e "  - ip_netmask: ${LAN_IPV4_ADDRESS}"
    echo -e "  hotplug: false"
    echo -e "  is_wan: false"
    echo -e "  hwaddr: ${PIKONEK_LAN_MAC_INTERFACE}"
    echo -e "  name: ${PIKONEK_LAN_INTERFACE}"
    echo -e "  orig_name: lan1"
    echo -e "  alias: ${PIKONEK_LAN_ALIAS}"
    echo -e "  pci_address: '${PIKONEK_LAN_DEVICE_ID}'"
    echo -e "  type: interface"
    echo -e "  use_dhcp: false"
    if [ "$WLAN_AP" -eq 1 ]; then
        echo -e "- addresses:"
        echo -e "  - ip_netmask: ${WLAN_IPV4_ADDRESS}"
        echo -e "  hotplug: false"
        echo -e "  is_wan: false"
        echo -e "  hwaddr: ${PIKONEK_WLAN_MAC_INTERFACE}"
        echo -e "  access_point: true"
        echo -e "  orig_name: wln1"
        echo -e "  alias: ${PIKONEK_WLAN_ALIAS}"
        echo -e "  pci_address: '${PIKONEK_WLAN_DEVICE_ID}'"
        echo -e "  is_wlan: true"
        echo -e "  name: ${PIKONEK_WLAN_INTERFACE}"
        echo -e "  type: interface"
        echo -e "  use_dhcp: false"
    fi
    if [ "$PIKONEK_WAN_DHCP_INTERFACE" = false ]; then
    echo -e "- addresses:"
    echo -e "  - ip_netmask: ${WAN_IPV4_ADDRESS}"
    echo -e "  hotplug: false"
    echo -e "  is_wan: true"
    echo -e "  name: ${PIKONEK_WAN_INTERFACE}"
    echo -e "  hwaddr: ${PIKONEK_WAN_MAC_INTERFACE}"
    echo -e "  orig_name: wan0"
    echo -e "  alias: ${PIKONEK_WAN_ALIAS}"
    echo -e "  pci_address: '${PIKONEK_WAN_DEVICE_ID}'"
    echo -e "  type: interface"
    echo -e "  use_dhcp: ${PIKONEK_WAN_DHCP_INTERFACE}"
    else
    echo -e "- hotplug: false"
    echo -e "  is_wan: true"
    echo -e "  name: ${PIKONEK_WAN_INTERFACE}"
    echo -e "  hwaddr: ${PIKONEK_WAN_MAC_INTERFACE}"
    echo -e "  orig_name: wan0"
    echo -e "  alias: ${PIKONEK_WAN_ALIAS}"
    echo -e "  pci_address: '${PIKONEK_WAN_DEVICE_ID}'"
    echo -e "  type: interface"
    echo -e "  use_dhcp: ${PIKONEK_WAN_DHCP_INTERFACE}"
    fi
    } > "${PIKONEK_LOCAL_REPO}/configs/pikonek_net_mapping.yaml"

    # set the pikonek_dhcp_mapping.yaml
    {
    echo -e "dhcp_script: /etc/pikonek/scripts/check_client.sh"
    echo -e "domain: pi.konek"
    echo -e "domain_needed: true"
    echo -e "addn_hosts:"
    echo -e "- host: /etc/pikonek/configs/pikonek.host"
    echo -e "bind_dynamic: true"
    echo -e "bogus_priv: true"
    echo -e "port: 53" # enable dns server
    echo -e "dhcp_authoritative: true"
    echo -e "no_hosts: false"
    echo -e "mac_blocked_list: []"
    echo -e "no_resolv: false"
    echo -e "resolv_file: /etc/pikonek/configs/pikonek.resolv"
    echo -e "static_mapping: []"
    echo -e "ipset: []"
    echo -e "name_server:"
    echo -e "- ip: ${pikonek_DNS_1}"
    echo -e "- ip: ${pikonek_DNS_2}"
    echo -e "dhcp_range:"
    echo -e "- end: ${pikonek_RANGE_2}"
    echo -e "  interface: ${PIKONEK_LAN_INTERFACE}"
    echo -e "  start: ${pikonek_RANGE_1}"
    echo -e "  lease_time: infinite"
    echo -e "  subnet: ${lan_subnet}"
    if [ "$WLAN_AP" -eq 1 ]; then
    echo -e "- end: ${wpikonek_RANGE_2}"
    echo -e "  interface: ${PIKONEK_WLAN_INTERFACE}"
    echo -e "  start: ${wpikonek_RANGE_1}"
    echo -e "  lease_time: infinite"
    echo -e "  subnet: ${wlan_subnet}"
    fi
    echo -e "dhcp_option:"
    echo -e "- interface: ${PIKONEK_LAN_INTERFACE}"
    echo -e "  ipaddress: ${lan_ip_v4}"
    echo -e "  option: 3"
    if [ "$WLAN_AP" -eq 1 ]; then
    echo -e "- interface: ${PIKONEK_WLAN_INTERFACE}"
    echo -e "  ipaddress: ${wlan_ip_v4}"
    echo -e "  option: 3"
    fi
    echo -e "hosts:"
    echo -e "- ip: ${lan_ip_v4}"
    echo -e "  name: pi.konek"
    if [ "$WLAN_AP" -eq 1 ]; then
    echo -e "- ip: ${wlan_ip_v4}"
    echo -e "  name: pi.konek"
    fi 
    echo -e "interface:"
    echo -e "- name: ${PIKONEK_LAN_INTERFACE}"
    if [ "$WLAN_AP" -eq 1 ]; then
    echo -e "- name: ${PIKONEK_WLAN_INTERFACE}"
    fi
    } > "${PIKONEK_LOCAL_REPO}/configs/pikonek_dhcp_mapping.yaml"

    # write the wpa config
    if [ "$WLAN_AP" -eq 1 ]; then
    {
    echo -e "- mode: ${ap_mode}"
    echo -e "  ssid: ${SSID}"
    echo -e "  country: ${COUNTRY}"
    if [ "$psk" != "" ]; then
    echo -e "  psk: ${psk}"
    fi
    echo -e "  key_mgmt: ${key_mgmt}"
    echo -e "  interface: ${PIKONEK_WLAN_INTERFACE}"
    } > "${PIKONEK_LOCAL_REPO}/configs/pikonek_wpa_mapping.yaml"
    fi

    # set pikonek.yaml
    {
    echo -e "firewall_rule:"
    echo -e "   fw_destroy:"
    echo -e "   - -t nat -D POSTROUTING -o \$wan_interface -j MASQUERADE"
    echo -e "   fw_init:"
    echo -e "   - -t nat -A POSTROUTING -o \$wan_interface -j MASQUERADE"
    echo -e "name: Pikonek Core"
    echo -e "port: 5000"
    echo -e "startup_service:"
    echo -e "- mosquitto: false"
    echo -e "wan_interface: wan0"
    echo -e "architecture: ${ARCH}"
    echo -e "os: ${OS}"
    echo -e "time_zone: ${PIKONEK_TIME_ZONE}"
    } > "${PIKONEK_LOCAL_REPO}/configs/pikonek.yaml"
    {
    echo -e "nameserver ${pikonek_DNS_1}"
    echo -e "nameserver ${pikonek_DNS_2}"
    } > "${PIKONEK_LOCAL_REPO}/configs/pikonek.resolv"

    # set pikonek hostname
    {
    echo -e "${lan_ip_v4} pi.konek"
    if [ "$WLAN_AP" -eq 1 ]; then
    echo -e "${wlan_ip_v4} pi.konek"
    fi 
    } > "${PIKONEK_LOCAL_REPO}/configs/pikonek.host"

    #set captive portal config
    {
    echo -e "description: Captive Portal for Pikonek"
    echo -e "enable: true"
    echo -e "fw_destroy:"
    echo -e "- command: -t mangle -F CAPTIVE_OUTGOING"
    echo -e "- command: -t mangle -F CAPTIVE_INCOMING"
    echo -e "- command: -t mangle -X CAPTIVE_OUTGOING"
    echo -e "- command: -t mangle -X CAPTIVE_INCOMING"
    echo -e "- command: -t mangle -F CAPTIVE_BLOCKED"
    echo -e "- command: -t mangle -X CAPTIVE_BLOCKED"
    echo -e "- command: -t nat -F CAPTIVE_OUTGOING"
    echo -e "- command: -t nat -X CAPTIVE_OUTGOING"
    echo -e "- command: -t filter -F CAPTIVE_TO_INTERNET"
    echo -e "- command: -t filter -F CAPTIVE_AUTHENTICATED"
    echo -e "- command: -t filter -X CAPTIVE_TO_INTERNET"
    echo -e "- command: -t filter -X CAPTIVE_AUTHENTICATED"
    echo -e "fw_init:"
    echo -e "   create_new_chain:"
    echo -e "   - command: -t mangle -N CAPTIVE_INCOMING"
    echo -e "   - command: -t mangle -N CAPTIVE_OUTGOING"
    echo -e "   - command: -t mangle -N CAPTIVE_BLOCKED"
    echo -e "   - command: -t nat -N CAPTIVE_OUTGOING"
    echo -e "   - command: -t filter -N CAPTIVE_TO_INTERNET"
    echo -e "   - command: -t filter -N CAPTIVE_AUTHENTICATED"
    echo -e "   create_rule:"
    echo -e "   - command: -t nat -I CAPTIVE_OUTGOING 1 -m mark --mark \$FW_MARK_AUTHENTICATED -j RETURN"
    echo -e "   - command: -t nat -A CAPTIVE_OUTGOING -j ACCEPT"
    echo -e "   - command: -t filter -A CAPTIVE_TO_INTERNET -m mark --mark \$FW_MARK_BLOCKED -j DROP"
    echo -e "   - command: -t filter -A CAPTIVE_TO_INTERNET -m conntrack --ctstate INVALID -j DROP"
    echo -e "   - command: -t filter -A CAPTIVE_TO_INTERNET -m mark --mark \$FW_MARK_AUTHENTICATED -j CAPTIVE_AUTHENTICATED"
    echo -e "   - command: -t filter -A CAPTIVE_TO_INTERNET -j REJECT --reject-with icmp-port-unreachable"
    echo -e "   - command: -t filter -A CAPTIVE_AUTHENTICATED -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
    echo -e "   - command: -t filter -A CAPTIVE_AUTHENTICATED -m mark --mark \$FW_MARK_AUTHENTICATED -j ACCEPT"
    echo -e "   - command: -t filter -A CAPTIVE_AUTHENTICATED -j REJECT --reject-with icmp-port-unreachable"
    echo -e "   create_rule_for_interface:"
    echo -e "   - command: -t mangle -A PREROUTING -i \$gw_interface -j CAPTIVE_OUTGOING"
    echo -e "   - command: -t mangle -A PREROUTING -i \$gw_interface -j CAPTIVE_BLOCKED"
    echo -e "   - command: -t nat -A CAPTIVE_OUTGOING -i \$gw_interface -p tcp -m tcp --dport 80 -j DNAT --to-destination \$gw_address"
    echo -e "   - command: -t mangle -A POSTROUTING -o \$gw_interface -j CAPTIVE_INCOMING"
    echo -e "   - command: -t nat -A PREROUTING -i \$gw_interface -j CAPTIVE_OUTGOING"
    echo -e "   - command: -t filter -A FORWARD -i \$gw_interface -j CAPTIVE_TO_INTERNET"
    echo -e "fw_mark_authenticated: 1000"
    echo -e "fw_mark_blocked: 2000"
    echo -e "id: pikonekCaptive"
    echo -e "interface:"
    echo -e "- coinslot: false"
    echo -e "  auto_connect: false"
    echo -e "  auto_disconnect: false"
    echo -e "  enable_pause_button: false"
    echo -e "  name: ${PIKONEK_LAN_INTERFACE}"
    echo -e "  voucher: false"
    echo -e "log_file: /var/log/pikonek.log"
    echo -e "name: Captive Portal"
    echo -e "port: 5000"
    } > "${PIKONEK_LOCAL_REPO}/configs/packages/captive_portal.yaml"

    # set coinslot config
    {
    echo -e "coins:"
    echo -e "- currency: 10"
    echo -e "  pulse: 10"
    echo -e "  time: 4"
    echo -e "  unit: hour"
    echo -e "- currency: 5"
    echo -e "  pulse: 5"
    echo -e "  time: 1"
    echo -e "  unit: hour"
    echo -e "- currency: 1"
    echo -e "  pulse: 1"
    echo -e "  time: 15"
    echo -e "  unit: minute"
    echo -e "enable_gpio_relay: false"
    echo -e "gpio_coin: 2"
    echo -e "gpio_relay: 3"
    echo -e "name: PiKonek Coinslot"
    } > "${PIKONEK_LOCAL_REPO}/configs/packages/coinslot.yaml"

    #set ngrok config
    {
    echo -e "authtoken:"
    echo -e "log_level: info"
    echo -e "region: us"
    echo -e "enable: false"
    echo -e "tunnels:"
    echo -e "   pikonek:"
    echo -e "       addr: 5050"
    echo -e "       proto: http"
    echo -e "   ssh:"
    echo -e "       addr: 22"
    echo -e "       proto: tcp"
    } > "${PIKONEK_LOCAL_REPO}/configs/ngrok.yaml"

    # set pikonek init
    {
    echo -e "TIMEZONE=${PIKONEK_TIME_ZONE}"
    echo -e "mosquitto=False"
    } > "${PIKONEK_LOCAL_REPO}/configs/pikonekInit.cfg"

    # set environment variable
    # generate secret key
    secret=$(tr -dc _A-Z-a-z-0-9 < /dev/urandom | head -c 10)
    {
    echo -e "SQLALCHEMY_DATABASE_URI=sqlite:////etc/pikonek/database/db.wifirouter?check_same_thread=False"
    echo -e "SECRET_KEY=${secret}"
    } > "${PIKONEK_LOCAL_REPO}/pikonek/.env"

}

configureSQM() {
    local str="Configuring sqm"
    printf "  %b %s...\\n" "${INFO}" "${str}"
    if is_repo "${PIKONEK_LOCAL_REPO}/sqm-scripts"; then
        # Update the repo, returning an error message on failure
        update_repo "${PIKONEK_LOCAL_REPO}/sqm-scripts" || { printf "\\n  %b: Could not update local repository. Contact support.%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"; exit 1; }
    # If it's not a .git repo,
    else
        # Show an error
        printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
        # Attempt to make the repository, showing an error on failure
        make_repo "${PIKONEK_LOCAL_REPO}/sqm-scripts" "${pikonekSQMUrl}" || { printf "\\n  %bError: Could not create local repository. Contact support.%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"; exit 1; }
    fi

    pushd "${PIKONEK_LOCAL_REPO}/sqm-scripts" &> /dev/null || return 1
    make install
    popd &> /dev/null || return 1

    if [[ ! -f "${PIKONEK_LOCAL_REPO}/configs/sqm.yaml" ]]; then    
        # create initial config
        {
        echo -e "enable: false"
        echo -e "uplink: 1000"
        echo -e "downlink: 5000"
        echo -e "package_install: true"
        } > "${PIKONEK_LOCAL_REPO}/configs/sqm.yaml"
    fi

    printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
}

configurePPPoE() {
    local str="Configuring ppoe server"
    printf "  %b %s...\\n" "${INFO}" "${str}"
    # set debian front end to non interactive
    export DEBIAN_FRONTEND=noninteractive
    distro_check
    PPPOE=(ppp)
    install_dependent_packages "${PPPOE[@]}"
    if is_repo "${PIKONEK_LOCAL_REPO}/rp-pppoe"; then
        # Update the repo, returning an error message on failure
        update_repo "${PIKONEK_LOCAL_REPO}/rp-pppoe" || { printf "\\n  %b: Could not update local repository. Contact support.%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"; exit 1; }
    # If it's not a .git repo,
    else
        # Show an error
        printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
        # Attempt to make the repository, showing an error on failure
        make_repo "${PIKONEK_LOCAL_REPO}/rp-pppoe" "${pikonekPPPoeUrl}" || { printf "\\n  %bError: Could not create local repository. Contact support.%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"; exit 1; }
    fi

    pushd "${PIKONEK_LOCAL_REPO}/rp-pppoe/src" &> /dev/null || return 1
    ./configure
    make
    make install
    # copy scripts
    cp "${PIKONEK_LOCAL_REPO}/rp-pppoe/ip-up" /etc/ppp/ip-up
    cp "${PIKONEK_LOCAL_REPO}/rp-pppoe/ip-down" /etc/ppp/ip-down
    # Copy the file over from the local repo
    install -D -m 644 -T  ${PIKONEK_LOCAL_REPO}/rp-pppoe/logrotate /etc/logrotate.d/pppoe
    logusergroup="$(stat -c '%U %G' /var/log)"
    # If the variable has a value,
    if [[ ! -z "${logusergroup}" ]]; then
        #
        sed -i "s/# su #/su ${logusergroup}/g;" /etc/logrotate.d/pppoe
    fi
    # chmod 600 /etc/ppp/chap-secrets
    # chmod 600 /etc/ppp/pap-secrets
    popd &> /dev/null || return 1

    if [[ ! -f "${PIKONEK_LOCAL_REPO}/configs/pppoe.yaml" ]]; then    
        # create initial config
        {
        echo -e "enable: false"
        echo -e "interfaces: []"
        echo -e "package_install: true"
        echo -e "total_user_count: 100"
        echo -e "authentication: local"
        echo -e "user_max_logins: 1"
        echo -e "server_address: 10.0.0.1"
        echo -e "remote_address_range: 10.0.0.2"
        echo -e "subnet_mask: 23"
        echo -e "dns_servers: [10.0.0.1, 8.8.8.8]"
        } > "${PIKONEK_LOCAL_REPO}/configs/pppoe.yaml"
    fi

    printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
}

# SELinux
checkSelinux() {
    local DEFAULT_SELINUX
    local CURRENT_SELINUX
    local SELINUX_ENFORCING=0
    # Check for SELinux configuration file and getenforce command
    if [[ -f /etc/selinux/config ]] && command -v getenforce &> /dev/null; then
        # Check the default SELinux mode
        DEFAULT_SELINUX=$(awk -F= '/^SELINUX=/ {print $2}' /etc/selinux/config)
        case "${DEFAULT_SELINUX,,}" in
            enforcing)
                printf "  %b %bDefault SELinux: %s%b\\n" "${CROSS}" "${COL_RED}" "${DEFAULT_SELINUX}" "${COL_NC}"
                SELINUX_ENFORCING=1
                ;;
            *)  # 'permissive' and 'disabled'
                printf "  %b %bDefault SELinux: %s%b\\n" "${TICK}" "${COL_GREEN}" "${DEFAULT_SELINUX}" "${COL_NC}"
                ;;
        esac
        # Check the current state of SELinux
        CURRENT_SELINUX=$(getenforce)
        case "${CURRENT_SELINUX,,}" in
            enforcing)
                printf "  %b %bCurrent SELinux: %s%b\\n" "${CROSS}" "${COL_RED}" "${CURRENT_SELINUX}" "${COL_NC}"
                SELINUX_ENFORCING=1
                ;;
            *)  # 'permissive' and 'disabled'
                printf "  %b %bCurrent SELinux: %s%b\\n" "${TICK}" "${COL_GREEN}" "${CURRENT_SELINUX}" "${COL_NC}"
                ;;
        esac
    else
        echo -e "  ${INFO} ${COL_GREEN}SELinux not detected${COL_NC}";
    fi
    # Exit the installer if any SELinux checks toggled the flag
    if [[ "${SELINUX_ENFORCING}" -eq 1 ]] && [[ -z "${pikonek_SELINUX}" ]]; then
        printf "  PiKonek does not provide an SELinux policy as the required changes modify the security of your system.\\n"
        printf "  Please refer to https://wiki.centos.org/HowTos/SELinux if SELinux is required for your deployment.\\n"
        printf "\\n  %bSELinux Enforcing detected, exiting installer%b\\n" "${COL_LIGHT_RED}" "${COL_NC}";
        exit 1;
    fi
}

# Installation complete message with instructions for the user
displayFinalMessage() {
    # Store a message in a variable and display it
    additional="View the web interface at http://pi.konek/ or http://${LAN_IPV4_ADDRESS%/*}/
Your Admin Webpage login password is ${1}"

    # Final completion message to user
    whiptail --msgbox --backtitle "Done." --title "Installation Complete!" "Successfully installed PiKonek on your system.
Please reboot your sytem.
The install log is in ${PIKONEK_LOCAL_REPO}.
${additional}" "${r}" "${c}"
}

clone_or_update_repos() {
    # so get git files for script
    getGitFiles "${PIKONEK_INSTALL_DIR}" ${pikonekScriptGitUrl} || \
    { printf "  %bUnable to clone %s into %s, unable to continue%b\\n" "${COL_LIGHT_RED}" "${pikonekScriptGitUrl}" "${PIKONEK_INSTALL_DIR}" "${COL_NC}"; \
    exit 1; \
    }
    # so get git files for Core
    getGitFiles "${PIKONEK_LOCAL_REPO}" ${pikonekGitUrl} || \
    { printf "  %bUnable to clone %s into %s, unable to continue%b\\n" "${COL_LIGHT_RED}" "${pikonekGitUrl}" "${PIKONEK_LOCAL_REPO}" "${COL_NC}"; \
    exit 1; \
    }

    if [[ "${useUpdate}" == false ]]; then
        git config --global --add safe.directory /etc/.pikonek
        git config --global --add safe.directory /etc/pikonek
    fi

}

make_temporary_log() {
    # Create a random temporary file for the log
    TEMPLOG=$(mktemp /tmp/pikonek_temp.XXXXXX)
    # Open handle 3 for templog
    # https://stackoverflow.com/questions/18460186/writing-outputs-to-log-file-and-console
    exec 3>"$TEMPLOG"
    # Delete templog, but allow for addressing via file handle
    # This lets us write to the log without having a temporary file on the drive, which
    # is meant to be a security measure so there is not a lingering file on the drive during the install process
    rm "$TEMPLOG"
}

main() {
    ######## FIRST CHECK ########
    # Must be root to install
    local str="Root user check"
    printf "\\n"

    # If the user's id is zero,
    if [[ "${EUID}" -eq 0 ]]; then
        # they are root and all is good
        if [[ "${useUpdate}" == false ]]; then
            printf "  %b %s\\n" "${TICK}" "${str}"
            # Show the PiKonek logo so people know it's genuine since the logo and name are trademarked
            show_ascii_berry
        fi
        make_temporary_log
    # Otherwise,
    else
        # They do not have enough privileges, so let the user know
        printf "  %b %s\\n" "${CROSS}" "${str}"
        printf "  %b %bScript called with non-root privileges%b\\n" "${INFO}" "${COL_LIGHT_RED}" "${COL_NC}"
        printf "      The PiKonek requires elevated privileges to install and run\\n"
        printf "      Please check the installer for any concerns regarding this requirement\\n"
        printf "  %b Sudo utility check" "${INFO}"

        # If the sudo command exists,
        if is_command sudo ; then
            printf "%b  %b Sudo utility check\\n" "${OVER}"  "${TICK}"
            # Download the install script and run it with admin rights
            exit $?
        # Otherwise,
        else
            # Let them know they need to run it as root
            printf "%b  %b Sudo utility check\\n" "${OVER}" "${CROSS}"
            printf "  %b Sudo is needed to run pikonek commands\\n\\n" "${INFO}"
            printf "  %b %bPlease re-run this installer as root${COL_NC}\\n" "${INFO}" "${COL_LIGHT_RED}"
            exit 1
        fi
    fi

    # Check for supported distribution
    distro_check

    # Start the installer
    # Verify there is enough disk space for the install
    if [[ "${skipSpaceCheck}" == true ]]; then
        printf "  %b Skipping free disk space verification\\n" "${INFO}"
    else
        verifyFreeDiskSpace
    fi

    # Check nic
    nic_check

    # Notify user of package availability
    notify_package_updates_available

    # Install packages used by this installation script
    install_dependent_packages "${INSTALLER_DEPS[@]}"

    # Check that the installed OS is officially supported - display warning if not
    os_check

    # Disable predictable names
    # do_net_names

    # Check if SELinux is Enforcing
    # checkSelinux

    if [[ "${useUpdate}" == false ]]; then
        # Create directory for PiKonek storage
        install -d -m 755 ${PIKONEK_INSTALL_DIR}
        install -d -m 755 ${PIKONEK_LOCAL_REPO}

        # clone repos
        clone_or_update_repos

        # Display welcome dialogs
        welcomeDialogs

        # Set timezone
        setTimezone

        # Determine available interfaces
        get_available_interfaces
        get_available_lan_interfaces
        get_available_wlan_interfaces

        # Set up wan interface
        setupWanInterface

        # Set up lan interface
        setupLanInterface

        # Decide what upstream DNS Servers to use
        setupWlanInterface

        # setDns
        setDNS

        # Install docker engine
        installDocker
    fi

    # Update repos
    if [[ "${useUpdate}" == true ]]; then
        chown -R root:root ${PIKONEK_LOCAL_REPO}
        update_repo "${PIKONEK_INSTALL_DIR}" ${pikonekScriptGitUrl} || { printf "\\n  %b: Could not update local repository. Contact support.%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"; exit 1; }
        update_repo "${PIKONEK_LOCAL_REPO}" ${pikonekGitUrl} || { printf "\\n  %b: Could not update local repository. Contact support.%b\\n" "${COL_LIGHT_RED}" "${COL_NC}"; exit 1; }
    fi

    # On some systems, lighttpd is not enabled on first install. We need to enable it here if the user
    # has chosen to install the web interface, else the `LIGHTTPD_ENABLED` check will fail
    enable_service lighttpd
    # Determine if lighttpd is correctly enabled
    if check_service_active "lighttpd"; then
        LIGHTTPD_ENABLED=true
    else
        LIGHTTPD_ENABLED=false
    fi
    # Create the pikonek user
    create_pikonek_user

    # Install and log everything to a file
    installpikonek | tee -a /proc/$$/fd/3

    if [[ "${useUpdate}" == false ]]; then
        finalExports
    fi

    # Install the Core dependencies
    pip_install_packages
    
    configurePikonekCore
    # configure the database
    configureDatabase
    
    if [[ "${useUpdate}" == false ]]; then
        # Add password to web UI if there is none
        pw=""
        # generate a random password
        pw=$(tr -dc _A-Z-a-z-0-9 < /dev/urandom | head -c 8)
        /usr/local/bin/pikonek -a -p "${pw}"
        # configure pihole docker
        configurePihole $pw
    fi

    # shellcheck disable=SC1091
    # configure the dhcp and dns
    configureDhcp
    # configure the network interface
    configureNetwork
    # configure wireless access point
    if [[ -f "${PIKONEK_LOCAL_REPO}/configs/pikonek_wpa_mapping.yaml" ]]; then
        configureWirelessAP
    fi

    # configure mosquitto
    configureMosquitto
    # change back to root
    if [[ "${useUpdate}" == false ]]; then
        stop_service mosquitto
        # disable service
        disable_service mosquitto
    fi

    # Enable service
    enable_service S70piknkmain
    enable_service ntp

    if check_service_active "S70piknkmain"; then
        PIKONEK_MAIN_ENABLED=true
    else
        PIKONEK_MAIN_ENABLED=false
    fi

    if [[ "${PIKONEK_MAIN_ENABLED}" == false ]]; then
        # restart_service S70piknkmain
        enable_service S70piknkmain
    else
        printf "  %b S70piknkmain is disabled, skipping service restart\\n" "${INFO}"
    fi

    if [[ "${LIGHTTPD_ENABLED}" == true ]]; then
        restart_service lighttpd
        enable_service lighttpd
    else
        printf "  %b Lighttpd is disabled, skipping service restart\\n" "${INFO}"
    fi

    printf "  %b Restarting services...\\n" "${INFO}"

    # Configure captive portal
    configureCaptivePortalRule

    # change back to root
    if [[ "${useUpdate}" == true ]]; then
        chown -R root:root ${PIKONEK_LOCAL_REPO}
    fi

    # Get version
    printf "  %b Checking version...\\n" "${INFO}"
    /etc/.pikonek/updatecheck.sh
    /etc/.pikonek/updatecheck.sh x remote
    printf "  %b Checking version...\\n" "${TICK}"

    if [[ "${useUpdate}" == false ]]; then
        displayFinalMessage "${pw}"
        if (( ${#pw} > 0 )) ; then
            # display the password
            printf "  %b Web Interface password: %b%s%b\\n" "${INFO}" "${COL_LIGHT_GREEN}" "${pw}" "${COL_NC}"
            printf "  %b This can be changed using 'pikonek -a -p'\\n\\n" "${INFO}"
        fi

        printf "  %b View the web interface at http://pi.konek/ or http://%s/\\n\\n" "${INFO}" "${LAN_IPV4_ADDRESS%/*}"
        INSTALL_TYPE="Installation"
    else
        INSTALL_TYPE="Update"
    fi

    if [[ "${INSTALL_TYPE}" == "Update" ]]; then
        printf "\\n"
        /usr/local/bin/pikonek -v --current
    fi

    # change back to pikonek
    if [[ "${useUpdate}" == true ]]; then
        chown -R pikonek:pikonek ${PIKONEK_LOCAL_REPO}
    fi

    printf "  %b Please reboot your system.\\n" "${INFO}"
    printf "%b%s Complete! %b\\n" "${COL_LIGHT_GREEN}" "${INSTALL_TYPE}" "${COL_NC}"

}

# allow to source this script without running it
if [[ "${SKIP_INSTALL}" != true ]] ; then
    main "$@"
fi
