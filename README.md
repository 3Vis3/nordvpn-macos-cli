# nordvpn-macos-cli

Rotate your public IP on macOS using your NordVPN subscription from the command line.

Built for AI agents, scrapers, and automation tools that need to change IPs
programmatically without manual interaction.

## Quick start

```sh
brew tap 3Vis3/tap
brew install nordvpn-macos-cli
```

Get your NordVPN service credentials from:

```text
https://my.nordaccount.com/dashboard/nordvpn/manual-configuration/server-recommendation/
```

Set up 5 servers for a country:

```sh
nordvpn-macos setup-openvpn Indonesia --count 5 --username YOUR_SERVICE_USERNAME
```

Enable passwordless rotation (asks for macOS password once):

```sh
nordvpn-macos install-sudoers
```

Rotate IP:

```sh
nordvpn-macos rotate-openvpn Indonesia --ip
```

That's it. No more password prompts. Your scripts and agents can now call
`rotate-openvpn` whenever they need a new IP.

<details>
<summary>AI agent install notes</summary>

Credentials page:

```text
https://my.nordaccount.com/dashboard/nordvpn/manual-configuration/server-recommendation/
```

Use the service username and service password from that page, not the normal
Nord Account login.

Install:

```sh
brew tap 3Vis3/tap
brew install nordvpn-macos-cli
```

One-time setup:

```sh
nordvpn-macos setup-openvpn Indonesia --count 5 --username NORD_SERVICE_USERNAME
nordvpn-macos install-sudoers
```

After setup, rotate without prompts:

```sh
nordvpn-macos rotate-openvpn Indonesia --ip
```

Other commands:

```sh
nordvpn-macos status-openvpn
nordvpn-macos stop-openvpn
nordvpn-macos ip
```

</details>

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

## How it works

1. `setup-openvpn` fetches NordVPN OpenVPN configs and stores your service
   password in macOS Keychain.
2. `install-sudoers` writes a narrow rule to `/etc/sudoers.d/nordvpn-macos-cli`
   so OpenVPN can start without repeated password prompts. Only the Homebrew
   OpenVPN binary and `/bin/kill` are allowed.
3. `rotate-openvpn` stops the current tunnel, picks a random server config, and
   starts a new connection. Returns the new public IP if `--ip` is passed.

## Automation examples

From a Python scraper:

```python
import subprocess
subprocess.run(["nordvpn-macos", "rotate-openvpn", "Indonesia", "--ip"])
```

Every 10 minutes with cron:

```cron
*/10 * * * * /opt/homebrew/bin/nordvpn-macos rotate-openvpn Indonesia >/tmp/nordvpn-rotate.log 2>&1
```

Shell alias:

```sh
alias vpn-rotate='nordvpn-macos rotate-openvpn Indonesia --ip'
```

## Troubleshooting

**Rotate asks for a password** -- Run `nordvpn-macos install-sudoers` to enable
unattended mode.

**Public IP does not change** -- Add more server configs:
`nordvpn-macos setup-openvpn Indonesia --count 10 --username YOUR_SERVICE_USERNAME`

**OpenVPN is missing** -- `brew install openvpn`

## Development

```sh
swift build
swift build -c release
swift run nordvpn-macos help
```

## Disclaimer

Unofficial. Not affiliated with NordVPN. Use only with accounts and services you
are authorized to access.

## License

MIT
