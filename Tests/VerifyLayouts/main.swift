import MacLayouts

let pair = try SystemLayouts.pair()
for (typed, intended) in [("руддщ", "hello"), ("цщкдв", "world"), ("Привет мир", "Ghbdtn vbh")] {
    guard try pair.russian.convert(typed, to: pair.english) == intended,
          try pair.english.convert(intended, to: pair.russian) == typed else {
        fatalError("Enabled layouts did not match the ABC/Russian integration fixture")
    }
}
print("Enabled English and Russian layouts passed bidirectional checks.")
