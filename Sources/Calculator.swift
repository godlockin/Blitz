import Foundation

enum Calculator {
    /// Returns a displayable result for quick math in the search box.
    /// Accepts expressions like `1+2*3`, `(10-3)/2`, `12%`, `2^10`.
    static func evaluate(_ raw: String) -> String? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Normalize unicode operators
        trimmed = trimmed
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "＋", with: "+")

        // Soften ^ power into multiplication chains for small integer exponents later
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/()%^ ")
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }

        let hasOp = trimmed.contains(where: { "+-*/()%^".contains($0) })
        guard hasOp else { return nil }

        let withPercent = rewritePercents(trimmed)
        let withPow = rewriteCaretPower(withPercent)

        let expr = NSExpression(format: withPow)
        guard let value = expr.expressionValue(with: nil, context: nil) as? NSNumber else { return nil }
        let d = value.doubleValue
        guard d.isFinite else { return nil }
        if abs(d - d.rounded()) < 1e-9 {
            return String(format: "%.0f", d)
        }
        var s = String(format: "%.8f", d)
        while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) {
            s.removeLast()
        }
        return s
    }

    private static func rewritePercents(_ s: String) -> String {
        // 12% -> (12/100.0) ; leave 12%3 alone by requiring % not followed by digit
        var out = ""
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            if chars[i] == "%" {
                let nextIsDigit = i + 1 < chars.count && chars[i + 1].isNumber
                if !nextIsDigit {
                    out += "/100.0"
                    i += 1
                    continue
                }
            }
            out.append(chars[i])
            i += 1
        }
        return out
    }

    /// Expand simple `a^b` where b is a small non-negative integer into repeated multiplication.
    private static func rewriteCaretPower(_ s: String) -> String {
        guard s.contains("^") else { return s }
        var result = s
        while let range = result.range(of: "^") {
            let left = String(result[..<range.lowerBound])
            let right = String(result[range.upperBound...])
            let base = left.trimmingCharacters(in: .whitespaces)
            let rest = right.trimmingCharacters(in: .whitespaces)
            // base: trailing number; exp: leading integer
            guard let baseMatch = base.range(of: #"([0-9]+(\.[0-9]+)?)$"#, options: .regularExpression),
                  let expMatch = rest.range(of: #"^[0-9]+"#, options: .regularExpression) else {
                return s.replacingOccurrences(of: "^", with: "")
            }
            let baseVal = String(base[baseMatch])
            let expStr = String(rest[expMatch])
            guard let exp = Int(expStr), exp >= 0, exp <= 12 else { return s }
            let prefix = String(base[..<baseMatch.lowerBound])
            let suffix = String(rest[expMatch.upperBound...])
            let expanded: String
            if exp == 0 {
                expanded = "1"
            } else {
                expanded = "(" + Array(repeating: baseVal, count: exp).joined(separator: "*") + ")"
            }
            result = prefix + expanded + suffix
        }
        return result
    }
}
