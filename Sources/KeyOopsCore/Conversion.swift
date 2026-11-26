public enum LayoutLanguage: String, Sendable {
    case english = "en", russian = "ru"

    public var opposite: Self { self == .english ? .russian : .english }

    public static func reading(_ text: String) throws -> Self {
        var language: Self?
        for letter in text.lowercased() where letter.isLetter {
            let next: Self
            if "abcdefghijklmnopqrstuvwxyz".contains(letter) {
                next = .english
            } else if "абвгдеёжзийклмнопрстуфхцчшщъыьэюя".contains(letter) {
                next = .russian
            } else {
                throw ConversionError.unsupported
            }
            if let language, language != next { throw ConversionError.mixed }
            language = next
        }
        guard let language else { throw ConversionError.noLetters }
        return language
    }
}

public enum ConversionError: Error, Equatable {
    case mixed, noLetters, unsupported, ambiguous
}

public struct PhysicalKey: Hashable {
    public let code: UInt16
    public let shifted: Bool

    public init(code: UInt16, shifted: Bool) {
        self.code = code
        self.shifted = shifted
    }
}

public struct KeyboardLayout {
    private let outputs: [PhysicalKey: Character]
    private let keys: [Character: [PhysicalKey]]

    public init(outputs: [PhysicalKey: Character]) {
        self.outputs = outputs
        keys = Dictionary(grouping: outputs.keys, by: { outputs[$0]! })
    }

    public func convert(_ text: String, to target: Self) throws -> String {
        var result = ""
        for character in text {
            if character.isWhitespace {
                result.append(character)
                continue
            }
            guard let positions = keys[character] else { throw ConversionError.unsupported }
            let alternatives = positions.compactMap { target.outputs[$0] }
            guard alternatives.count == positions.count else { throw ConversionError.unsupported }
            guard let value = alternatives.first, alternatives.allSatisfy({ $0 == value }) else {
                throw ConversionError.ambiguous
            }
            result.append(value)
        }
        return result
    }
}
