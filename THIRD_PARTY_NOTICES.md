# Dictionary data and lookup code

KeyOops includes the English and Russian lexicons from [Tilqos](https://github.com/elapen/tilqos) and adapts its runtime Hunspell lookup and binary reader. The build-time encoder and additional languages are omitted. The lookup code and supplemental word lists are copyright © 2026 Tilqos contributors, MIT licensed.

The Russian binary derives from Alexander I. Lebedev's LibreOffice ru_RU Hunspell dictionary. The English binary derives from LibreOffice en_US (SCOWL and Ispell). Each binary contains hashed stems and affix rules. The complete original notices are provided in Licenses and accompany the app. These data retain their respective upstream terms.

The four English and Russian isolated-word test lists in Tests/VerifyLayouts/Corpus.swift are adapted from the Tilqos regression corpus under the same MIT license. They are used only in development checks.

The English–Russian phrase model (phrases.arpa) is distributed under CC BY-SA 3.0.
It is derived from the first 900 sentences of each of the Universal Dependencies
[English PUD](https://github.com/UniversalDependencies/UD_English-PUD/tree/r2.16)
and [Russian PUD](https://github.com/UniversalDependencies/UD_Russian-PUD/tree/r2.16)
treebanks by the PUD contributors, with original conversational examples.
Scripts/train-phrases.py normalizes text and trains a smoothed bigram model using
KenLM lmplz. See Licenses/PUD-CC-BY-SA-3.0.txt.
