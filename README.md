# PiKonek + Pihole
![pikonek logo](logo.png)
# Introduction
## About PiKonek
The PiKonek software is a simple wifi hotspot management system. It has an easy-to-use web interface, wherein you can manage bandwidth, users, and rates. PiKonek can be used also as your network-wide ad-blocking solution with Pihole in its arsenal. See [Pihole](https://pi-hole.net/) for more information.
​
## Features
- Remote Management - You can monitor users and configure your system remotely via the internet.

- Bandwidth Limiter - Set bandwidth limit for the user.

- Multi-LAN Support - The software can be configured with multiple LANs. Each can have a separate DHCP, captive portal, bandwidth limit, and authentication.

- Captive Portal Support - Configurable captive portal.

- Voucher Support - You can use vouchers to authenticate users to the internet.

- Coin Slot Support - Connect to the internet by inserting a coin.

- VLAN Support

- Content Filtering

- Walled Garden

## Network-wide Ad Blocking Solution
Pikonek uses Pihole as your blocking solution.

## Command Line Interface
The pikonek command has all the functionality necessary to fully administer the PiKonek such as adding network interfaces and connecting clients.

# Prerequisites

## Hardware
### Minimum Hardware Requirements
The minimum hardware requirements for PiKonek are:

- x86-64 compatible CPU

- 1GB or more RAM

- 16GB or larger disk drive(SSD, HDD, etc)

- Two or more network interface cards

PiKonek also supports ARM-based hardware.

Here are currently supported ARM:

- Raspberry Pi 4

- Raspberry Pi 3B+

## Network Adapters
A wide variety of wired Ethernet Network Interface Cards (NICs) are supported by Ubuntu and are thus compatible with PiKonek software. You must have at least two network adapters on your hardware.
​
## Supported Operating Systems
PiKonek currently supports only Ubuntu 18.04 operating system for both x86-64 and ARM hardware.

# Install
Follow these steps to install PiKonek software.

>Note: The machine must meet the requirements under the  section Prerequisites, install the supported operating system and support two or more network interfaces.

## Installing PiKonek
After installing Ubuntu 18.04, follow these steps to install PiKonek software.

>Note: To continue installing PiKonek, you must have the credentials needed to install the application. To acquire the credentials please see [Pricing](https://pikonek.gitbook.io/pikonek/pricing).

## One Step Automated Install

`curl -sSL https://install.pikonek.com | sudo bash`

Run the installer. You must be a sudo to run the command.

`sudo bash pikonek-install.sh`

Once the installer has been run, reboot your system.

To access the web interface, open your browser and type http://pi.konek.

To access the admin web interface, open your browser and type http://pi.konek:5000/#/admin

>Note: You must be connected to the same LAN interface to access the web GUI page.

## Documentation
For more info see our [Full Documentation](https://pikonek.gitbook.io/pikonek).

## Contact Us
For inquiries and suggestions, you can contact us through our email at dev.pisokonek@gmail.com.
