import Foundation

struct CommandResult {
    let status: Int32
    let output: String
}

enum CLIError: Error, CustomStringConvertible {
    case missingArgument(String)
    case invalidArgument(String)
    case commandFailed(String)

    var description: String {
        switch self {
        case .missingArgument(let message):
            return message
        case .invalidArgument(let message):
            return message
        case .commandFailed(let message):
            return message
        }
    }
}

let executableName = URL(fileURLWithPath: CommandLine.arguments.first ?? "nordvpn-macos")
    .lastPathComponent

func printUsage() {
    print("""
    NordVPN macOS CLI

    A small wrapper around macOS' built-in VPN controller (`scutil --nc`).
    It works with NordVPN manual IKEv2/IPSec profiles created in System Settings.

    Usage:
      \(executableName) list
      \(executableName) profiles <country>
      \(executableName) status <vpn-name>
      \(executableName) connect <vpn-name> [--ip]
      \(executableName) connect-country <country> [--ip]
      \(executableName) disconnect <vpn-name>
      \(executableName) reconnect <vpn-name> [--wait seconds] [--ip]
      \(executableName) reconnect-country <country> [--wait seconds] [--ip]
      \(executableName) rotate <vpn-name-1> <vpn-name-2> ... [--wait seconds] [--ip] [--dry-run]
      \(executableName) rotate-country <country> [--wait seconds] [--ip] [--dry-run]
      \(executableName) ip

    Examples:
      \(executableName) list
      \(executableName) connect "NordVPN Germany"
      \(executableName) connect-country Germany --ip
      \(executableName) reconnect-country "United States" --ip
      \(executableName) rotate-country Germany --ip
      \(executableName) rotate-country Germany --dry-run
      \(executableName) rotate "NordVPN Germany 1" "NordVPN Germany 2" --ip

    Notes:
      - This tool does not log in to the NordVPN macOS app.
      - Create one or more NordVPN IKEv2 profiles in macOS System Settings first.
      - For country commands, name profiles like "NordVPN <Country>" or "NordVPN <Country> 1".
      - Changing VPN state can interrupt active network connections.
    """)
}

func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
    let process = Process()
    let pipe = Pipe()

    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
    } catch {
        throw CLIError.commandFailed("Failed to run \(executable): \(error.localizedDescription)")
    }

    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""

    return CommandResult(status: process.terminationStatus, output: output)
}

func runScutil(_ arguments: [String], allowFailure: Bool = false) throws -> CommandResult {
    let result = try run("/usr/sbin/scutil", ["--nc"] + arguments)
    if result.status != 0 && !allowFailure {
        throw CLIError.commandFailed(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return result
}

func publicIP() throws -> String {
    let result = try run("/usr/bin/curl", ["-fsSL", "https://api.ipify.org"])
    if result.status != 0 {
        throw CLIError.commandFailed("Unable to fetch public IP: \(result.output)")
    }
    return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
}

func requireVPNName(_ args: [String]) throws -> String {
    guard let name = args.first, !name.hasPrefix("--") else {
        throw CLIError.missingArgument("Missing VPN profile name.")
    }
    return name
}

func requireCountry(_ args: [String]) throws -> String {
    let countryParts = try positionalArguments(args)
    guard !countryParts.isEmpty else {
        throw CLIError.missingArgument("Missing country name.")
    }
    return countryParts.joined(separator: " ")
}

func parseWait(_ args: [String], defaultWait: UInt32 = 5) throws -> UInt32 {
    guard let waitIndex = args.firstIndex(of: "--wait") else {
        return defaultWait
    }

    let valueIndex = args.index(after: waitIndex)
    guard valueIndex < args.endIndex else {
        throw CLIError.missingArgument("Missing value after --wait.")
    }

    guard let seconds = UInt32(args[valueIndex]), seconds <= 120 else {
        throw CLIError.invalidArgument("--wait must be a number between 0 and 120.")
    }

    return seconds
}

func shouldPrintIP(_ args: [String]) -> Bool {
    args.contains("--ip")
}

func shouldDryRun(_ args: [String]) -> Bool {
    args.contains("--dry-run")
}

func positionalArguments(_ args: [String]) throws -> [String] {
    var values: [String] = []
    var index = args.startIndex

    while index < args.endIndex {
        let value = args[index]
        if value == "--ip" {
            index = args.index(after: index)
            continue
        }

        if value == "--dry-run" {
            index = args.index(after: index)
            continue
        }

        if value == "--wait" {
            let nextIndex = args.index(after: index)
            guard nextIndex < args.endIndex else {
                throw CLIError.missingArgument("Missing value after --wait.")
            }
            index = args.index(after: nextIndex)
            continue
        }

        if value.hasPrefix("--") {
            throw CLIError.invalidArgument("Unknown option: \(value)")
        }

        values.append(value)
        index = args.index(after: index)
    }

    return values
}

func printCommandOutput(_ result: CommandResult) {
    let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    if !output.isEmpty {
        print(output)
    }
}

func printPublicIPIfRequested(_ requested: Bool) throws {
    guard requested else { return }
    print("Public IP: \(try publicIP())")
}

func listVPNs() throws {
    printCommandOutput(try runScutil(["list"]))
}

func listProfiles(country: String) throws {
    let matches = try profilesMatching(country: country)
    print("Found \(matches.count) profile(s) for \(country):")
    for match in matches {
        print("- \(match)")
    }
}

func availableVPNNames() throws -> [String] {
    let result = try runScutil(["list"])

    return result.output
        .split(separator: "\n")
        .compactMap { line in
            guard let firstQuote = line.firstIndex(of: "\"") else {
                return nil
            }
            let afterFirstQuote = line.index(after: firstQuote)
            guard let lastQuote = line[afterFirstQuote...].lastIndex(of: "\"") else {
                return nil
            }
            let name = String(line[afterFirstQuote..<lastQuote])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        }
}

func profilesMatching(country: String) throws -> [String] {
    let normalizedCountry = country.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedCountry.isEmpty else {
        throw CLIError.missingArgument("Missing country name.")
    }

    let names = try availableVPNNames()
    let matches = names.filter { name in
        name.range(of: normalizedCountry, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    if matches.isEmpty {
        throw CLIError.invalidArgument("""
        No VPN profiles found for country: \(normalizedCountry)

        Create one or more macOS IKEv2 profiles with names that include the country, for example:
          NordVPN \(normalizedCountry)
          NordVPN \(normalizedCountry) 1
          NordVPN \(normalizedCountry) 2

        Then verify with:
          \(executableName) list
        """)
    }

    return matches.sorted()
}

func status(_ vpnName: String) throws {
    printCommandOutput(try runScutil(["status", vpnName], allowFailure: true))
}

func connect(_ vpnName: String, printIP: Bool) throws {
    print("Connecting: \(vpnName)")
    printCommandOutput(try runScutil(["start", vpnName]))
    printCommandOutput(try runScutil(["status", vpnName], allowFailure: true))
    try printPublicIPIfRequested(printIP)
}

func disconnect(_ vpnName: String) throws {
    print("Disconnecting: \(vpnName)")
    printCommandOutput(try runScutil(["stop", vpnName], allowFailure: true))
}

func reconnect(_ vpnName: String, waitSeconds: UInt32, printIP: Bool) throws {
    print("Disconnecting: \(vpnName)")
    _ = try runScutil(["stop", vpnName], allowFailure: true)

    if waitSeconds > 0 {
        print("Waiting \(waitSeconds)s...")
        sleep(waitSeconds)
    }

    print("Connecting: \(vpnName)")
    printCommandOutput(try runScutil(["start", vpnName]))

    if waitSeconds > 0 {
        print("Waiting \(waitSeconds)s for connection to settle...")
        sleep(waitSeconds)
    }

    printCommandOutput(try runScutil(["status", vpnName], allowFailure: true))
    try printPublicIPIfRequested(printIP)
}

func rotate(_ vpnNames: [String], waitSeconds: UInt32, printIP: Bool, dryRun: Bool) throws {
    guard !vpnNames.isEmpty else {
        throw CLIError.missingArgument("Provide at least one VPN profile name to rotate.")
    }

    let selected = vpnNames.randomElement() ?? vpnNames[0]

    if dryRun {
        print("Dry run: would disconnect \(vpnNames.count) candidate profile(s).")
        for vpnName in vpnNames {
            print("- \(vpnName)")
        }
        print("Dry run: would connect: \(selected)")
        return
    }

    print("Disconnecting candidate VPN profiles...")
    for vpnName in vpnNames {
        _ = try runScutil(["stop", vpnName], allowFailure: true)
    }

    if waitSeconds > 0 {
        print("Waiting \(waitSeconds)s...")
        sleep(waitSeconds)
    }

    print("Connecting: \(selected)")
    printCommandOutput(try runScutil(["start", selected]))

    if waitSeconds > 0 {
        print("Waiting \(waitSeconds)s for connection to settle...")
        sleep(waitSeconds)
    }

    printCommandOutput(try runScutil(["status", selected], allowFailure: true))
    try printPublicIPIfRequested(printIP)
}

func connectCountry(_ country: String, printIP: Bool) throws {
    let matches = try profilesMatching(country: country)
    let selected = matches[0]

    if matches.count > 1 {
        print("Found \(matches.count) profiles for \(country). Connecting first match: \(selected)")
        print("Use rotate-country \"\(country)\" to randomly choose one.")
    }

    try connect(selected, printIP: printIP)
}

func reconnectCountry(_ country: String, waitSeconds: UInt32, printIP: Bool) throws {
    let matches = try profilesMatching(country: country)
    let selected = matches[0]

    if matches.count > 1 {
        print("Found \(matches.count) profiles for \(country). Reconnecting first match: \(selected)")
        print("Use rotate-country \"\(country)\" to randomly choose one.")
    }

    try reconnect(selected, waitSeconds: waitSeconds, printIP: printIP)
}

func rotateCountry(_ country: String, waitSeconds: UInt32, printIP: Bool, dryRun: Bool) throws {
    let matches = try profilesMatching(country: country)
    print("Found \(matches.count) profile(s) for \(country):")
    for match in matches {
        print("- \(match)")
    }
    try rotate(matches, waitSeconds: waitSeconds, printIP: printIP, dryRun: dryRun)
}

func main() throws {
    var args = Array(CommandLine.arguments.dropFirst())

    guard let command = args.first else {
        printUsage()
        return
    }

    args.removeFirst()

    switch command {
    case "help", "--help", "-h":
        printUsage()
    case "list":
        try listVPNs()
    case "profiles":
        try listProfiles(country: try requireCountry(args))
    case "status":
        try status(try requireVPNName(args))
    case "connect":
        try connect(try requireVPNName(args), printIP: shouldPrintIP(args))
    case "connect-country":
        try connectCountry(try requireCountry(args), printIP: shouldPrintIP(args))
    case "disconnect", "stop":
        try disconnect(try requireVPNName(args))
    case "reconnect":
        try reconnect(
            try requireVPNName(args),
            waitSeconds: try parseWait(args),
            printIP: shouldPrintIP(args)
        )
    case "reconnect-country":
        try reconnectCountry(
            try requireCountry(args),
            waitSeconds: try parseWait(args),
            printIP: shouldPrintIP(args)
        )
    case "rotate":
        try rotate(
            try positionalArguments(args),
            waitSeconds: try parseWait(args),
            printIP: shouldPrintIP(args),
            dryRun: shouldDryRun(args)
        )
    case "rotate-country":
        try rotateCountry(
            try requireCountry(args),
            waitSeconds: try parseWait(args),
            printIP: shouldPrintIP(args),
            dryRun: shouldDryRun(args)
        )
    case "ip":
        print(try publicIP())
    default:
        throw CLIError.invalidArgument("Unknown command: \(command)")
    }
}

do {
    try main()
} catch let error as CLIError {
    fputs("Error: \(error.description)\n\n", stderr)
    printUsage()
    exit(1)
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
