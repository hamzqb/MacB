import Foundation

/// Turning a piece of text into a JavaScript string the browser can be handed.
///
/// MacB builds a small script when it reads or clicks something in a page, and
/// the thing the user named goes inside it. That name is text from a
/// conversation — it can hold a quote, a backslash, a newline, a line of HTML —
/// and none of it may end up as code. Everything outside a plain printable
/// range is escaped rather than trusted.
///
/// Written by hand rather than with `JSONSerialization`, which raises an
/// Objective-C exception for a bare string — one Swift cannot catch, so a
/// `try?` in front of it is no protection at all. MacB crashed on every click
/// in a browser because of that.
public enum JavaScriptLiteral {
    public static func string(_ value: String) -> String {
        var out = "\""
        for character in value.unicodeScalars {
            switch character {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            // A literal < or > could close the script element it sits in, and
            // the two line separators end a statement in JavaScript although
            // they are ordinary characters everywhere else.
            case "<": out += "\\u003C"
            case ">": out += "\\u003E"
            case "&": out += "\\u0026"
            case "\u{2028}": out += "\\u2028"
            case "\u{2029}": out += "\\u2029"
            default:
                if character.value < 0x20 || character.value == 0x7F {
                    out += String(format: "\\u%04X", character.value)
                } else {
                    out.unicodeScalars.append(character)
                }
            }
        }
        return out + "\""
    }
}
