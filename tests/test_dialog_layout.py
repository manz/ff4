"""ff4's dialog layout (utils/dialog_layout.py): window rules, French and English typography, pages the engine can show."""

import re
from pathlib import Path

import pytest

from utils.dialog_layout import LINE_WIDTHS, NEW_WINDOW, DialogLayout, dialog_layout


@pytest.fixture(scope="module")
def layout() -> DialogLayout:
    return dialog_layout()


def windows(text: str) -> list[list[str]]:
    """The windows of a laid-out message: the lines between two `[new]`."""
    return [[line for line in window.split("\n") if line] for window in text.split(NEW_WINDOW)]


def test_a_speaker_is_set_in_bold_with_french_spacing(layout: DialogLayout) -> None:
    assert layout.layout("Cecil: Comment!?[end]") == "[bold]Cecil[normal]°: Comment°!?[end]"


def test_english_sets_no_space_before_marks() -> None:
    assert dialog_layout("en").layout("Cecil: What!? Mr. Cid![end]") == "[bold]Cecil[normal]: What!? Mr. Cid![end]"


def test_a_speaker_change_turns_the_window(layout: DialogLayout) -> None:
    assert layout.layout("Soldat: Mais, Capitaine! Cecil: Écoutez![end]") == (
        "[bold]Soldat[normal]°: Mais, Capitaine°![new]\n[bold]Cecil[normal]°: Écoutez°![end]"
    )


def test_a_hand_placed_new_window_is_laid_out_again(layout: DialogLayout) -> None:
    assert layout.layout("Cecil: Allons-y![new] Partons![end]") == "[bold]Cecil[normal]°: Allons-y°! Partons°![end]"


def test_a_forced_window_turns_and_sets_the_speaker_again(layout: DialogLayout) -> None:
    assert layout.layout("Roi Baron: Vraiment?![force_new] Tu pars demain![end]") == (
        "[bold]Roi Baron[normal]°: Vraiment°?![force_new]\n[bold]Roi Baron[normal]°: Tu pars demain°![end]"
    )


def test_a_forced_window_in_narration_survives_a_second_layout(layout: DialogLayout) -> None:
    once = layout.layout("Les cristaux luisaient.[force_new] Le vent tomba.[end]")
    assert layout.layout(once) == once


def test_a_forced_window_survives_a_second_layout(layout: DialogLayout) -> None:
    once = layout.layout("Roi Baron: Vraiment?![force_new] Tu pars demain![end]")
    assert layout.layout(once) == once


def test_narration_runs_on_into_a_speaker_on_a_new_line(layout: DialogLayout) -> None:
    out = layout.layout("La porte s'ouvre. Cecil: Allons-y![end]")
    assert out == "La porte s'ouvre.\n[bold]Cecil[normal]°: Allons-y°![end]"


def test_sentences_share_a_line_while_they_fit(layout: DialogLayout) -> None:
    assert layout.layout("Beigan: Ah! Vous avez le Cristal![end]") == (
        "[bold]Beigan[normal]°: Ah°! Vous avez le Cristal°![end]"
    )


def test_a_quote_answering_a_speaker_gets_its_own_window(layout: DialogLayout) -> None:
    out = layout.layout("Cecil: Qui est là? «Je suis votre guide pour l'enfer...»[end]")
    assert out == "[bold]Cecil[normal]°: Qui est là°?[new]\n« Je suis votre guide pour l'enfer... »[end]"


def test_a_long_quote_turns_windows_between_its_sentences(layout: DialogLayout) -> None:
    quote = (
        "«Je suis l'un des quatre Empereurs de seigneur Golbez... Scarmiglione de la Terre... "
        "Il est temps que dînent mes précieux morts-vivants!»[end]"
    )
    for window in layout.layout(quote).split(NEW_WINDOW):
        assert re.search(r"(\.\.\.|!|») ?(\[end\])?$", window.strip()), window


def test_a_sentence_fills_its_first_line(layout: DialogLayout) -> None:
    """A sentence just over a line fills the first: "Yang: Rydia a été avalée / par Léviathan.", not balanced to
    "Yang: Rydia a / été avalée par Léviathan."."""
    out = layout.layout("Yang: Rydia a été avalée par Léviathan.[end]")
    assert windows(out)[0][0] == "[bold]Yang[normal]°: Rydia a été avalée"


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
        lines = [line.removesuffix("[end]") for line in window]  # the engine draws nothing once it ends
        assert all(layout.measure(line) <= width for line, width in zip(lines, LINE_WIDTHS, strict=False))


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


def test_an_announcement_gets_its_own_window(layout: DialogLayout) -> None:
    """A whole sentence in [force_bold] (a party join) is not the speaker's: it doesn't share their window."""
    out = layout.layout("Cecil: Merci... Rydia. [force_bold]L'invocatrice Rydia se joint à toi![force_normal][end]")
    assert out == (
        "[bold]Cecil[normal]°: Merci... Rydia.[new]\n[force_bold]L'invocatrice Rydia\nse joint à toi°![force_normal][end]"
    )


def test_a_bold_word_stays_in_its_sentence(layout: DialogLayout) -> None:
    out = layout.layout("Garde: Prends ça! [force_bold]Crapaud[force_normal]![end]")
    assert NEW_WINDOW not in out


def test_a_speaker_name_keeps_its_apostrophe() -> None:
    assert dialog_layout("en").layout("Yang's wife: Dear![end]") == "[bold]Yang's wife[normal]: Dear![end]"


def test_an_english_quote_gets_its_own_window() -> None:
    out = dialog_layout("en").layout("Cecil: Who's there? 'It's your guide to Hell...'[end]")
    assert out == "[bold]Cecil[normal]: Who's there?[new]\n'It's your guide to Hell...'[end]"


def test_a_word_broken_at_its_hyphen_joins_again() -> None:
    assert "single-handedly" in dialog_layout("en").layout("Edge: I did it single-\nhandedly![end]")


def test_mt_stays_with_the_name() -> None:
    out = dialog_layout("en").layout("Elder: Go east of here and climb Mt. Ordeals, far beyond the sea and sand.[end]")
    assert not any(line.endswith("Mt.") for line in out.split("\n"))


def test_an_unclosed_quote_stops_at_its_message(layout: DialogLayout) -> None:
    out = layout.layout("«Wahaha![end]Cecil: Halte![end]«Fin!»[end]")
    assert out == "« Wahaha°![end]\n[bold]Cecil[normal]°: Halte°![end]\n« Fin°! »[end]"


def test_a_quoted_word_stays_in_its_sentence() -> None:
    out = dialog_layout("en").layout("Yang: Stop calling me 'Dear'...![end]")
    assert out == "[bold]Yang[normal]: Stop calling me 'Dear'...![end]"


def test_a_titled_speaker_keeps_the_title() -> None:
    assert dialog_layout("en").layout("Dr. Lugeie: Grr...[end]") == "[bold]Dr. Lugeie[normal]: Grr...[end]"


def test_a_french_speaker_takes_the_1px_spacer_before_the_colon_once(layout: DialogLayout) -> None:
    laid = layout.layout("Cecil: Comment!?[end]")
    assert (laid, layout.layout(laid)) == ("[bold]Cecil[normal]°: Comment°!?[end]",) * 2


def test_an_ellipsis_opening_a_source_line_lays_out_as_it_reads_mid_line(layout: DialogLayout) -> None:
    """ "...Te" opens a line of the script but sits mid-line once laid out: it is spaced either way, so laying
    the text out again changes nothing."""
    once = layout.layout("[bold]FuSoYa[normal]: ...Tu as recouvré tes esprits.\n...Te souviens-tu du nom de ton père?[end]")
    assert layout.layout(once) == once


@pytest.mark.parametrize("lang", ["fr", "en"])
def test_laying_the_script_out_again_changes_nothing(lang: str) -> None:
    lay = dialog_layout(lang)
    for path in sorted(Path(f"text/{lang}").glob("bank*.xml")):
        for pointer, body in re.findall(r'<sn:pointer id="(\d+)">(.*?)</sn:pointer>', path.read_text(encoding="utf-8"), re.S):
            once = lay.layout(body)
            assert lay.layout(once) == once, f"{path.stem}#{pointer}"
