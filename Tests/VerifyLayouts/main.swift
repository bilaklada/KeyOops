import KeyOopsCore
import MacLayouts

let pair = try SystemLayouts.pair()
for (typed, intended) in [("руддщ", "hello"), ("цщкдв", "world"), ("Привет мир", "Ghbdtn vbh")] {
    guard try pair.russian.convert(typed, to: pair.english) == intended,
          try pair.english.convert(intended, to: pair.russian) == typed else {
        fatalError("Enabled layouts did not match the ABC/Russian integration fixture")
    }
}
print("Enabled English and Russian layouts passed bidirectional checks.")

checkCorpus(english: pair.english, russian: pair.russian)

@MainActor func proposal(_ text: String) -> LayoutProposal? {
    LayoutProposal.ending(in: text, atDocumentStart: true, english: pair.english, russian: pair.russian)
}
let reported = proposal("Pf,skf gthtrk.xbnm zpsr ")
precondition(reported?.replacement == "Забыла переключить язык" && reported?.decision == .automatic)
precondition(proposal("z ") == nil)
let short = proposal("z ghbdtn ")
precondition(short?.replacement == "я привет" && short?.decision == .suggest)
let reverse = try pair.english.convert("I forgot language", to: pair.russian)
precondition(proposal(reverse + " ")?.replacement == "I forgot language")
print("Contextual layout examples passed.")
