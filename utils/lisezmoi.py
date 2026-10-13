"""
The release LISEZMOI with its version and date filled in: `@VERSION@` and `@DATE@` ("Octobre 2026", the month of the
last commit, so a rebuild gives the same file).

    uv run python -m utils.lisezmoi release/LISEZMOI.txt v1.0.0b0 > dist/LISEZMOI.txt
"""

from __future__ import annotations

import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

MONTHS = ("Janvier", "Février", "Mars", "Avril", "Mai", "Juin", "Juillet", "Août", "Septembre", "Octobre",
          "Novembre", "Décembre")


def french_month(when: datetime) -> str:
    return f"{MONTHS[when.month - 1]} {when.year}"


def fill(template: str, version: str, when: datetime) -> str:
    return template.replace("@VERSION@", version).replace("@DATE@", french_month(when))


def _last_commit() -> datetime:
    stamp = subprocess.run(["git", "log", "-1", "--format=%ct"], capture_output=True, text=True, check=True).stdout
    return datetime.fromtimestamp(int(stamp), UTC)


def main() -> None:
    template, version = Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[2]
    sys.stdout.write(fill(template, version, _last_commit()))


if __name__ == "__main__":
    main()
