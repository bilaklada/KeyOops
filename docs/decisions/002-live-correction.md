# 002 · Contextual live correction

Live mode uses Accessibility to read committed text from the focused writable text area in TextEdit or Notes. Keyboard events trigger checks without decoding the typed characters. A 24 ms coalescing interval gives the host time to insert text. The model and dictionaries load away from the main thread.

On whitespace, the decoder compares the typed and physical-key readings of each word. A forward and backward pass computes the best complete sequence under each reading at each position. The difference is the confidence margin. Scores combine bilingual KenLM probabilities, dictionary evidence, and a layout-state prior trained on simulated slips. Automatic mode commits high-margin words and keeps unresolved neighbors available for later evidence. Unseen target names can accompany a supported run for review.

The active window contains at most 16 words. When it fills, the oldest eight decisions are frozen and the recent words retain their left context. Sentence punctuation and line breaks finish the current fragment. Suggestions from completed fragments stay in one batch. At 4,096 UTF-16 units, a pending batch freezes until accepted or dismissed. The caret may advance beyond it without retaining the additional text.

One session belongs to one app process, window, field and document. Notes uses a field document identifier or requires the host to resolve a note text marker. Focus notifications, app activation, sleep, navigation and editing commands invalidate the binding. Append checks verify the original text, caret, and the length and beginning of the text to its right. A replacement rechecks ownership, exact source text and temporary selection immediately before writing. A successful edit can switch the active input source and supplies a guarded inverse edit. Dismissal and undo advance the lower bound of future inspection.

The selection Service continues to operate independently of live sessions.
