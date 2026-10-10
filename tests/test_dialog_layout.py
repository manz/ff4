"""ff4's dialog layout (utils/dialog_layout.py): window rules, French typography, pages the engine can show."""

import re

import pytest

from utils.dialog_layout import LINE_WIDTHS, NEW_WINDOW, DialogLayout, dialog_layout


@pytest.fixture(scope="module")
def layout() -> DialogLayout:
    return dialog_layout()


def windows(text: str) -> list[list[str]]:
    """The windows of a laid-out message: the lines between two `[new]`."""
    return [[line for line in window.split("\n") if line] for window in text.split(NEW_WINDOW)]


def test_a_speaker_is_set_in_bold_with_french_spacing(layout: DialogLayout) -> None:
    assert layout.layout("Cecil: Comment!?[end]") == "[bold]Cecil[normal]: Comment !?[end]"


def test_a_speaker_change_turns_the_window(layout: DialogLayout) -> None:
    assert layout.layout("Soldat: Mais, Capitaine! Cecil: Écoutez![end]") == (
        "[bold]Soldat[normal]: Mais, Capitaine ![new]\n[bold]Cecil[normal]: Écoutez ![end]"
    )


def test_narration_runs_on_into_a_speaker_on_a_new_line(layout: DialogLayout) -> None:
    out = layout.layout("La porte s'ouvre. Cecil: Allons-y![end]")
    assert out == "La porte s'ouvre.\n[bold]Cecil[normal]: Allons-y ![end]"


def test_sentences_share_a_line_while_they_fit(layout: DialogLayout) -> None:
    assert layout.layout("Beigan: Ah! Vous avez le Cristal![end]") == (
        "[bold]Beigan[normal]: Ah ! Vous avez le Cristal ![end]"
    )


def test_a_quote_answering_a_speaker_gets_its_own_window(layout: DialogLayout) -> None:
    out = layout.layout("Cecil: Qui est là? «Je suis votre guide pour l'enfer...»[end]")
    assert out == "[bold]Cecil[normal]: Qui est là ?[new]\n« Je suis votre guide pour l'enfer... »[end]"


def test_a_long_quote_turns_windows_between_its_sentences(layout: DialogLayout) -> None:
    quote = (
        "«Je suis l'un des quatre Empereurs de seigneur Golbez... Scarmiglione de la Terre... "
        "Il est temps que dînent mes précieux morts-vivants!»[end]"
    )
    for window in layout.layout(quote).split(NEW_WINDOW):
        assert re.search(r"(\.\.\.|!|») ?(\[end\])?$", window.strip()), window


def test_m_dot_stays_with_the_name_inside_a_line(layout: DialogLayout) -> None:
    out = layout.layout("Cecil: Bonjour M. Rosa, comment allez-vous? Nous devons partir maintenant.[end]")
    assert "M. Rosa" in out


def test_m_dot_stays_with_the_name_when_a_sentence_breaks(layout: DialogLayout) -> None:
    out = layout.layout("Porom: Vous êtes M. Cecil, n'est-ce pas?[end]")
    assert "M. Cecil" in out
    assert not any(line.endswith("M.") for line in out.split("\n"))


def test_every_window_fits_the_page(layout: DialogLayout) -> None:
    text = "Tellah: " + " ".join(
        [
            "Je ne suis pas en mesure de vaincre quelqu'un d'aussi puissant que lui avec la magie dont je dispose.",
            "Je recherchais la légendaire magie scellée, Météor...",
            "Et j'ai senti une forte aura émise de cette montagne.",
            "Serait-ce possible, après toutes ces années de recherches..?",
        ]
    ) + "[end]"
    for window in windows(layout.layout(text)):
        assert len(window) <= len(LINE_WIDTHS)
        assert all(layout.measure(line) <= width for line, width in zip(window, LINE_WIDTHS, strict=False))


def test_messages_in_one_pointer_stay_separate(layout: DialogLayout) -> None:
    assert layout.layout("T[end]\nT[end]") == "T[end]\nT[end]"


def test_markup_a_layout_added_is_ignored(layout: DialogLayout) -> None:
    raw = "Soldat: Mais, Capitaine! Cecil: Écoutez![end]"
    authored = "[bold]Soldat[normal]: Mais, Capitaine![new]\n[bold]Cecil[normal]: Écoutez![end]"
    assert layout.layout(authored) == layout.layout(raw)


def test_control_codes_take_no_width(layout: DialogLayout) -> None:
    line = "Le Moine Yang a rejoint le groupe !"
    assert layout.measure(line + "[music][0x29][delay][0x28][close_window]") == layout.measure(line)


BOOK = 2  # [force_book]: font index


def test_a_font_switch_holds_across_lines_and_windows(layout: DialogLayout) -> None:
    """A `[force_book]` narration is wrapped to the book font on every line, not only the one carrying the tag."""
    narration = " ".join(["Le pays de Baron devint la plus forte puissance militaire au monde par leurs aéronefs."] * 3)
    font = 0
    for window in windows(layout.layout(f"[force_book]{narration}[end]")):
        for line, width in zip(window, LINE_WIDTHS, strict=False):
            assert layout.measure(line, font) <= width, line
            font = layout.metrics.font_after(line, font)
    assert font == BOOK


def test_each_message_starts_in_the_dialog_font(layout: DialogLayout) -> None:
    long_line = "Le pays de Baron devint la plus forte puissance militaire au monde"
    out = layout.layout(f"[force_book]Ainsi.[end]\n{long_line}[end]")
    assert out.split("\n", 1)[1] == layout.layout(f"{long_line}[end]")
