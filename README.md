# nordvpn-macos-cli

Command-line control for NordVPN manual VPN profiles on macOS.

This tool wraps `scutil --nc`, the VPN controller included with macOS. It does
not control the NordVPN app and it does not store VPN credentials.

## Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [AI agent install notes](#ai-agent-install-notes)
- [NordVPN profile setup](#nordvpn-profile-setup)
- [Automated profile generation](#automated-profile-generation)
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
- A NordVPN subscription.
- One or more NordVPN manual IKEv2/IPSec profiles configured in macOS.

Install Homebrew if needed:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

## Installation

Install with Homebrew:

```sh
brew tap 3Vis3/tap
brew install nordvpn-macos-cli
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

Purpose: install and use `nordvpn-macos`, a Swift CLI that controls existing
macOS VPN profiles via `scutil --nc`.

Do not ask for or store NordVPN credentials. This tool does not create NordVPN
accounts and does not log in to the NordVPN app.

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
nordvpn-macos help
```

Validate without changing VPN state:

```sh
nordvpn-macos list
nordvpn-macos ip
nordvpn-macos rotate-country Germany --dry-run
```

Before running connect, reconnect, disconnect, or rotate without `--dry-run`,
tell the user VPN state changes can interrupt active network connections.

Expected profile naming:

```text
NordVPN <Country> 1
NordVPN <Country> 2
NordVPN <Country> 3
```

Common commands:

```sh
nordvpn-macos generate-mobileconfig Indonesia --count 5 --username NORD_SERVICE_USERNAME --open
nordvpn-macos profiles Germany
nordvpn-macos connect-country Germany --ip
nordvpn-macos reconnect-country Germany --ip
nordvpn-macos rotate-country Germany --ip
nordvpn-macos disconnect "NordVPN Germany 1"
```

Failure handling:

- If `brew --version` fails, ask the user to install Homebrew.
- If country commands find no profiles, run `nordvpn-macos list` and check the
  macOS VPN profile names.
- If `scutil --nc list` does not show the profile, the user must create or fix
  the macOS VPN profile first.
- Do not use third-party scripts that require plaintext NordVPN credentials
  unless the user explicitly accepts that risk.
- If using `generate-mobileconfig`, tell the user the generated file contains
  the NordVPN service password and should be deleted after installation.

</details>

## NordVPN profile setup

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

## Automated profile generation

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
nordvpn-macos ip
```

## Shell aliases

Add aliases to `~/.zshrc`:

```sh
alias vpn-de='nordvpn-macos connect-country Germany --ip'
alias vpn-de-reconnect='nordvpn-macos reconnect-country Germany --ip'
alias vpn-de-rotate='nordvpn-macos rotate-country Germany --ip'
alias vpn-de-off='nordvpn-macos disconnect "NordVPN Germany 1"'
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
- Profiles must be created in macOS before this tool can control them.
- Reconnecting the same profile may return the same public IP.
- `scutil --nc` must be able to see the VPN profile.
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
