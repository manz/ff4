"""The release LISEZMOI gets the tag and a French month."""
from __future__ import annotations

from datetime import UTC, datetime

from utils.lisezmoi import fill, french_month


def test_the_month_is_french() -> None:
    assert french_month(datetime(2026, 8, 1, tzinfo=UTC)) == "Août 2026"


def test_every_placeholder_is_filled() -> None:
    text = fill("@DATE@ @VERSION@ @VERSION@", "v1.0.0b0", datetime(2026, 10, 13, tzinfo=UTC))
    assert text == "Octobre 2026 v1.0.0b0 v1.0.0b0"
