"""
ff4 dialog laid out at build time with katsuji: French typography, sentences packed into the dialog window.

The XML keeps the translation as written; `layout` runs on each dialog pointer while the banks are encoded, so
window breaks and line breaks are the build's, never hand-kept. Markup a previous layout added (`[new]`,
`[bold]`/`[normal]` around speakers) is stripped first, so laying out twice changes nothing.

ff4's script rules: `Name:` opens a speaker, set in bold at the start of each of their windows; a speaker change
starts a new window; «» speech without a visible speaker gets windows of its own; `[end]` / `[close_window]` close
the text. The window is 4 lines of 208 pixels, the fourth 200 (the page-turn arrow). A font switch holds until the
next one, across lines and windows; each message starts in the dialog font. Every line is measured in the font in
use where it starts, so a `[force_book]` narration wraps to the book font's widths.

Inside those rules katsuji does the setting: `typeset` spaces the punctuation the French way, and `TextLayout`
packs sentences onto a line while they fit and splits a sentence wider than the window over balanced lines.
"""

import re
import sys
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

from katsuji.layout import TextLayout
from katsuji.typeset import FRENCH, Markup
from script import Table

from metrics import TextMetrics

TABLE = Path("text/ff4fr.tbl")
FONTS = ["build/gen/font.dat", "build/gen/wicked_font.dat", "build/gen/book_font.dat", "build/gen/bold_font.dat"]
WINDOW_WIDTH = 208
LINE_WIDTHS = (208, 208, 208, 200)  # the fourth line leaves room for the page-turn arrow
NEW_WINDOW = "[new]"
ENDS = ("[end]", "[close_window]")
SPEAKER = re.compile(r"(\w+(?:\s+\w+)*):")
QUOTE = re.compile(r"«[^»]*»")
CONTROL = re.compile(r"\[[^\]]*\]")
LAYOUT_MARKUP = ("[bold]", "[normal]", "[book]", "[wicked]")
MARKUP = Markup(
    tag=r"\[[^\]]*\]",  # every ff4 tag: font switches, waits, terminators, raw codes
    glyphs=r"\[0x[0-9a-f]+\]",  # a raw code draws a glyph: a mark after it stays tight
    speakers=True,  # no space before the colon of "Beigan:" opening a line
)


ABBREVIATIONS = ("M.",)
"""Words ending in a period that never end a sentence: French keeps the title with the name ("M. Rosa"), and a
line never ends on one."""


@dataclass(frozen=True)
class Token:
    kind: str  # SPEAKER, QUOTE, SENTENCE, END, BREAK
    value: str


def clean(text: str) -> str:
    """`text` without the markup a layout adds, so laying it out again changes nothing."""
    cleaned = text.replace(NEW_WINDOW, "\n")
    for tag in LAYOUT_MARKUP:
        cleaned = cleaned.replace(tag, "")
    return cleaned


def tokenize(text: str) -> list[Token]:
    text = re.sub(r"\s+", " ", text.strip())
    tokens: list[Token] = []
    i = 0
    while i < len(text):
        if text[i].isspace():
            i += 1
            continue
        end = next((e for e in ENDS if text.startswith(e, i)), None)
        if end:
            tokens.append(Token("END", end))
            i += len(end)
        elif quote := QUOTE.match(text, i):
            tokens.append(Token("QUOTE", quote.group(0)))
            i = quote.end()
        elif speaker := SPEAKER.match(text, i):
            tokens.append(Token("SPEAKER", speaker.group(1)))
            i = speaker.end()
            while i < len(text) and text[i] in ": ":
                i += 1
        else:
            sentence, i = _sentence(text, i)
            if sentence.strip():
                tokens.append(Token("SENTENCE", sentence.strip()))
    return tokens


def _interrupts(text: str, i: int) -> bool:
    return text.startswith("«", i) or bool(SPEAKER.match(text, i)) or any(text.startswith(e, i) for e in ENDS)


def _sentence(text: str, i: int) -> tuple[str, int]:
    sentence = ""
    while i < len(text):
        if sentence.strip() and _interrupts(text, i):
            break
        char = text[i]
        sentence += char
        i += 1
        if char not in ".!?" or (char == "." and sentence.endswith("M.")):
            continue
        if i >= len(text) or any(text.startswith(e, i) for e in ENDS):
            break
        if text[i] == "[" and (close := text.find("]", i)) != -1:
            sentence += text[i : close + 1]
            i = close + 1
            continue
        if text[i].isspace():
            ahead = i
            while ahead < len(text) and text[ahead].isspace():
                ahead += 1
            if ahead < len(text) and (text[ahead].isupper() or _interrupts(text, ahead)):
                break
        elif SPEAKER.match(text, i):
            break
    return sentence, i


def _quote_sentences(quote: str) -> list[str]:
    """A «» quote cut into its sentences, the marks kept on the first and last, so a long quote turns windows
    between sentences rather than inside one."""
    inner = quote[1:-1].strip()
    sentences: list[str] = []
    i = 0
    while i < len(inner):
        sentence, i = _sentence(inner, i)
        if sentence.strip():
            sentences.append(sentence.strip())
    if not sentences:
        return [quote]
    sentences[0] = "«" + sentences[0]
    sentences[-1] += "»"
    return sentences


def _control_only(text: str) -> bool:
    return not CONTROL.sub("", text).strip()


def with_breaks(tokens: Sequence[Token]) -> list[Token]:
    """A break after a quote followed by more speech, and before a quote answering a speaker."""
    out: list[Token] = []
    speaking = False
    for index, token in enumerate(tokens):
        out.append(token)
        speaking = token.kind == "SPEAKER" or (speaking and token.kind not in ("QUOTE", "END"))
        following = tokens[index + 1] if index + 1 < len(tokens) else None
        if following is None:
            continue
        visible = following.kind == "SENTENCE" and not _control_only(following.value)
        if (token.kind == "QUOTE" and (following.kind in ("SPEAKER", "QUOTE") or visible)) or (
            token.kind == "SENTENCE" and speaking and following.kind == "QUOTE"
        ):
            out.append(Token("BREAK", ""))
    return out


class DialogLayout:
    """Lays one dialog pointer out into ff4 windows."""

    def __init__(self, metrics: TextMetrics) -> None:
        self.metrics = metrics
        self.text_layout = TextLayout(
            self.measure, WINDOW_WIDTH, FRENCH, MARKUP, abbreviations=ABBREVIATIONS, measure_after=self._measure_after
        )
        self.font = 0  # in use at the start of the open window
        self._start_font = 0  # the font the text `_set` is wrapping starts in

    def measure(self, line: str, font: int = 0) -> int:
        return self.metrics.measure_string(line, font)

    def _measure_after(self, line: str, before: str) -> int:
        """`line` measured in the font in use after `before`, the text laid out ahead of it."""
        return self.measure(line, self.metrics.font_after(before, self._start_font))

    def _line_fonts(self, lines: Sequence[str], font: int) -> list[int]:
        """The font each of `lines` starts in, the first in `font`."""
        fonts = []
        for line in lines:
            fonts.append(font)
            font = self.metrics.font_after(line, font)
        return fonts

    def _end_font(self) -> int:
        """The font in use after the open window's lines."""
        return self.metrics.font_after("\n".join(self.lines), self.font)

    def layout(self, text: str) -> str:
        """`text` laid out: `[new]` where a window must turn, sentences packed onto 4-line pages."""
        if not text:
            return text
        self.windows: list[str] = []
        self.lines: list[str] = []
        self.font = 0
        self.joinable = False  # the last line may take the next sentence of the same speaker
        speaker: str | None = None
        tokens = with_breaks(tokenize(clean(text)))
        for token in tokens:
            if token.kind == "BREAK":
                self._turn()
                speaker = None
            elif token.kind == "SPEAKER":
                if speaker is not None:
                    self._turn()
                speaker = f"[bold]{token.value}[normal]"
                self.joinable = False
            elif token.kind == "SENTENCE" and _control_only(token.value) and (self.lines or self.windows):
                self._append(token.value)
            elif token.kind == "SENTENCE":
                self._add(token.value, speaker)
            elif token.kind == "QUOTE":
                self.joinable = False
                for sentence in _quote_sentences(token.value):
                    self._add(sentence, None)
                speaker = None
                self.joinable = False
            else:  # END: the message ends; another one in the same pointer starts afresh
                self._append(token.value)
                self._finish()
                speaker = None
        self._finish()
        return "\n".join(self.windows)

    def _set(self, text: str, font: int) -> list[str]:
        """`text`, started in font `font`, typeset and wrapped to the window, a sentence wider than a line over
        balanced lines."""
        self._start_font = font
        return self.text_layout.reflow(text).split("\n")

    def _fits(self, lines: Sequence[str]) -> bool:
        """`lines` fit the open window: four lines at most, the fourth short enough for the page-turn arrow."""
        fonts = self._line_fonts(lines, self.font)
        return len(lines) <= len(LINE_WIDTHS) and all(
            self.measure(line, font) <= width for line, font, width in zip(lines, fonts, LINE_WIDTHS, strict=False)
        )

    def _add(self, sentence: str, speaker: str | None) -> None:
        """Put `sentence` on the open window's last line if the same voice goes on and it fits there, else on new
        lines; when it would cross the page, turn the window first and repeat the speaker."""
        opening = not self.joinable
        if self.lines and self.joinable:
            joined = self._set(f"{self.lines[-1]} {sentence}", self._line_fonts(self.lines, self.font)[-1])
            if len(joined) == 1 and self._fits([*self.lines[:-1], joined[0]]):
                self.lines[-1] = joined[0]
                return
        text = f"{speaker}: {sentence}" if speaker and opening else sentence
        if self.lines:
            lines = self._set(text, self._end_font())
            if self._fits([*self.lines, *lines]):
                self.lines.extend(lines)
                self.joinable = True
                return
            self._turn()
            text = f"{speaker}: {sentence}" if speaker else sentence
        self._fill(self._set(text, self.font))
        self.joinable = True

    def _fill(self, lines: list[str]) -> None:
        """Lay `lines` over windows, turning at the last line that fits (one sentence longer than a window)."""
        while lines:
            taken = len(lines)
            while taken > 1 and not self._fits(lines[:taken]):
                taken -= 1
            self.lines = lines[:taken]
            lines = lines[taken:]
            if lines:
                self._turn()

    def _append(self, text: str) -> None:
        """`text` (control tags) at the end of the last line written."""
        if self.lines:
            self.lines[-1] += text
        elif self.windows:
            self.windows[-1] += text
        else:
            self.lines = [text]

    def _turn(self) -> None:
        """Close the open window with `[new]`: the next text starts a fresh window."""
        if self.lines:
            self.font = self._end_font()
            self.windows.append("\n".join(self.lines) + NEW_WINDOW)
            self.lines = []
        self.joinable = False

    def _finish(self) -> None:
        """Close the open window at the end of a message, without `[new]`."""
        if self.lines:
            self.windows.append("\n".join(self.lines))
            self.lines = []
        self.font = 0  # the next message starts in the dialog font
        self.joinable = False


def dialog_layout() -> DialogLayout:
    table = Table(str(TABLE))
    return DialogLayout(TextMetrics(table, FONTS))


def main(paths: list[str]) -> int:
    """Print each dialog pointer of `paths` laid out, for review."""
    layout = dialog_layout()
    for name in paths:
        text = Path(name).read_text(encoding="utf-8")
        for pointer, body in re.findall(r'<sn:pointer id="(\d+)">(.*?)</sn:pointer>', text, re.S):
            print(f"==== {Path(name).stem}#{pointer}\n{layout.layout(body)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
