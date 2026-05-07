import Darwin
import Foundation

struct CommandResult {
    let status: Int32
    let output: String
}

struct OpenVPNProfile: Codable {
    let name: String
    let country: String
    let hostname: String
    let configPath: String
    let username: String
    let remoteIP: String?
    let load: Int
}

struct OpenVPNState: Codable {
    let pid: Int32
    let profileName: String
    let country: String
    let hostname: String
    let startedAt: String
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
      \(executableName) generate-mobileconfig <country> --username <name> [--count n] [--output path] [--open] [--password-stdin]
      \(executableName) setup-openvpn <country> --username <name> [--count n] [--tcp] [--password-stdin]
      \(executableName) rotate-openvpn <country> [--wait seconds] [--ip] [--dry-run]
      \(executableName) status-openvpn
      \(executableName) stop-openvpn
      \(executableName) ip

    Examples:
      \(executableName) list
      \(executableName) connect "NordVPN Germany"
      \(executableName) connect-country Germany --ip
      \(executableName) reconnect-country "United States" --ip
      \(executableName) rotate-country Germany --ip
      \(executableName) rotate-country Germany --dry-run
      \(executableName) generate-mobileconfig Indonesia --count 5 --username your-service-user --open
      \(executableName) setup-openvpn Indonesia --count 5 --username your-service-user
      \(executableName) rotate-openvpn Indonesia --ip
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

func optionValue(_ args: [String], option: String) throws -> String? {
    guard let optionIndex = args.firstIndex(of: option) else {
        return nil
    }

    let valueIndex = args.index(after: optionIndex)
    guard valueIndex < args.endIndex else {
        throw CLIError.missingArgument("Missing value after \(option).")
    }

    let value = args[valueIndex]
    guard !value.hasPrefix("--") else {
        throw CLIError.missingArgument("Missing value after \(option).")
    }

    return value
}

func parseCount(_ args: [String], defaultCount: Int = 5) throws -> Int {
    guard let value = try optionValue(args, option: "--count") else {
        return defaultCount
    }

    guard let count = Int(value), (1...20).contains(count) else {
        throw CLIError.invalidArgument("--count must be a number between 1 and 20.")
    }

    return count
}

func shouldPrintIP(_ args: [String]) -> Bool {
    args.contains("--ip")
}

func shouldDryRun(_ args: [String]) -> Bool {
    args.contains("--dry-run")
}

func shouldOpen(_ args: [String]) -> Bool {
    args.contains("--open")
}

func shouldReadPasswordFromStdin(_ args: [String]) -> Bool {
    args.contains("--password-stdin")
}

func shouldUseTCP(_ args: [String]) -> Bool {
    args.contains("--tcp")
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

        if value == "--open" || value == "--password-stdin" || value == "--tcp" {
            index = args.index(after: index)
            continue
        }

        if ["--wait", "--count", "--username", "--output"].contains(value) {
            let nextIndex = args.index(after: index)
            guard nextIndex < args.endIndex else {
                throw CLIError.missingArgument("Missing value after \(value).")
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

struct NordVPNServer {
    let name: String
    let hostname: String
    let load: Int
}

let nordVPNCountryIDs: [String: Int] = [
    "albania": 2, "algeria": 3, "andorra": 5, "argentina": 10, "armenia": 11,
    "australia": 13, "austria": 14, "azerbaijan": 15, "bahamas": 16, "bangladesh": 18,
    "belgium": 21, "belize": 22, "bermuda": 24, "bhutan": 25, "bolivia": 26,
    "bosnia and herzegovina": 27, "brazil": 30, "brunei": 32, "bulgaria": 33,
    "cambodia": 36, "canada": 38, "cayman islands": 40, "chile": 43, "colombia": 47,
    "costa rica": 52, "croatia": 54, "cyprus": 56, "czech republic": 57,
    "denmark": 58, "dominican republic": 61, "ecuador": 63, "egypt": 64,
    "el salvador": 65, "estonia": 68, "finland": 73, "france": 74, "georgia": 80,
    "germany": 81, "ghana": 82, "greece": 84, "greenland": 85, "guam": 88,
    "guatemala": 89, "honduras": 96, "hong kong": 97, "hungary": 98, "iceland": 99,
    "india": 100, "indonesia": 101, "ireland": 104, "israel": 105, "italy": 106,
    "jamaica": 107, "japan": 108, "kazakhstan": 110, "kenya": 111, "laos": 118,
    "latvia": 119, "lebanon": 120, "liechtenstein": 124, "lithuania": 125,
    "luxembourg": 126, "malaysia": 131, "malta": 134, "mexico": 140, "moldova": 142,
    "monaco": 143, "mongolia": 144, "montenegro": 146, "morocco": 147,
    "myanmar": 149, "nepal": 152, "netherlands": 153, "new zealand": 156,
    "nigeria": 159, "north macedonia": 128, "norway": 163, "pakistan": 165,
    "panama": 168, "papua new guinea": 169, "paraguay": 170, "peru": 171,
    "philippines": 172, "poland": 174, "portugal": 175, "puerto rico": 176,
    "romania": 179, "serbia": 192, "singapore": 195, "slovakia": 196,
    "slovenia": 197, "south africa": 200, "south korea": 114, "spain": 202,
    "sri lanka": 203, "sweden": 208, "switzerland": 209, "thailand": 214,
    "trinidad and tobago": 218, "turkey": 220, "ukraine": 225,
    "united arab emirates": 226, "united kingdom": 227, "united states": 228,
    "uruguay": 230, "uzbekistan": 231, "venezuela": 233, "vietnam": 234,
]

func normalizedCountryKey(_ country: String) -> String {
    country
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "_", with: " ")
}

func slug(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
    return value
        .lowercased()
        .replacingOccurrences(of: " ", with: "-")
        .unicodeScalars
        .map { allowed.contains($0) ? String($0) : "-" }
        .joined()
        .replacingOccurrences(of: "--", with: "-")
}

func appSupportDirectory() throws -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let directory = base.appendingPathComponent("nordvpn-macos-cli", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

func openVPNDirectory() throws -> URL {
    let directory = try appSupportDirectory().appendingPathComponent("openvpn", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

func openVPNProfilesPath(country: String) throws -> URL {
    try openVPNDirectory().appendingPathComponent("\(slug(country)).profiles.json")
}

func openVPNStatePath() throws -> URL {
    try openVPNDirectory().appendingPathComponent("state.json")
}

func openVPNAuthPath() throws -> URL {
    try openVPNDirectory().appendingPathComponent("auth.txt")
}

func saveJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let data = try JSONEncoder().encode(value)
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}

func loadJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(type, from: data)
}

func openVPNExecutable() throws -> String {
    let candidates = [
        "/opt/homebrew/opt/openvpn/sbin/openvpn",
        "/usr/local/opt/openvpn/sbin/openvpn",
        "/opt/homebrew/sbin/openvpn",
        "/usr/local/sbin/openvpn",
        "/usr/sbin/openvpn",
    ]

    for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
        return candidate
    }

    let result = try run("/usr/bin/which", ["openvpn"])
    if result.status == 0 {
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty {
            return path
        }
    }

    throw CLIError.commandFailed("OpenVPN not found. Install it with: brew install openvpn")
}

func storeOpenVPNPassword(username: String, password: String) throws {
    let result = try run("/usr/bin/security", [
        "add-generic-password", "-U",
        "-s", "nordvpn-macos-cli-openvpn",
        "-a", username,
        "-w", password,
    ])
    if result.status != 0 {
        throw CLIError.commandFailed("Unable to store password in Keychain: \(result.output)")
    }
}

func loadOpenVPNPassword(username: String) throws -> String {
    let result = try run("/usr/bin/security", [
        "find-generic-password",
        "-s", "nordvpn-macos-cli-openvpn",
        "-a", username,
        "-w",
    ])
    if result.status != 0 {
        throw CLIError.commandFailed("Unable to read password from Keychain. Re-run setup-openvpn for this username.")
    }
    return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
}

func fetchNordVPNOpenVPNConfig(hostname: String, useTCP: Bool) throws -> String {
    let proto = useTCP ? "tcp" : "udp"
    let url = "https://downloads.nordcdn.com/configs/files/ovpn_\(proto)/servers/\(hostname).\(proto).ovpn"
    let result = try run("/usr/bin/curl", ["-fsSL", url])
    if result.status != 0 {
        throw CLIError.commandFailed("Unable to download OpenVPN config for \(hostname): \(result.output)")
    }
    return result.output
}

func configuredOpenVPNConfig(_ config: String) throws -> String {
    var lines = config.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    lines.removeAll { line in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed == "auth-user-pass" || trimmed.hasPrefix("auth-user-pass ")
    }
    lines.append("auth-user-pass \"\(try openVPNAuthPath().path)\"")
    lines.append("auth-nocache")
    return lines.joined(separator: "\n") + "\n"
}

func fetchNordVPNServers(country: String, count: Int, technologyIdentifier: String = "ikev2") throws -> [NordVPNServer] {
    let key = normalizedCountryKey(country)
    guard let countryID = nordVPNCountryIDs[key] else {
        throw CLIError.invalidArgument("Unknown NordVPN country: \(country)")
    }

    var components = URLComponents(string: "https://api.nordvpn.com/v1/servers/recommendations")!
    components.queryItems = [
        URLQueryItem(
            name: "filters",
            value: "{\"country_id\":\(countryID),\"servers_technologies\":[{\"identifier\":\"\(technologyIdentifier)\"}]}"
        ),
        URLQueryItem(name: "limit", value: String(count)),
    ]

    guard let url = components.url else {
        throw CLIError.commandFailed("Unable to build NordVPN API URL.")
    }

    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        throw CLIError.commandFailed("Unable to fetch NordVPN server recommendations: \(error.localizedDescription)")
    }

    guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        throw CLIError.commandFailed("Unable to parse NordVPN server recommendations.")
    }

    let servers = json.compactMap { item -> NordVPNServer? in
        guard let hostname = item["hostname"] as? String,
              let name = item["name"] as? String else {
            return nil
        }
        let load = item["load"] as? Int ?? 0
        return NordVPNServer(name: name, hostname: hostname, load: load)
    }

    if servers.count < count {
        throw CLIError.commandFailed("Only found \(servers.count) \(technologyIdentifier) server(s) for \(country).")
    }

    return Array(servers.prefix(count))
}

func readPassword(hidden: Bool) throws -> String {
    var restoreEcho = false

    if hidden {
        print("NordVPN service password: ", terminator: "")
        fflush(stdout)
        _ = try? run("/bin/stty", ["-echo"])
        restoreEcho = true
    }

    defer {
        if restoreEcho {
            _ = try? run("/bin/stty", ["echo"])
            print("")
        }
    }

    guard let password = readLine(), !password.isEmpty else {
        throw CLIError.missingArgument("Missing NordVPN service password.")
    }

    return password
}

func generateMobileconfig(country: String, args: [String]) throws {
    let count = try parseCount(args)
    guard let username = try optionValue(args, option: "--username") else {
        throw CLIError.missingArgument("Missing --username <NordVPN service username>.")
    }

    let password = try readPassword(hidden: !shouldReadPasswordFromStdin(args))
    let servers = try fetchNordVPNServers(country: country, count: count)
    let countryName = country.trimmingCharacters(in: .whitespacesAndNewlines)
    let outputPath = try optionValue(args, option: "--output") ??
        FileManager.default.currentDirectoryPath + "/nordvpn-\(slug(countryName))-\(count).mobileconfig"

    var payloads: [[String: Any]] = []

    for (index, server) in servers.enumerated() {
        let profileName = "NordVPN \(countryName) \(index + 1)"
        payloads.append([
            "PayloadType": "com.apple.vpn.managed",
            "PayloadVersion": 1,
            "PayloadIdentifier": "com.trevislabs.nordvpn-macos-cli.vpn.\(slug(profileName))",
            "PayloadUUID": UUID().uuidString.uppercased(),
            "PayloadDisplayName": profileName,
            "UserDefinedName": profileName,
            "VPNType": "IKEv2",
            "IKEv2": [
                "RemoteAddress": server.hostname,
                "RemoteIdentifier": server.hostname,
                "LocalIdentifier": "",
                "AuthenticationMethod": "None",
                "ExtendedAuthEnabled": 1,
                "AuthName": username,
                "AuthPassword": password,
                "DeadPeerDetectionRate": "Medium",
                "DisconnectOnIdle": 0,
                "DisableMOBIKE": 0,
                "DisableRedirect": 0,
                "EnableCertificateRevocationCheck": 0,
                "EnablePFS": 0,
                "UseConfigurationAttributeInternalIPSubnet": 0,
            ],
        ])
    }

    let profile: [String: Any] = [
        "PayloadType": "Configuration",
        "PayloadVersion": 1,
        "PayloadIdentifier": "com.trevislabs.nordvpn-macos-cli.\(slug(countryName)).profiles",
        "PayloadUUID": UUID().uuidString.uppercased(),
        "PayloadDisplayName": "NordVPN \(countryName) CLI Profiles",
        "PayloadDescription": "NordVPN IKEv2 profiles generated by nordvpn-macos-cli.",
        "PayloadOrganization": "nordvpn-macos-cli",
        "PayloadRemovalDisallowed": false,
        "PayloadContent": payloads,
    ]

    let data = try PropertyListSerialization.data(
        fromPropertyList: profile,
        format: .xml,
        options: 0
    )

    let url = URL(fileURLWithPath: outputPath)
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outputPath)

    print("Wrote: \(outputPath)")
    print("Generated profiles:")
    for (index, server) in servers.enumerated() {
        print("- NordVPN \(countryName) \(index + 1): \(server.hostname) (\(server.name), load \(server.load))")
    }
    print("Warning: this .mobileconfig contains the NordVPN service password. Delete it after installation.")

    if shouldOpen(args) {
        _ = try run("/usr/bin/open", [outputPath])
    }
}

func setupOpenVPN(country: String, args: [String]) throws {
    let count = try parseCount(args)
    guard let username = try optionValue(args, option: "--username") else {
        throw CLIError.missingArgument("Missing --username <NordVPN service username>.")
    }

    _ = try openVPNExecutable()
    let password = try readPassword(hidden: !shouldReadPasswordFromStdin(args))
    try storeOpenVPNPassword(username: username, password: password)

    let useTCP = shouldUseTCP(args)
    let servers = try fetchNordVPNServers(
        country: country,
        count: count,
        technologyIdentifier: useTCP ? "openvpn_tcp" : "openvpn_udp"
    )
    let countryName = country.trimmingCharacters(in: .whitespacesAndNewlines)
    let directory = try openVPNDirectory().appendingPathComponent(slug(countryName), isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    var profiles: [OpenVPNProfile] = []
    for (index, server) in servers.enumerated() {
        let rawConfig = try fetchNordVPNOpenVPNConfig(hostname: server.hostname, useTCP: useTCP)
        let config = try configuredOpenVPNConfig(rawConfig)
        let profileName = "NordVPN \(countryName) \(index + 1)"
        let configPath = directory.appendingPathComponent("\(slug(profileName)).ovpn")
        try config.write(to: configPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configPath.path)

        profiles.append(OpenVPNProfile(
            name: profileName,
            country: countryName,
            hostname: server.hostname,
            configPath: configPath.path,
            username: username,
            remoteIP: nil,
            load: server.load
        ))
    }

    try saveJSON(profiles, to: openVPNProfilesPath(country: countryName))
    print("Saved \(profiles.count) OpenVPN profile(s) for \(countryName):")
    for profile in profiles {
        print("- \(profile.name): \(profile.hostname)")
    }
    print("Password stored in macOS Keychain for account: \(username)")
    print("Rotate with: \(executableName) rotate-openvpn \"\(countryName)\" --ip")
}

func loadOpenVPNProfiles(country: String) throws -> [OpenVPNProfile] {
    let countryName = country.trimmingCharacters(in: .whitespacesAndNewlines)
    let path = try openVPNProfilesPath(country: countryName)
    guard FileManager.default.fileExists(atPath: path.path) else {
        throw CLIError.commandFailed("No OpenVPN profiles found for \(countryName). Run setup-openvpn first.")
    }
    return try loadJSON([OpenVPNProfile].self, from: path)
}

func currentOpenVPNState() throws -> OpenVPNState? {
    let path = try openVPNStatePath()
    guard FileManager.default.fileExists(atPath: path.path) else {
        return nil
    }
    return try? loadJSON(OpenVPNState.self, from: path)
}

func processIsRunning(pid: Int32) -> Bool {
    kill(pid, 0) == 0
}

func terminateOpenVPN(pid: Int32, signal: Int32) throws {
    if kill(pid, signal) == 0 || errno == ESRCH {
        return
    }

    if errno == EPERM {
        let result = try run("/usr/bin/sudo", ["/bin/kill", "-\(signal)", String(pid)])
        if result.status != 0 {
            throw CLIError.commandFailed("Unable to stop OpenVPN process \(pid): \(result.output)")
        }
        return
    }

    throw CLIError.commandFailed("Unable to stop OpenVPN process \(pid).")
}

func stopOpenVPN(quiet: Bool = false) throws {
    guard let state = try currentOpenVPNState() else {
        if !quiet { print("No managed OpenVPN process found.") }
        return
    }

    if processIsRunning(pid: state.pid) {
        if !quiet { print("Stopping \(state.profileName) (pid \(state.pid))...") }
        try terminateOpenVPN(pid: state.pid, signal: SIGTERM)
        for _ in 0..<20 {
            if !processIsRunning(pid: state.pid) { break }
            usleep(250_000)
        }
        if processIsRunning(pid: state.pid) {
            try terminateOpenVPN(pid: state.pid, signal: SIGKILL)
        }
    }

    try? FileManager.default.removeItem(at: openVPNStatePath())
}

func statusOpenVPN() throws {
    guard let state = try currentOpenVPNState() else {
        print("Disconnected")
        return
    }

    if processIsRunning(pid: state.pid) {
        print("Connected or connecting: \(state.profileName) (\(state.hostname), pid \(state.pid))")
    } else {
        print("Stale state: \(state.profileName) pid \(state.pid) is not running")
    }
}

func writeAuthFile(username: String) throws {
    let password = try loadOpenVPNPassword(username: username)
    let auth = "\(username)\n\(password)\n"
    let path = try openVPNAuthPath()
    try auth.write(to: path, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
}

func rotateOpenVPN(country: String, args: [String]) throws {
    let profiles = try loadOpenVPNProfiles(country: country)
    guard let selected = profiles.randomElement() else {
        throw CLIError.commandFailed("No OpenVPN profiles available for \(country).")
    }

    if shouldDryRun(args) {
        print("Dry run: would stop current managed OpenVPN process.")
        print("Dry run: would connect: \(selected.name) (\(selected.hostname))")
        return
    }

    guard let username = try optionValue(args, option: "--username") else {
        throw CLIError.missingArgument("Missing --username <NordVPN service username>.")
    }

    let openvpn = try openVPNExecutable()
    try writeAuthFile(username: username)
    try stopOpenVPN(quiet: true)

    let waitSeconds = try parseWait(args, defaultWait: 10)
    let logPath = URL(fileURLWithPath: "/tmp/nordvpn-macos-cli-openvpn.log")
    let pidPath = URL(fileURLWithPath: "/tmp/nordvpn-macos-cli-openvpn.pid")
    try? FileManager.default.removeItem(at: pidPath)

    print("Connecting: \(selected.name) (\(selected.hostname))")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    process.arguments = [
        openvpn,
        "--config", selected.configPath,
        "--daemon", "nordvpn-macos-cli",
        "--writepid", pidPath.path,
        "--log", logPath.path,
    ]
    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        throw CLIError.commandFailed("OpenVPN failed to start. Check log: \(logPath.path)")
    }

    sleep(waitSeconds)

    let pidText = (try? String(contentsOf: pidPath, encoding: .utf8)) ?? ""
    guard let pid = Int32(pidText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        throw CLIError.commandFailed("OpenVPN process was not found after start. Check log: \(logPath.path)")
    }

    let state = OpenVPNState(
        pid: pid,
        profileName: selected.name,
        country: selected.country,
        hostname: selected.hostname,
        startedAt: ISO8601DateFormatter().string(from: Date())
    )
    try saveJSON(state, to: openVPNStatePath())

    print("Started: \(selected.name) (pid \(pid))")
    try printPublicIPIfRequested(shouldPrintIP(args))
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
    case "generate-mobileconfig":
        try generateMobileconfig(country: try requireCountry(args), args: args)
    case "setup-openvpn":
        try setupOpenVPN(country: try requireCountry(args), args: args)
    case "rotate-openvpn":
        try rotateOpenVPN(country: try requireCountry(args), args: args)
    case "status-openvpn":
        try statusOpenVPN()
    case "stop-openvpn":
        try stopOpenVPN()
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
