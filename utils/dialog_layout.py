"""
ff4 dialog laid out at build time with katsuji: the language's typography, sentences packed into the dialog window.

The XML keeps the translation as written; `layout` runs on each dialog pointer while the banks are encoded, so
window breaks and line breaks are the build's, never hand-kept. Markup a previous layout added (`[new]`,
`[bold]`/`[normal]` around speakers, the spacer before their colon) is stripped first, so laying out twice changes nothing.

ff4's script rules: `Name:` opens a speaker, set in bold at the start of each of their windows; a speaker change
starts a new window; quoted speech («» in French, '' in English) without a visible speaker gets windows of its own, and so does an announcement, a
whole sentence set in `[force_bold]` ("L'invocatrice Rydia se joint à toi !"); `[end]` / `[close_window]` close
the text; `[force_new]` is an editor's window turn, the speaker set again after it. The window is 4 lines of 208 pixels, the fourth 200 (the page-turn arrow). A font switch holds until the
next one, across lines and windows; each message starts in the dialog font. Every line is measured in the font in
use where it starts, so a `[force_book]` narration wraps to the book font's widths.

ff4 keeps those rules: it cuts each message into paragraphs (a speaker's sentences, narration, a quote, an
announcement) and says which open a window. katsuji does the setting: `typeset` spaces the punctuation the
language's way, `TextLayout` splits a sentence wider than the window over balanced lines, and `windows` packs
sentences onto a line while they fit, turns the window when they do not and sets the speaker again on each window
they carry onto.
"""

import re
import sys
from functools import lru_cache
from collections.abc import Sequence
from dataclasses import dataclass, replace
from pathlib import Path

from katsuji.dialog import Window
from katsuji.layout import TextLayout
from katsuji.windows import Paragraph, windows
from katsuji.typeset import ENGLISH, FRENCH, FRENCH_ONE_LETTER_WORDS, Markup, Typography, typeset
from katsuji.script import Table

from utils.metrics import TextMetrics

TABLE = Path("text/ff4fr.tbl")
FONTS = ["build/gen/font.dat", "build/gen/wicked_font.dat", "build/gen/book_font.dat", "build/gen/bold_font.dat",
         "build/gen/italic_font.dat"]
WINDOW_WIDTH = 208
MIN_BALANCED_WIDTH = WINDOW_WIDTH * 2 // 3  # a balanced sentence keeps lines this wide: no "Rydia a / été avalée"
LINE_WIDTHS = (208, 208, 208, 200)  # the fourth line leaves room for the page-turn arrow
WINDOW = Window(WINDOW_WIDTH, len(LINE_WIDTHS), line_widths=dict(enumerate(LINE_WIDTHS)))
NEW_WINDOW = "[new]"
ONE_TAIL = 0.5  # one sentence ending on a line under half full per window: two read as holes (in game)
FORCE_NEW = "[force_new]"  # an editor's window turn: kept, the speaker set again
LINE_BREAK = "[br]"  # an editor's line turn (TeX's \\): kept; `~` is a space no line breaks at
CENTER = "[center]"  # opens a message whose lines are centred: code FA, a blank glyph a pixel wide
ENDS = ("[end]", "[close_window]")
SPEAKER = re.compile(r"((?:Dr\.\s+)?\w+(?:'\w+)?(?:\s+\w+(?:'\w+)?)*):")  # "Yang's wife:", "Dr. Lugeie:" too
_IN_MESSAGE = r"(?!\[end\]|\[close_window\])"  # a quote never runs past its message


@dataclass(frozen=True)
class Quoting:
    """A language's quoted speech: the whole quote, and its opening mark, which cuts a sentence even unclosed."""

    quote: re.Pattern[str]
    opener: re.Pattern[str]


QUOTING = {
    "fr": Quoting(re.compile(rf"«(?:{_IN_MESSAGE}[^»])*»"), re.compile("«")),
    "en": Quoting(  # 'It's me!': apostrophes inside a word stay in the quote
        re.compile(rf"'(?:{_IN_MESSAGE}(?:[^']|(?<=[A-Za-z])'(?=[A-Za-z])))*'(?![A-Za-z])"), re.compile("'(?=[A-Z])")
    ),
}
ANNOUNCEMENT = re.compile(r"\[force_bold\][^\[]*[.!?]\s*\[force_normal\]")  # its punctuation inside: not a bold word
ANNOUNCED = re.compile(r"\[force_bold\][^\[]*\[force_normal\]")  # an announcement as laid out, padding and all
CONTROL = re.compile(r"\[[^\]]*\]")
LAYOUT_MARKUP = ("[bold]", "[normal]", "[book]", "[wicked]")
MARKUP = Markup(
    tag=r"\[[^\]]*\]",  # every ff4 tag: font switches, waits, terminators, raw codes
    glyphs=r"\[0x[0-9a-f]+\]",  # a raw code draws a glyph: a mark after it stays tight
    speakers=True,  # no space before the colon of "Beigan:" opening a line
)


ABBREVIATIONS = {"fr": ("M.",), "en": ("Mr.", "Mrs.", "Dr.", "St.", "Mt.")}
"""Words ending in a period that never end a sentence: a title stays with the name ("M. Rosa"), and a line never
ends on one."""
SPEAKER_SPACE = "°"  # the 1px spacer (FD): "Soldat°:", a hint of the French space before the colon, not a 3px gap
THIN_SPACE = "°"  # the same spacer before ? ! ; : as the French narrow no-break space: "Tue-moi°!", never a break
FRENCH_DIALOG = replace(FRENCH, speaker_space=SPEAKER_SPACE, thin_space=THIN_SPACE,
                        short_words=FRENCH_ONE_LETTER_WORDS)
TYPOGRAPHY = {"fr": FRENCH_DIALOG, "en": ENGLISH}


@dataclass(frozen=True)
class Token:
    kind: str  # SPEAKER, QUOTE, ANNOUNCEMENT, SENTENCE, END, BREAK
    value: str


RESUMED_ELLIPSIS = re.compile(r"^(\.\.\.+)(?=[^\W\d_])", re.MULTILINE)
"""An ellipsis opening a source line, glued to the word after it ("...Te souviens-tu"): katsuji leaves it glued
there as resumed speech, but spaces it mid-line, where the next layout reads it."""


def clean(text: str) -> str:
    """`text` without the markup a layout adds, so laying it out again changes nothing."""
    cleaned = text.replace(NEW_WINDOW, "\n")
    for tag in LAYOUT_MARKUP:
        cleaned = cleaned.replace(tag, "")
    cleaned = cleaned.replace(SPEAKER_SPACE + ":", ":")
    cleaned = _uncentred(cleaned)
    return re.sub(r"(?<=\w-)\n(?=\w)", "", cleaned)  # a word a layout broke at its hyphen


def _uncentred(text: str) -> str:
    """`text` without the padding a layout set before centred lines: an announcement's, and those of a `[center]`
    message's opening run, up to its first speaker."""
    text = ANNOUNCED.sub(lambda m: _unpadded(m[0]), text)
    parts = re.split(r"(\[end\]|\[close_window\])", text)
    return "".join(_unpadded_run(part) if part.lstrip().startswith(CENTER) else part for part in parts)


def _unpadded_run(message: str) -> str:
    speaker = re.search(r"^\[bold\]", message, re.MULTILINE)
    cut = speaker.start() if speaker else len(message)
    return _unpadded(message[:cut]) + message[cut:]


def _unpadded(text: str) -> str:
    """Each line of `text` without the run of spaces and spacers after its opening tags."""
    return re.sub(rf"^((?:\[[^\]]*\])*)[ {SPEAKER_SPACE}]+", r"\1", text, flags=re.MULTILINE)


def tokenize(text: str, quoting: Quoting = QUOTING["fr"], abbreviations: tuple[str, ...] = ("M.",)) -> list[Token]:
    text = re.sub(r"\s+", " ", text.strip())
    tokens: list[Token] = []
    i = 0
    while i < len(text):
        if text[i].isspace():
            i += 1
            continue
        end = next((e for e in ENDS if text.startswith(e, i)), None)
        if text.startswith(FORCE_NEW, i):
            tokens.append(Token("PAGE", ""))
            i += len(FORCE_NEW)
        elif text.startswith(LINE_BREAK, i):
            tokens.append(Token("LINE", ""))
            i += len(LINE_BREAK)
        elif end:
            tokens.append(Token("END", end))
            i += len(end)
        elif quoted := _quote_at(text, i, quoting.quote):
            tokens.append(Token("QUOTE", quoted.group(0)))
            i = quoted.end()
        elif announcement := ANNOUNCEMENT.match(text, i):
            tokens.append(Token("ANNOUNCEMENT", announcement.group(0)))
            i = announcement.end()
        elif speaker := SPEAKER.match(text, i):
            tokens.append(Token("SPEAKER", speaker.group(1)))
            i = speaker.end()
            while i < len(text) and text[i] in ": ":
                i += 1
        else:
            sentence, i = _sentence(text, i, quoting, abbreviations)
            if sentence.strip():
                tokens.append(Token("SENTENCE", sentence.strip()))
    return tokens


def _quote_at(text: str, i: int, mark: re.Pattern[str]) -> re.Match[str] | None:
    """`mark` (a quote or its opener) at `i`, at the start of a word."""
    return mark.match(text, i) if i == 0 or not text[i - 1].isalnum() else None


def _interrupts(text: str, i: int, quoting: Quoting) -> bool:
    """A quote cuts in where a sentence could end: 'Dear' inside one stays put."""
    return (
        (bool(_quote_at(text, i, quoting.opener)) and text[:i].rstrip()[-1:] in (".", "!", "?", "]", ""))
        or bool(SPEAKER.match(text, i))
        or bool(ANNOUNCEMENT.match(text, i))
        or any(text.startswith(e, i) for e in (*ENDS, FORCE_NEW, LINE_BREAK))
    )


def _sentence(text: str, i: int, quoting: Quoting, abbreviations: tuple[str, ...]) -> tuple[str, int]:
    sentence = ""
    while i < len(text):
        if sentence.strip() and _interrupts(text, i, quoting):
            break
        char = text[i]
        sentence += char
        i += 1
        if char not in ".!?" or (char == "." and sentence.endswith(abbreviations)):
            continue
        if i >= len(text) or any(text.startswith(e, i) for e in ENDS):
            break
        if text[i] == "[" and not text.startswith((FORCE_NEW, LINE_BREAK), i) and (close := text.find("]", i)) != -1:
            sentence += text[i : close + 1]
            i = close + 1
            continue
        if text[i].isspace():
            ahead = i
            while ahead < len(text) and text[ahead].isspace():
                ahead += 1
            if ahead < len(text) and (text[ahead].isupper() or _interrupts(text, ahead, quoting)):
                break
        elif SPEAKER.match(text, i):
            break
    return sentence, i


def _quote_sentences(quoted: str, quoting: Quoting, abbreviations: tuple[str, ...]) -> list[str]:
    """A quote cut into its sentences, the marks kept on the first and last, so a long quote turns windows
    between sentences rather than inside one."""
    inner = quoted[1:-1].strip()
    sentences: list[str] = []
    i = 0
    while i < len(inner):
        sentence, i = _sentence(inner, i, quoting, abbreviations)
        if sentence.strip():
            sentences.append(sentence.strip())
    if not sentences:
        return [quoted]
    sentences[0] = quoted[0] + sentences[0]
    sentences[-1] += quoted[-1]
    return sentences


def _control_only(text: str) -> bool:
    return not CONTROL.sub("", text).strip()


def with_breaks(tokens: Sequence[Token]) -> list[Token]:
    """A break after a quote followed by more speech, and before a quote answering a speaker; one on either side of
    an announcement."""
    out: list[Token] = []
    speaking = False
    for index, token in enumerate(tokens):
        if token.kind == "ANNOUNCEMENT" and out and out[-1].kind not in ("BREAK", "END"):
            out.append(Token("BREAK", ""))
        out.append(token)
        if token.kind == "ANNOUNCEMENT":
            following = tokens[index + 1] if index + 1 < len(tokens) else None
            if following is not None and following.kind != "END" and not (
                following.kind == "SENTENCE" and _control_only(following.value)
            ):
                out.append(Token("BREAK", ""))
            speaking = False
            continue
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


class _Paragraphs:
    """A message's tokens cut into the paragraphs katsuji pours into windows: a speaker's sentences, narration, a
    quote, an announcement; a break or a speaker change opens a window."""

    def __init__(self, quoting: Quoting, abbreviations: tuple[str, ...]) -> None:
        self.quoting = quoting
        self.abbreviations = abbreviations
        self.paragraphs: list[tuple[str, bool, list[str]]] = []  # lead, opens a window, sentences
        self.open = False  # the last paragraph takes the next sentence
        self.new_window = False  # the next paragraph opens a window
        self.speaker: str | None = None

    def token(self, token: Token) -> None:
        if token.kind == "BREAK":
            self.close(new_window=True)
        elif token.kind == "PAGE":
            if self.paragraphs:  # kept in the output, so a second layout turns there again
                self.append(FORCE_NEW)
            self.open = False
            self.new_window = True
        elif token.kind == "LINE":
            if self.paragraphs:  # the line ends there; the paragraph goes on below it
                self.append(LINE_BREAK)
        elif token.kind == "SPEAKER":
            self.close(new_window=self.speaker is not None)
            self.speaker = f"[bold]{token.value}[normal]"
        elif token.kind == "SENTENCE" and _control_only(token.value) and self.paragraphs:
            self.append(token.value)
        elif token.kind == "SENTENCE":
            self.sentence(token.value)
        elif token.kind == "QUOTE":
            self.close()
            self.whole(_quote_sentences(token.value, self.quoting, self.abbreviations))
        else:  # ANNOUNCEMENT
            self.close()
            self.whole([token.value])

    def sentence(self, sentence: str) -> None:
        if self.open:
            self.paragraphs[-1][2].append(sentence)
            return
        lead = f"{self.speaker}: " if self.speaker else ""
        self.paragraphs.append((lead, self.new_window, [sentence]))
        self.new_window = False
        self.open = True

    def whole(self, sentences: list[str]) -> None:
        """A paragraph no other voice runs on into: a quote, an announcement."""
        self.paragraphs.append(("", self.new_window, sentences))
        self.new_window = False
        self.close()

    def append(self, text: str) -> None:
        """`text` (control tags) at the end of the last sentence."""
        self.paragraphs[-1][2][-1] += text

    def close(self, new_window: bool = False) -> None:
        """End the open paragraph: the next sentence starts a new one, with no speaker."""
        self.open = False
        self.speaker = None
        self.new_window = self.new_window or new_window

    def result(self) -> list[Paragraph]:
        return [Paragraph(sentences, lead, opens) for lead, opens, sentences in self.paragraphs]


def messages(tokens: Sequence[Token]) -> list[tuple[list[Token], str]]:
    """`tokens` cut into messages, each with the terminators closing it (`[close_window][end]`): each message is
    laid out on its own, its terminators set after its last line."""
    out: list[tuple[list[Token], str]] = []
    body: list[Token] = []
    for token in tokens:
        if token.kind != "END":
            body.append(token)
        elif body or not out:
            out.append((body, token.value))
            body = []
        else:  # a terminator right after another closes the same message
            out[-1] = (out[-1][0], out[-1][1] + token.value)
    if body:
        out.append((body, ""))
    return out


class DialogLayout:
    """Lays one dialog pointer out into ff4 windows: ff4's script rules cut it into paragraphs, katsuji pours them
    into windows."""

    def __init__(self, metrics: TextMetrics, typography: Typography = FRENCH_DIALOG,
                 abbreviations: tuple[str, ...] = ABBREVIATIONS["fr"], quoting: Quoting = QUOTING["fr"]) -> None:
        self.metrics = metrics
        self.quoting = quoting
        self.abbreviations = abbreviations
        self.text_layout = TextLayout(
            self.measure,
            WINDOW_WIDTH,
            typography,
            MARKUP,
            abbreviations=abbreviations,
            measure_after=self._measure_after,
            min_balanced_width=MIN_BALANCED_WIDTH,
            line_breaks=(LINE_BREAK,),
            fill=True,  # full lines read on, phrases on lines of their own chop the reading (blind test)
        )
        self._font_after = lru_cache(maxsize=16384)(self._font_after_uncached)

    def measure(self, line: str, font: int = 0) -> int:
        # The table knows `[force_new]` only with its newline: bare, it would be measured as the letters "force_new".
        return self.metrics.measure_string(line.replace(FORCE_NEW, "").replace(LINE_BREAK, ""), font)

    def _measure_after(self, line: str, before: str) -> int:
        """`line` measured in the font in use after `before`, the message laid out ahead of it."""
        return self.measure(line, self._font_after(before))

    def _centred(self, laid: list[list[str]], opening: bool) -> list[list[str]]:
        """System messages centred: with `opening` (`[center]`), the message's opening run up to its first speaker;
        and every window an announcement opens. Each line is padded to the middle of the window with the spaces and
        spacers of the font in use there, after the tags opening the line (`[center]`, a font)."""
        out: list[list[str]] = []
        before, centring = "", opening
        for lines in laid:
            window = []
            announced = bool(lines) and lines[0].startswith("[force_bold]")
            for line in lines:
                centring = centring and not line.startswith("[bold]")
                if centring or announced:
                    line = self._centre(line, before)
                window.append(line)
                before = f"{before}\n{line}" if before else line
            out.append(window)
        return out

    def _centre(self, line: str, before: str) -> str:
        opening = re.match(r"(?:\[[^\]]*\] ?)*", line)[0]
        tags, words = opening.replace("] ", "]").rstrip(), line[len(opening) :]
        ahead = f"{before}\n{tags}" if before else tags
        font = self._font_after(ahead) if ahead else 0
        space, spacer = self.measure(" ", font), self.measure(SPEAKER_SPACE, font)
        used = self.measure(tags, self._font_after(before) if before else 0) + self.measure(words, font)
        room = max(0, (WINDOW_WIDTH - used) // 2)
        return tags + " " * (room // space) + SPEAKER_SPACE * (room % space // spacer) + words

    def _font_after_uncached(self, before: str) -> int:
        """The font in use after `before`: after its last line, started in the font its other lines leave, each
        of those cached, so a message is walked once however often its lines are measured."""
        head, _, last = before.rpartition("\n")
        return self.metrics.font_after(last, self._font_after(head) if head else 0)

    def layout(self, text: str) -> str:
        """`text` laid out: `[new]` where a window must turn, sentences packed onto 4-line windows."""
        if not text:
            return text
        # Sentences are cut on the text as typeset ("...Si" spaced to "... Si"), the text a second layout reads.
        # The source's lines are not the window's: an ellipsis opening one is spaced as it would be mid-line.
        unlined = RESUMED_ELLIPSIS.sub(r"\1 ", clean(text))
        typeset_text = clean(typeset(unlined, self.text_layout.typography, MARKUP))
        tokens = with_breaks(tokenize(typeset_text, self.quoting, self.abbreviations))
        return "\n".join(self._message(body, ends) for body, ends in messages(tokens))

    def _message(self, tokens: Sequence[Token], ends: str) -> str:
        """One message laid out from the dialog font, `ends` (its terminators) after its last line."""
        paragraphs = _Paragraphs(self.quoting, self.abbreviations)
        for token in tokens:
            paragraphs.token(token)
        laid = windows(self.text_layout, paragraphs.result(), WINDOW, one_tail=ONE_TAIL)
        laid = self._centred(laid, bool(tokens) and tokens[0].value.startswith(CENTER))
        text = f"{NEW_WINDOW}\n".join("\n".join(lines) for lines in laid) + ends
        text = re.sub(re.escape(LINE_BREAK) + r"(?!\n)", "", text)  # a line break a window turn or an end makes moot
        return text.replace(FORCE_NEW + NEW_WINDOW, FORCE_NEW)


def dialog_layout(lang: str = "fr") -> DialogLayout:
    table = Table(str(TABLE))
    return DialogLayout(TextMetrics(table, FONTS), TYPOGRAPHY[lang], ABBREVIATIONS[lang], QUOTING[lang])


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
