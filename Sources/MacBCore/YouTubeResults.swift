import Foundation

/// Reading one thing out of a YouTube results page: the first video's
/// identifier.
///
/// Nothing else is taken from the page — no title, no channel, no description,
/// no comment — so nothing written on YouTube by anybody can reach the model or
/// the user. An identifier is eleven characters of a fixed alphabet, which is
/// narrow enough to check rather than trust.
///
/// Pure, because the interesting failure here is a page whose shape has changed,
/// and that is provable with a string.
public enum YouTubeResults {
    public static let identifierLength = 11

    public static func firstVideoIdentifier(in html: String) -> String? {
        let marker = "\"videoId\":\""
        var index = html.startIndex
        while let found = html.range(of: marker, range: index..<html.endIndex) {
            let start = found.upperBound
            let candidate = String(html[start...].prefix(identifierLength))
            if candidate.count == identifierLength, candidate.allSatisfy(isIdentifierCharacter),
               html.index(start, offsetBy: identifierLength, limitedBy: html.endIndex)
                   .map({ $0 == html.endIndex || html[$0] == "\"" }) == true {
                return candidate
            }
            index = found.upperBound
        }
        return nil
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        guard character.isASCII else { return false }
        return character.isLetter || character.isNumber || character == "-" || character == "_"
    }
}
