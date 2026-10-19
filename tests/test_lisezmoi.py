"""The release readmes get the tag and the month in their language."""
from __future__ import annotations

from datetime import UTC, datetime

from utils.lisezmoi import fill, month


def test_the_month_is_french() -> None:
    assert month(datetime(2026, 8, 1, tzinfo=UTC)) == "Août 2026"


def test_the_english_month() -> None:
    assert month(datetime(2026, 8, 1, tzinfo=UTC), "en") == "August 2026"


def test_every_placeholder_is_filled() -> None:
    text = fill("@DATE@ @VERSION@ @VERSION@", "v1.0.0b0", datetime(2026, 10, 13, tzinfo=UTC))
    assert text == "Octobre 2026 v1.0.0b0 v1.0.0b0"
