import AppKit
import Carbon
import KeyOopsCore
import MacLayouts

@MainActor public final class CorrectionService: NSObject {
    public typealias LayoutPair = (english: KeyboardLayout, russian: KeyboardLayout)
    private let layouts: @MainActor () throws -> LayoutPair
    private let protectedInput: () -> Bool
    private let confirm: (String, Bool) -> Bool
    private let maximumCharacters = 4096

    public init(layouts: @escaping @MainActor () throws -> LayoutPair = SystemLayouts.pair,
                protectedInput: @escaping () -> Bool = { IsSecureEventInputEnabled() },
                confirm: @escaping (String, Bool) -> Bool) {
        self.layouts = layouts
        self.protectedInput = protectedInput
        self.confirm = confirm
    }

    @objc public func correctSelection(_ pasteboard: NSPasteboard, userData: String?,
                                      error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        if let failure = process(pasteboard) { error.pointee = failure as NSString }
    }

    public func process(_ pasteboard: NSPasteboard) -> String? {
        guard !protectedInput() else { return "Secure input is active." }
        let revision = pasteboard.changeCount
        guard let original = pasteboard.string(forType: .string),
              !original.isEmpty, original.prefix(maximumCharacters + 1).count <= maximumCharacters else {
            return "Select between 1 and 4,096 characters of plain text."
        }
        do {
            let language = try LayoutLanguage.reading(original)
            let pair = try layouts()
            let (from, to) = language == .english ? (pair.english, pair.russian) : (pair.russian, pair.english)
            let candidate = try from.convert(original, to: to)
            guard candidate != original else { return "Both layouts produce the same text." }
            let likely = Assessment.suggests(original: original, candidate: candidate, source: language)
            guard confirm(candidate, likely) else { return "Correction cancelled." }
            guard !protectedInput(), pasteboard.changeCount == revision else {
                return "The selection changed or secure input became active."
            }
            // Services supplies a private transaction pasteboard. The host inserts the reply.
            guard pasteboard.setString(candidate, forType: .string) else { return "Could not return the correction." }
            return nil
        } catch LayoutError.multiple {
            return "Select the intended input source or leave one layout enabled per language."
        } catch LayoutError.unavailable {
            return "Enable an English and a Russian keyboard layout in System Settings."
        } catch ConversionError.mixed {
            return "Select one language at a time."
        } catch {
            return "Select English or Russian text made with ordinary or shifted keys. Every character must have a clear mapping."
        }
    }
}
