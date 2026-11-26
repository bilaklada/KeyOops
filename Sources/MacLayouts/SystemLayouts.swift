import Carbon
import Foundation
import KeyOopsCore

public enum LayoutError: Error { case unavailable, multiple }

public enum SystemLayouts {
    /// Query on demand so enabling or switching layouts takes effect on the next invocation.
    @MainActor public static func pair() throws -> (english: KeyboardLayout, russian: KeyboardLayout) {
        let sources = TISCreateInputSourceList(nil, false).takeRetainedValue() as NSArray
        let current = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        func identifier(_ source: TISInputSource) -> String? {
            guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
            return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
        }
        func find(_ language: String) throws -> KeyboardLayout {
            var candidates: [KeyboardLayout] = []
            for item in sources {
                let source = item as! TISInputSource
                guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages),
                      let tags = Unmanaged<CFArray>.fromOpaque(raw).takeUnretainedValue() as? [String],
                      tags.first?.split(separator: "-").first == Substring(language),
                      let layout = read(source) else { continue }
                if identifier(source) == identifier(current) { return layout }
                candidates.append(layout)
            }
            guard let layout = candidates.first else { throw LayoutError.unavailable }
            guard candidates.count == 1 else { throw LayoutError.multiple }
            return layout
        }
        return try (find("en"), find("ru"))
    }

    @MainActor private static func read(_ source: TISInputSource) -> KeyboardLayout? {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        let hardware = UInt32(LMGetKbdType())
        return data.withUnsafeBytes { bytes in
            guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            var outputs: [PhysicalKey: Character] = [:]
            // macOS virtual codes through ANSI grave include the main typing block.
            // Keypad digits would add indistinguishable origins to number-row characters.
            for code in UInt16(0)...UInt16(kVK_ANSI_Grave) {
                for shifted in [false, true] {
                    var deadState: UInt32 = 0
                    var length = 0
                    var buffer = [UniChar](repeating: 0, count: 8)
                    let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown),
                        shifted ? UInt32(shiftKey >> 8) : 0, hardware, 0, &deadState,
                        buffer.count, &length, &buffer)
                    guard status == noErr, deadState == 0, length > 0 else { continue }
                    let value = String(decoding: buffer.prefix(length), as: UTF16.self)
                    guard value.count == 1, let char = value.first,
                          !char.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
                    else { continue }
                    outputs[PhysicalKey(code: code, shifted: shifted)] = char
                }
            }
            return KeyboardLayout(outputs: outputs)
        }
    }
}
