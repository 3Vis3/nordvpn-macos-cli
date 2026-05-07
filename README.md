# nordvpn-macos-cli

Command line control for NordVPN on macOS.

The tool downloads NordVPN OpenVPN configs, stores your NordVPN service password
in macOS Keychain, and rotates between servers from Terminal.

## Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [AI agent install notes](#ai-agent-install-notes)
- [NordVPN credentials](#nordvpn-credentials)
- [Setup](#setup)
- [Usage](#usage)
- [Unattended rotation](#unattended-rotation)
- [Commands](#commands)
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
- NordVPN manual service credentials.

OpenVPN is installed by Homebrew as a dependency of this package.

## Installation

```sh
brew tap 3Vis3/tap
brew install nordvpn-macos-cli
```

Check the install:

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

Purpose: install and use `nordvpn-macos`, a Swift CLI for rotating NordVPN
OpenVPN configs on macOS.

NordVPN manual service credentials and server recommendations are available at:

```text
https://my.nordaccount.com/dashboard/nordvpn/manual-configuration/server-recommendation/
```

Do not ask for the user's normal Nord Account password. Use the service
username and service password from the manual configuration page. The password
is stored in macOS Keychain by `setup-openvpn`.

Install:

```sh
brew tap 3Vis3/tap
brew install nordvpn-macos-cli
nordvpn-macos help
```

Safe validation commands:

```sh
nordvpn-macos ip
nordvpn-macos status-openvpn
```

Setup command:

```sh
nordvpn-macos setup-openvpn Indonesia --count 5 --username NORD_SERVICE_USERNAME
```

Rotation command:

```sh
nordvpn-macos rotate-openvpn Indonesia --ip
```

Notes:

- Tell the user VPN changes can interrupt active network connections.
- `setup-openvpn` asks for the NordVPN service password.
- `rotate-openvpn` does not need `--username`; it uses the username saved by setup.
- `rotate-openvpn` may ask for the macOS admin password because OpenVPN needs sudo.
- `install-sudoers` enables unattended rotation with a narrow sudoers rule.
- If `openvpn` is missing, run `brew install openvpn`.

</details>

## NordVPN credentials

Get the service username, service password, and server recommendations from:

```text
https://my.nordaccount.com/dashboard/nordvpn/manual-configuration/server-recommendation/
```

Use the service username and service password from that page. They are not
always the same as your normal Nord Account email and password.

## Setup

Set up five configs for a country:

```sh
nordvpn-macos setup-openvpn Indonesia \
  --count 5 \
  --username NORD_SERVICE_USERNAME
```

The command asks for the NordVPN service password and stores it in macOS
Keychain. It stores OpenVPN config files under:

```text
~/Library/Application Support/nordvpn-macos-cli/openvpn/
```

Use TCP instead of UDP:

```sh
nordvpn-macos setup-openvpn Indonesia \
  --count 5 \
  --username NORD_SERVICE_USERNAME \
  --tcp
```

## Usage

Rotate to a random configured server in a country:

```sh
nordvpn-macos rotate-openvpn Indonesia --ip
```

Preview rotation without changing VPN state:

```sh
nordvpn-macos rotate-openvpn Indonesia --dry-run
```

Check the managed OpenVPN process:

```sh
nordvpn-macos status-openvpn
```

Stop the managed OpenVPN process:

```sh
nordvpn-macos stop-openvpn
```

Print current public IP:

```sh
nordvpn-macos ip
```

`rotate-openvpn` uses `sudo` because OpenVPN needs privileges to create the VPN
tunnel interface and routes. If prompted, enter your macOS admin password, not
your NordVPN password.

## Unattended rotation

For scheduled rotation, enable the optional sudoers rule:

```sh
nordvpn-macos install-sudoers
```

This asks for macOS administrator approval once and installs:

```text
/etc/sudoers.d/nordvpn-macos-cli
```

The rule is limited to the Homebrew OpenVPN binary and `/bin/kill`. It does not
grant broad passwordless sudo access.

Preview the rule first:

```sh
nordvpn-macos install-sudoers --dry-run
```

Remove the rule:

```sh
nordvpn-macos uninstall-sudoers
```

Then use a scheduler such as `cron`, `launchd`, or your scraping script:

```sh
nordvpn-macos rotate-openvpn Indonesia --ip
```

Example cron entry for rotation every 10 minutes:

```cron
*/10 * * * * /opt/homebrew/bin/nordvpn-macos rotate-openvpn Indonesia >/tmp/nordvpn-macos-rotate.log 2>&1
```

Security note: passwordless sudo should be kept narrow. Do not grant broad
`NOPASSWD: ALL` access.

The generated sudoers rule looks like this on Apple Silicon Homebrew:

```text
%admin ALL=(root) NOPASSWD: /opt/homebrew/opt/openvpn/sbin/openvpn, /bin/kill
```

## Commands

```text
nordvpn-macos setup-openvpn <country> --username <name> [--count n] [--tcp] [--password-stdin]
nordvpn-macos rotate-openvpn <country> [--wait seconds] [--ip] [--dry-run]
nordvpn-macos status-openvpn
nordvpn-macos stop-openvpn
nordvpn-macos install-sudoers [--dry-run]
nordvpn-macos uninstall-sudoers
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
- OpenVPN mode requires `sudo` to start and stop the VPN tunnel.
- The tool only manages the OpenVPN process it starts.
- Reconnecting the same server may return the same public IP.

## Troubleshooting

### OpenVPN is missing

```sh
brew install openvpn
```

### No OpenVPN profiles found

Run setup first:

```sh
nordvpn-macos setup-openvpn Indonesia --count 5 --username NORD_SERVICE_USERNAME
```

### Rotate asks for a password

That is the macOS admin password for `sudo`, not your NordVPN password.
OpenVPN needs admin privileges to create the tunnel interface and routes.

### Public IP does not change

Set up more configs for the country and rotate again:

```sh
nordvpn-macos setup-openvpn Indonesia --count 10 --username NORD_SERVICE_USERNAME
nordvpn-macos rotate-openvpn Indonesia --ip
```

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
swift run nordvpn-macos status-openvpn
```

## Disclaimer

This project is unofficial and is not affiliated with, endorsed by, sponsored
by, or maintained by NordVPN. NordVPN is a trademark of its respective owner.

Use this software only with accounts, devices, and networks you are authorized
to use. VPN changes can interrupt active network connections.

## License

MIT. See [LICENSE](LICENSE).
