import Foundation

enum PasswordGenerator {
    struct Options: Equatable {
        var length: Int = 16
        var uppercase: Bool = true
        var lowercase: Bool = true
        var digits: Bool = true
        var symbols: Bool = true
        var excludeAmbiguous: Bool = true
    }

    static func generate(_ options: Options = Options()) -> String {
        var pools: [String] = []
        if options.lowercase { pools.append(options.excludeAmbiguous ? "abcdefghjkmnpqrstuvwxyz" : "abcdefghijklmnopqrstuvwxyz") }
        if options.uppercase { pools.append(options.excludeAmbiguous ? "ABCDEFGHJKLMNPQRSTUVWXYZ" : "ABCDEFGHIJKLMNOPQRSTUVWXYZ") }
        if options.digits { pools.append(options.excludeAmbiguous ? "23456789" : "0123456789") }
        if options.symbols { pools.append("!@#$%^&*()-_=+[]{}") }
        if pools.isEmpty { pools = ["abcdefghjkmnpqrstuvwxyz"] }

        let length = min(128, max(4, options.length))
        var chars: [Character] = []
        // Ensure at least one from each selected pool
        for pool in pools {
            if let c = pool.randomElement() { chars.append(c) }
        }
        let all = pools.joined()
        while chars.count < length {
            if let c = all.randomElement() { chars.append(c) }
        }
        chars.shuffle()
        return String(chars.prefix(length))
    }

    static func strengthLabel(for password: String) -> String {
        let len = password.count
        var classes = 0
        if password.rangeOfCharacter(from: .lowercaseLetters) != nil { classes += 1 }
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil { classes += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { classes += 1 }
        if password.unicodeScalars.contains(where: { CharacterSet.alphanumerics.inverted.contains($0) }) { classes += 1 }
        let score = len + classes * 4
        if score >= 28 { return "很强" }
        if score >= 20 { return "强" }
        if score >= 14 { return "中" }
        return "弱"
    }
}
