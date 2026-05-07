# nordvpn-macos-cli

Command-line control for NordVPN on macOS.

The reliable CLI path uses OpenVPN configs and macOS Keychain. Legacy helpers
for macOS VPN profiles are still available, but IKEv2 profiles are not
consistently controllable from Terminal on macOS.

## Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [AI agent install notes](#ai-agent-install-notes)
- [OpenVPN setup](#openvpn-setup)
- [IKEv2 profile helpers](#ikev2-profile-helpers)
- [Usage](#usage)
- [Shell aliases](#shell-aliases)
- [Homebrew](#homebrew)
- [Limitations](#limitations)
- [Troubleshooting](#troubleshooting)
- [Development](#development)
- [Disclaimer](#disclaimer)
- [License](#license)

## Requirements

- macOS 13 or newer.
- Homebrew.
- OpenVPN, installed with Homebrew.
- A NordVPN subscription.
- NordVPN manual service credentials.

Install Homebrew if needed:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

## Installation

Install with Homebrew:

```sh
brew tap 3Vis3/tap
brew install nordvpn-macos-cli
brew install openvpn
```

Check the installation:

```sh
nordvpn-macos help
```

Upgrade:

```sh
brew update
brew upgrade nordvpn-macos-cli
```

<details id="ai-agent-install-notes">
<summary>AI agent install notes</summary>

Purpose: install and use `nordvpn-macos`, a Swift CLI that rotates NordVPN
OpenVPN configs on macOS.

This tool does not create NordVPN accounts and does not log in to the NordVPN
app. For OpenVPN mode, it stores the NordVPN service password in macOS Keychain.

Prerequisites to verify:

```sh
sw_vers -productVersion
brew --version
scutil --nc list
```

Install with Homebrew:

```sh
brew tap 3Vis3/tap
brew install nordvpn-macos-cli
brew install openvpn
nordvpn-macos help
```

Validate without changing VPN state:

```sh
nordvpn-macos list
nordvpn-macos ip
nordvpn-macos rotate-openvpn Germany --dry-run
```

Before running connect, reconnect, disconnect, or rotate commands without
`--dry-run`, tell the user VPN state changes can interrupt active network
connections.

Common commands:

```sh
nordvpn-macos setup-openvpn Indonesia --count 5 --username NORD_SERVICE_USERNAME
nordvpn-macos rotate-openvpn Indonesia --ip
nordvpn-macos status-openvpn
nordvpn-macos stop-openvpn
```

Failure handling:

- If `brew --version` fails, ask the user to install Homebrew.
- If `openvpn` is missing, run `brew install openvpn`.
- If OpenVPN setup has not run, run `setup-openvpn` before `rotate-openvpn`.
- Do not use third-party scripts that require plaintext NordVPN credentials
  unless the user explicitly accepts that risk.
- If using `generate-mobileconfig`, tell the user the generated file contains
  the NordVPN service password and should be deleted after installation.

</details>

## OpenVPN setup

OpenVPN mode is the recommended mode for CLI rotation on macOS.

Get NordVPN service credentials from:

```text
NordVPN -> Set up NordVPN manually -> Service credentials
```

Set up five Indonesia configs:

```sh
nordvpn-macos setup-openvpn Indonesia \
  --count 5 \
  --username NORD_SERVICE_USERNAME
```

The command prompts for the NordVPN service password without echoing it and
stores it in macOS Keychain. OpenVPN config files are stored under:

```text
~/Library/Application Support/nordvpn-macos-cli/openvpn/
```

Rotate IP:

```sh
nordvpn-macos rotate-openvpn Indonesia --ip
```

Check status:

```sh
nordvpn-macos status-openvpn
```

Stop the managed OpenVPN process:

```sh
nordvpn-macos stop-openvpn
```

Use TCP instead of UDP during setup:

```sh
nordvpn-macos setup-openvpn Indonesia \
  --count 5 \
  --username NORD_SERVICE_USERNAME \
  --tcp
```

`rotate-openvpn` uses `sudo` because OpenVPN needs privileges to create the VPN
tunnel interface and routes.

## IKEv2 profile helpers

The standard NordVPN macOS app does not provide the Linux `nordvpn` CLI. To use
this tool, create one or more manual IKEv2/IPSec profiles in macOS System
Settings.

### Service credentials

In Nord Account, open:

```text
NordVPN -> Set up NordVPN manually -> Service credentials
```

Copy the service username and service password. Use these credentials for the
manual VPN profile.

### Server hostname

In Nord Account, open:

```text
NordVPN -> Set up NordVPN manually -> Server recommendation
```

Choose `IKEv2/IPSec` and the country you want. Copy the recommended hostname,
for example:

```text
de123.nordvpn.com
```

### macOS VPN profile

Open:

```text
System Settings -> VPN -> Add VPN Configuration -> IKEv2
```

Example profile:

```text
Display name: NordVPN Germany 1
Server address: de123.nordvpn.com
Remote ID: de123.nordvpn.com
Local ID: leave blank
Username: NordVPN service username
Password: NordVPN service password
```

For rotation, create several profiles for the same country with different
server hostnames:

```text
NordVPN Germany 1
NordVPN Germany 2
NordVPN Germany 3
```

Country commands match the country text in the profile name.

### Automated profile generation

`generate-mobileconfig` creates an installable macOS configuration profile for
multiple NordVPN IKEv2 servers in a country. It fetches recommended IKEv2
servers from NordVPN, writes one VPN profile per server, and sets the profile
authentication to username/password.

Example for five Indonesia profiles:

```sh
nordvpn-macos generate-mobileconfig Indonesia \
  --count 5 \
  --username NORD_SERVICE_USERNAME \
  --open
```

The command prompts for the NordVPN service password without echoing it. The
service username and password come from:

```text
NordVPN -> Set up NordVPN manually -> Service credentials
```

The generated profiles are named:

```text
NordVPN Indonesia 1
NordVPN Indonesia 2
NordVPN Indonesia 3
NordVPN Indonesia 4
NordVPN Indonesia 5
```

The generated `.mobileconfig` contains the service password so macOS can import
the profiles with username/password authentication instead of defaulting to
certificate authentication. Delete the file after installation.

To choose an output path:

```sh
nordvpn-macos generate-mobileconfig Indonesia \
  --count 5 \
  --username NORD_SERVICE_USERNAME \
  --output ~/Desktop/nordvpn-indonesia.mobileconfig
```

For non-interactive scripts, pass the password on stdin:

```sh
printf '%s\n' "$NORDVPN_SERVICE_PASSWORD" | \
  nordvpn-macos generate-mobileconfig Indonesia \
    --count 5 \
    --username "$NORDVPN_SERVICE_USERNAME" \
    --password-stdin
```

After installing the profile in System Settings, verify:

```sh
nordvpn-macos profiles Indonesia
nordvpn-macos rotate-country Indonesia --dry-run
```

## Usage

Recommended OpenVPN rotation:

```sh
nordvpn-macos setup-openvpn Indonesia --count 5 --username NORD_SERVICE_USERNAME
nordvpn-macos rotate-openvpn Indonesia --ip
nordvpn-macos status-openvpn
nordvpn-macos stop-openvpn
```

Legacy IKEv2/scutil commands:

List configured VPN services:

```sh
nordvpn-macos list
```

List profiles matching a country:

```sh
nordvpn-macos profiles Germany
nordvpn-macos profiles "United States"
```

Connect by profile name:

```sh
nordvpn-macos connect "NordVPN Germany 1"
```

Connect by country:

```sh
nordvpn-macos connect-country Germany
```

Reconnect a profile:

```sh
nordvpn-macos reconnect "NordVPN Germany 1"
```

Reconnect by country:

```sh
nordvpn-macos reconnect-country Germany
```

Rotate across explicit profiles:

```sh
nordvpn-macos rotate \
  "NordVPN Germany 1" \
  "NordVPN Germany 2" \
  "NordVPN Germany 3"
```

Rotate by country:

```sh
nordvpn-macos rotate-country Germany
```

Preview a rotation without changing VPN state:

```sh
nordvpn-macos rotate-country Germany --dry-run
```

Print the public IP after connecting:

```sh
nordvpn-macos connect-country Germany --ip
nordvpn-macos rotate-country Germany --ip
```

Change wait time for reconnect/rotate commands:

```sh
nordvpn-macos reconnect-country Germany --wait 10 --ip
```

Show status:

```sh
nordvpn-macos status "NordVPN Germany 1"
```

Disconnect:

```sh
nordvpn-macos disconnect "NordVPN Germany 1"
```

Print current public IP:

```sh
nordvpn-macos ip
```

## Commands

```text
nordvpn-macos list
nordvpn-macos profiles <country>
nordvpn-macos status <vpn-name>
nordvpn-macos connect <vpn-name> [--ip]
nordvpn-macos connect-country <country> [--ip]
nordvpn-macos disconnect <vpn-name>
nordvpn-macos reconnect <vpn-name> [--wait seconds] [--ip]
nordvpn-macos reconnect-country <country> [--wait seconds] [--ip]
nordvpn-macos rotate <vpn-name-1> <vpn-name-2> ... [--wait seconds] [--ip] [--dry-run]
nordvpn-macos rotate-country <country> [--wait seconds] [--ip] [--dry-run]
nordvpn-macos generate-mobileconfig <country> --username <name> [--count n] [--output path] [--open] [--password-stdin]
nordvpn-macos setup-openvpn <country> --username <name> [--count n] [--tcp] [--password-stdin]
nordvpn-macos rotate-openvpn <country> [--wait seconds] [--ip] [--dry-run]
nordvpn-macos status-openvpn
nordvpn-macos stop-openvpn
nordvpn-macos ip
```

## Shell aliases

Add aliases to `~/.zshrc`:

```sh
alias vpn-id='nordvpn-macos rotate-openvpn Indonesia --ip'
alias vpn-status='nordvpn-macos status-openvpn'
alias vpn-off='nordvpn-macos stop-openvpn'
```

Reload the shell:

```sh
source ~/.zshrc
```

## Homebrew

Formula: `3Vis3/tap/nordvpn-macos-cli`

```sh
brew tap 3Vis3/tap
brew install nordvpn-macos-cli
```

## Limitations

- This is not the official NordVPN CLI.
- The NordVPN macOS app login is not used by this tool.
- OpenVPN mode requires `sudo` to start/stop the VPN tunnel.
- OpenVPN mode manages only the process it starts.
- IKEv2/scutil mode depends on macOS exposing the VPN profile to `scutil --nc`.
- Reconnecting the same server may return the same public IP.
- Generated `.mobileconfig` files can contain the NordVPN service password.

## Troubleshooting

Check that macOS can see the profile:

```sh
scutil --nc list
```

Check profile status directly:

```sh
scutil --nc status "NordVPN Germany 1"
```

If a country command finds no profiles, check the profile names:

```sh
nordvpn-macos list
nordvpn-macos profiles Germany
```

Country commands require the country name to appear in the profile name.

If the public IP does not change, create more profiles for the same country
using different NordVPN server hostnames and use `rotate-country`.

## Development

Build:

```sh
swift build
```

Build release:

```sh
swift build -c release
```

Run from source:

```sh
swift run nordvpn-macos help
swift run nordvpn-macos list
```

## Disclaimer

This project is unofficial and is not affiliated with, endorsed by, sponsored
by, or maintained by NordVPN. NordVPN is a trademark of its respective owner.

Use this software only with accounts, devices, and networks you are authorized
to use. VPN changes can interrupt active network connections.

## License

MIT. See [LICENSE](LICENSE).
