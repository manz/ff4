"""Make `_ff4kintsuki` importable from sibling test modules without
requiring tests/ to be a package on every Python pathing setup."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))


def pytest_sessionfinish(session, exitstatus):
    """After every pytest run, regenerate tests/goldens/index.html — a
    flat gallery showing every golden / actual / diff / prev image
    side-by-side so reviewers can eyeball regressions without firing
    up an emulator."""
    from html import escape

    goldens_root = Path(__file__).parent / "goldens"
    if not goldens_root.exists():
        return

    cards: list[str] = []
    for golden in sorted(goldens_root.rglob("*.png")):
        name = golden.name
        if name.endswith((".actual.png", ".diff.png", ".prev.png")):
            continue
        rel = golden.relative_to(goldens_root)
        stem = golden.with_suffix("")
        actual = stem.with_suffix(".actual.png")
        diff = stem.with_suffix(".diff.png")
        prev = stem.with_suffix(".prev.png")

        def cell(label: str, path: Path) -> str:
            if not path.exists():
                return f'<figure><figcaption>{label}</figcaption><div class="missing">none</div></figure>'
            r = path.relative_to(goldens_root)
            return (
                f'<figure><figcaption>{label}</figcaption>'
                f'<a href="{escape(str(r))}"><img src="{escape(str(r))}" alt="{escape(path.name)}" loading="lazy"></a>'
                f"</figure>"
            )

        cards.append(
            f"""
        <article class="card">
          <header class="name">{escape(str(rel))}</header>
          <div class="grid">
            {cell('golden', golden)}
            {cell('actual', actual)}
            {cell('diff', diff)}
            {cell('prev', prev)}
          </div>
        </article>"""
        )

    html = f"""<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>FF4 goldens</title>
<style>
  :root {{ color-scheme: dark; }}
  * {{ box-sizing: border-box; }}
  body {{ font-family: -apple-system, system-ui, sans-serif; background: #1e1e1e; color: #eee;
          margin: 0; padding: max(env(safe-area-inset-top), 0.75rem) 0.75rem 1rem; }}
  h1 {{ font-size: 1.1rem; margin: 0 0 0.5rem; }}
  p.summary {{ margin: 0 0 1rem; color: #aaa; font-size: 0.85rem; }}
  .cards {{ display: grid; gap: 0.75rem;
            grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); }}
  .card {{ background: #262626; border: 1px solid #333; border-radius: 8px;
            padding: 0.5rem; }}
  .card .name {{ font-family: ui-monospace, Menlo, monospace; font-size: 0.8rem;
                  word-break: break-all; padding-bottom: 0.4rem;
                  border-bottom: 1px solid #333; margin-bottom: 0.5rem; }}
  .grid {{ display: grid; grid-template-columns: repeat(2, 1fr); gap: 0.4rem; }}
  figure {{ margin: 0; }}
  figcaption {{ font-size: 0.7rem; color: #999; text-transform: uppercase;
                 letter-spacing: 0.05em; margin-bottom: 0.2rem; }}
  img {{ width: 100%; height: auto; image-rendering: pixelated;
          display: block; border: 1px solid #1a1a1a; background: #000; }}
  a {{ display: block; }}
  .missing {{ color: #555; font-style: italic; font-size: 0.75rem;
               border: 1px dashed #333; padding: 1rem; text-align: center;
               border-radius: 4px; }}
  @media (max-width: 480px) {{
    .cards {{ grid-template-columns: 1fr; }}
    body {{ padding-left: 0.5rem; padding-right: 0.5rem; }}
  }}
</style></head><body>
<h1>FF4 golden gallery</h1>
<p class="summary">{len(cards)} golden(s). exit={exitstatus}. Tap any thumbnail to open the full PNG.</p>
<div class="cards">{"".join(cards)}</div>
</body></html>
"""
    (goldens_root / "index.html").write_text(html, encoding="utf-8")
