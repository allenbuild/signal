import Foundation

public struct SignalCommandURLPolicy: Sendable {
    public init() {}

    public func validate(_ value: String) throws -> URL {
        guard value.count <= 2_048,
              !value.unicodeScalars.contains(where: {
                  CharacterSet.whitespacesAndNewlines.contains($0)
                      || CharacterSet.controlCharacters.contains($0)
              }),
              var components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.port == nil || components.port == 443,
              let unnormalizedHost = components.host?.lowercased(),
              hasCanonicalAuthority(
                  value,
                  host: unnormalizedHost,
                  port: components.port
              )
        else {
            throw SignalCommandValidationError.unsafeURL(value)
        }

        let host = unnormalizedHost.hasSuffix(".")
            ? String(unnormalizedHost.dropLast())
            : unnormalizedHost
        guard isPublicDomainName(host) else {
            throw SignalCommandValidationError.unsafeURL(value)
        }

        components.scheme = "https"
        components.host = host
        guard let result = components.url else {
            throw SignalCommandValidationError.unsafeURL(value)
        }
        return result
    }

    public func validate(_ value: String, exactHost: String) throws -> URL {
        let url = try validate(value)
        guard url.host?.lowercased() == exactHost.lowercased() else {
            throw SignalCommandValidationError.unsafeURL(value)
        }
        return url
    }

    private func hasCanonicalAuthority(
        _ value: String,
        host: String,
        port: Int?
    ) -> Bool {
        guard let schemeSeparator = value.range(of: "://") else {
            return false
        }
        let authorityStart = schemeSeparator.upperBound
        let authorityEnd = value[authorityStart...].firstIndex {
            $0 == "/" || $0 == "?" || $0 == "#"
        } ?? value.endIndex
        let authority = value[authorityStart..<authorityEnd]
        let expectedAuthority = port == 443 ? "\(host):443" : host
        return authority.lowercased() == expectedAuthority
    }

    private func isPublicDomainName(_ host: String) -> Bool {
        guard host.count <= 253,
              host.contains("."),
              host.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
                      .contains($0)
              }),
              host.unicodeScalars.contains(where: {
                  CharacterSet.lowercaseLetters.contains($0)
              }),
              !host.contains(":")
        else {
            return false
        }

        let blockedNames = [
            "localhost",
            "localhost.localdomain",
            "broadcasthost",
            "ip6-localhost",
            "ip6-loopback"
        ]
        let blockedSuffixes = [
            ".localhost",
            ".local",
            ".internal",
            ".lan",
            ".home",
            ".test",
            ".invalid",
            ".example",
            ".onion"
        ]
        guard !blockedNames.contains(host),
              !blockedSuffixes.contains(where: host.hasSuffix)
        else {
            return false
        }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        for label in labels {
            guard !label.isEmpty,
                  label.count <= 63,
                  label.first != "-",
                  label.last != "-"
            else {
                return false
            }
        }

        // Reject decimal, hexadecimal, octal, dotted, and IPv6 literals. Public
        // commands open named HTTPS destinations only.
        if host.hasPrefix("0x")
            || host.split(separator: ".").allSatisfy({ label in
                label.allSatisfy(\.isNumber)
            })
        {
            return false
        }
        return true
    }
}
