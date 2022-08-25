#!/usr/bin/env bash
# shellcheck disable=SC1090
# source taken from pihole 2017 Pi-hole, LLC (https://pi-hole.net)
set -e

readonly PIKONEK_FILES_DIR="/etc/pikonek"
readonly PIKONEK_SCRIPT_DIR="/etc/.pikonek"
SKIP_INSTALL="true"
source "${PIKONEK_SCRIPT_DIR}/install.sh"
# Set these values so the installer can still run in color
QST="[?]"

# User must be root to uninstall
str="Root user check"
if [[ ${EUID} -eq 0 ]]; then
    echo -e "  ${TICK} ${str}"
else
    # Check if sudo is actually installed
    # If it isn't, exit because the uninstall can not complete
    if [ -x "$(command -v sudo)" ]; then
        export SUDO="sudo"
    else
        echo -e "  ${CROSS} ${str}
            Script called with non-root privileges
            The PiKonek requires elevated privileges to uninstall"
        exit 1
    fi
fi

ARCH=$(dpkg --print-architecture)

if [ "$ARCH" = "arm64" ] ; then
    INSTALLER_DEPS=(build-essential python3-dev python3-venv python3-testresources libssl-dev ipcalc sqlite3 dnsmasq lighttpd libffi-dev lighttpd dnsmasq dnsmasq-utils vlan bridge-utils python3-pip python3-setuptools ipset ifupdown ntp wpasupplicant mosquitto)
else
    INSTALLER_DEPS=(build-essential gcc-multilib python3-dev python3-venv python3-testresources libssl-dev ipcalc sqlite3 dnsmasq lighttpd libffi-dev lighttpd dnsmasq dnsmasq-utils vlan bridge-utils python3-pip python3-setuptools ipset ifupdown ntp wpasupplicant mosquitto)
fi

DOCKER_DEPS=(docker-ce docker-ce-cli containerd.io docker-compose-plugin)

# Install packages used by the PiKonek
DEPS=("${INSTALLER_DEPS[@]}" "${DOCKER_DEPS[@]}")
PKG_MANAGER="apt-get"

# Compatibility
if [ -x "$(command -v apt-get)" ]; then
    # Debian Family
    PKG_REMOVE=("${PKG_MANAGER}" -y remove --purge)
    package_check() {
        dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -c "ok installed"
    }
elif [ -x "$(command -v rpm)" ]; then
    # Fedora Family
    PKG_REMOVE=("${PKG_MANAGER}" remove -y)
    package_check() {
        rpm -qa | grep "^$1-" > /dev/null
    }
else
    echo -e "  ${CROSS} OS distribution not supported"
    exit 1
fi

removeAndPurge() {
    # Purge dependencies
    echo ""
    # remove docker pihole
    docker compose -f /etc/pikonek/pihole/docker-compose.yaml rm pihole --stop --force || \
    true
    # uninstall pikonek dependencies
    "${PIKONEK_FILES_DIR}"/venv/bin/python3 -m pip uninstall -y -r "${PIKONEK_FILES_DIR}/requirements.txt" || \
    true

    for i in "${DEPS[@]}"; do
        if package_check "${i}" > /dev/null; then
            while true; do
                read -rp "  ${QST} Do you wish to remove ${i} from your system? [Y/N] " answer
                case ${answer} in
                    [Yy]* )
                        echo -ne "  ${INFO} Removing ${i}...";
                        ${SUDO} "${PKG_REMOVE[@]}" "${i}" &> /dev/null;
                        echo -e "${OVER}  ${INFO} Removed ${i}";
                        break;;
                    [Nn]* ) echo -e "  ${INFO} Skipped ${i}"; break;;
                esac
            done
        else
            echo -e "  ${INFO} Package ${i} not installed"
        fi
    done

    # Remove dnsmasq config files
    ${SUDO} rm -f /etc/dnsmasq.conf /etc/dnsmasq.conf.orig /etc/dnsmasq.d/*-pikonek*.conf &> /dev/null
    echo -e "  ${TICK} Removing dnsmasq config files"

    # Call removeNoPurge to remove PiKonek specific files
    removeNoPurge
}

removeNoPurge() {
    # Attempt to preserve backwards compatibility with older versions
    if [[ -f /etc/cron.d/pikonek ]];then
        ${SUDO} rm -f /etc/cron.d/pikonek &> /dev/null
        echo -e "  ${TICK} Removed /etc/cron.d/pikonek"
    fi

    if package_check lighttpd > /dev/null; then
        if [[ -f /etc/lighttpd/lighttpd.conf.orig ]]; then
            ${SUDO} mv /etc/lighttpd/lighttpd.conf.orig /etc/lighttpd/lighttpd.conf
        fi

        if [[ -f /etc/lighttpd/external.conf ]]; then
            ${SUDO} rm /etc/lighttpd/external.conf
        fi

        echo -e "  ${TICK} Removed lighttpd configs"
    fi

    ${SUDO} rm -f /etc/dnsmasq.d/01-pikonek.conf &> /dev/null
    ${SUDO} rm -f /etc/mosquitto/conf.d/01-mosquitto.conf &> /dev/null
    ${SUDO} rm -f /etc/mosquitto/passwd &> /dev/null
    ${SUDO} rm -rf /var/log/pikonek.log &> /dev/null
    ${SUDO} rm -rf /etc/pikonek &> /dev/null
    ${SUDO} rm -rf /etc/.pikonek &> /dev/null
    ${SUDO} rm -f /usr/local/bin/pikonek &> /dev/null
    ${SUDO} rm -f /etc/sudoers.d/pikonek &> /dev/null
    ${SUDO} rm -f /etc/init.d/S70piknkmain &> /dev/null
    ${SUDO} rm -f /etc/systemd/network/25* &> /dev/null
    ${SUDO} rm -f /etc/systemd/network/99* &> /dev/null
    ${SUDO} rm -f /etc/logrotate.d/pikonek &> /dev/null
    ${SUDO} rm -f /etc/wpa_supplicant/wpa_supplicant* &> /dev/null
    echo -e "  ${TICK} Removed config files"

    # Restore sysctl.config
    if [[ -e /etc/sysctl.conf.old ]]; then
        ${SUDO} cp -p /etc/sysctl.conf.old /etc/sysctl.conf
    else
        ${SUDO} rm -f /etc/sysctl.conf &> /dev/null
    fi

    # Restore Resolved
    if [[ -e /etc/systemd/resolved.conf.orig ]]; then
        ${SUDO} cp -p /etc/systemd/resolved.conf.orig /etc/systemd/resolved.conf
        systemctl reload-or-restart systemd-resolved
    fi

    if [[ -e /etc/resolv.conf.orig ]]; then
        ${SUDO} cp -p /etc/resolv.conf.orig /etc/resolv.conf
    fi

    # If the pikonek user exists, then remove
    if id "pikonek" &> /dev/null; then
        if ${SUDO} userdel -r pikonek 2> /dev/null; then
            echo -e "  ${TICK} Removed 'pikonek' user"
        else
            echo -e "  ${CROSS} Unable to remove 'pikonek' user"
        fi
    fi
    # If the pikonek group exists, then remove
    if getent group "pikonek" &> /dev/null; then
        if ${SUDO} groupdel pikonek 2> /dev/null; then
            echo -e "  ${TICK} Removed 'pikonek' group"
        else
            echo -e "  ${CROSS} Unable to remove 'pikonek' group"
        fi
    fi

    echo -e "\\n   We're sorry to see you go, but thanks for checking out PiKonek!
       Reinstall at any time: ${COL_LIGHT_RED}curl -sSL https://install.pikonek.com | bash.
       Please restart your machine.
      ${COL_LIGHT_GREEN}Uninstallation Complete!"
}

while true; do
    read -rp "  ${QST} Are you sure you would like to remove PiKonek? [y/N] " answer
    case ${answer} in
        [Yy]* ) removeAndPurge; break;;
        * ) echo -e "${OVER}  ${COL_LIGHT_GREEN}Uninstall has been canceled"; exit 0;;
    esac
done
