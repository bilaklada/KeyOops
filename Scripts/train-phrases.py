"""Usage: python3 Scripts/train-phrases.py /path/to/lmplz en_pud.conllu ru_pud.conllu"""
import pathlib
import re
import subprocess
import sys

# Supplement the news-domain PUD data with original conversational examples.
chat = """my name was on the list
your name is on the envelope
my name appears twice
i am ready to go
i am very tired today
we are looking for the right keyboard
can you see what i am typing
i was looking at the screen
меня зовут анна
мой друг уже здесь
это мой новый телефон
мы смотрим на экран
я не знаю как это сделать
я пишу тебе письмо
мое имя есть в списке
как тебя зовут"""
lines = chat.splitlines()
for filename in sys.argv[2:]:
    sentences = [line[9:].strip().lower() for line in pathlib.Path(filename).read_text().splitlines()
                 if line.startswith("# text = ")]
    assert len(sentences) == 1000
    for sentence in sentences[:900]:
        lines.extend(re.findall(r"[a-zа-яё]+(?: [a-zа-яё]+)*", sentence))
result = subprocess.run([sys.argv[1], "-o", "2", "-S", "100M", "--discount_fallback"],
                        input="\n".join(lines) + "\n", text=True, stdout=subprocess.PIPE, check=True)
pathlib.Path("Sources/KeyOopsCore/Data/phrases.arpa").write_text(result.stdout)
