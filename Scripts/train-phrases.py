"""Usage: python3 Scripts/train-phrases.py /path/to/lmplz en_pud.conllu ru_pud.conllu"""
import json
import math
import pathlib
import random
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
как тебя зовут
when are you coming home
we can talk after lunch
all of us have the same question
are there any seats left
i left my keys here
some of my friends are coming
put the book on the table
you can tell me about it later
if you want to go just let me know
я скоро вернусь домой
мы с тобой уже знакомы
что ты будешь делать вечером
положи ключи на стол
мне нужно немного времени
я могу тебе помочь
у нас есть ещё один вопрос
если хочешь приходи к нам завтра"""
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

# Fit the keyboard-state transition prior separately from the language model.
# Simulate uninterrupted typing plus slips of different lengths on training
# sentences only. These are synthetic priors, not estimates from user telemetry.
rng = random.Random(731)
counts = [[1, 1], [1, 1]]
for sentence in lines:
    length = len(sentence.split())
    states = [0] * length
    if length and rng.random() < 0.5:
        start = rng.randrange(length)
        stop = min(length, start + rng.choice([1, 2, 3, 5, 8, length]))
        states[start:stop] = [1] * (stop - start)
    for left, right in zip(states, states[1:]):
        counts[left][right] += 1
prior = [[math.log10(count / sum(row)) for count in row] for row in counts]
pathlib.Path("Sources/KeyOopsCore/Data/layout-channel.json").write_text(json.dumps(prior) + "\n")
