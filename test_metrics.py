from pathlib import Path

import pytest
from script import Table

from metrics import TextMetrics


@pytest.fixture
def text_metrics() -> TextMetrics:
    length_table = Path("assets/font_length_table.dat").read_bytes()
    table = Table("text/ff4fr.tbl")
    text_metrics = TextMetrics(table, [length_table])
    return text_metrics


def test_metrics_work(text_metrics: TextMetrics) -> None:
    pixel_width = text_metrics.measure_bytes(text_metrics.table.to_bytes("ManZ"))

    assert pixel_width > 0


def test_metrics_line_count(text_metrics: TextMetrics) -> None:
    line_count = text_metrics.measure_line_count("ManZ ManZ ManZ", 26)

    assert line_count == 4


def test_word_wrap(text_metrics: TextMetrics) -> None:
    # wrapped = text_metrics.word_warp("T[end]T[end]T[end]T[end]T[end]T[end]T[end]T[end]T[end]T[end]Le trésor de Baron est entreposé ici! C'est interdit![end]",200)
    assert (
        text_metrics.word_warp(
            "Soldat: Capitaine Cecil, nous approchons de Baron!", 200
        )
        == "Soldat: Capitaine Cecil, nous\napprochons de Baron!"
    )


def test_metrics_line_count_real(text_metrics: TextMetrics) -> None:
    assert (
        text_metrics.measure_line_count(
            "Cecil: Votre Majesté, nous ne comprenons pas vos intentions.", 200
        )
        == 2
    )
    assert (
        text_metrics.measure_line_count(
            "Pourquoi avez-vous besoin de ces cristaux?", 200
        )
        == 2
    )
    assert (
        text_metrics.measure_line_count(
            "Était-ce parce que les Mythidiens représentaient une menace?", 200
        )
        == 2
    )
    assert (
        text_metrics.measure_line_count("Alors pourquoi n'ont-ils pas résisté?", 200)
        == 1
    )
    assert (
        text_metrics.measure_line_count(
            "Nous ne comprenons pas pourquoi des innocents ont dû périr.[end]", 200
        )
        == 2
    )
