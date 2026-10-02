#!/usr/bin/env python3
"""Regenerate the README screenshots from the test savestates.

Each scene boots the freshly built patch, either cold or from a kintsuki
savestate, replays a short input script and saves the picture, 2x
nearest-neighbour upscaled, under `screenshots/`. Run after `make build`.
"""
from __future__ import annotations

import ctypes
from dataclasses import dataclass, field
from pathlib import Path

from kintsuki import Button, Emu
from kintsuki._native import lib
from PIL import Image

REPO = Path(__file__).resolve().parents[1]
ROM = REPO / "build" / "ff4.sfc"
SAVESTATES = REPO / "tests" / "savestates"
OUT = REPO / "screenshots"
SCALE = 2
# kintsuki pads the 256x224 picture with ares' letterbox border.
PICTURE = (13, 9, 13 + 256, 9 + 224)


@dataclass(frozen=True)
class Scene:
    """One screenshot: a savestate, frames to settle, then inputs.

    Each step is a button name to tap, `"BUTTON:N"` to hold it N frames,
    or `"*N"` to idle N frames.
    """

    name: str
    kss: str | None
    settle: int = 60
    steps: list[str] = field(default_factory=list)
    gap: int = 20


# Savestates freeze whatever an older build already drew: a menu saved
# open keeps its old text, and battle inventories are built at battle
# start. So menus open live and battles start live, from the world map.
FIELD = "ff4-before-field-inventory.kss"
# Cold boot: START through the title, then A through the Red Wings intro,
# one press every 3 seconds, stopping on a three-line soldier's line.
INTRO = [
    step
    for i in range(58)
    for step in ["*60", *(["START" if i < 12 else "A"] if i % 3 == 0 and i < 57 else [])]
]
FRESH_BATTLE = ["B", *(["LEFT:40", "RIGHT:40"] * 3), "LEFT:40", "*200"]

SCENES = [
    Scene("battle-menu", FIELD, steps=FRESH_BATTLE),
    Scene("battle-messages-vwf", "ff4.kss", 10, ["A", "A", "*400", "A", "*30"]),
    Scene("battle-items", FIELD, steps=[*FRESH_BATTLE, "DOWN", "DOWN", "DOWN", "A"]),
    Scene("two-columns-magic", FIELD, steps=[*FRESH_BATTLE, "DOWN", "A", "*30"]),
    Scene("dialog-vwf", None, 0, INTRO, gap=0),
    Scene("key-item-picker", "ff4-key-inventory.kss", steps=["A", "A", "*60"], gap=30),
    Scene("main-menu", FIELD),
    Scene("load-save-menu", FIELD, steps=["UP", "A", "*60"]),
    Scene("menu-description-vwf", FIELD, steps=["A", "*60", "DOWN"]),
    Scene("field-inventory-scroll", FIELD, steps=["A", "*60", *(["DOWN"] * 14)]),
    Scene("shop-sell", "ff4-buggy-item-shop-press-a.kss", steps=["RIGHT", "A"], gap=40),
    Scene("drops", "ff4-before-battle-inventory.kss", settle=600),
]


def load(kss: Path | None) -> Emu:
    emu = Emu(load_srm_sidecar=False)
    emu.load_rom(str(ROM))
    if kss is None:
        return emu
    blob = kss.read_bytes()
    buf = (ctypes.c_uint8 * len(blob))(*blob)
    if lib.kintsuki_load_state(emu._handle, buf, len(blob)) != 1:
        raise RuntimeError(f"failed to load {kss.name}")
    return emu


def play(emu: Emu, scene: Scene) -> None:
    emu.run_frames(scene.settle)
    for step in scene.steps:
        if step.startswith("*"):
            emu.run_frames(int(step[1:]))
            continue
        name, _, hold = step.partition(":")
        button = getattr(Button, name)
        emu.press(0, button)
        emu.run_frames(int(hold) if hold else 6)
        emu.release(0, button)
        if not hold:
            emu.run_frames(scene.gap)
    emu.run_frames(20)


def capture(scene: Scene) -> Path:
    emu = load(SAVESTATES / scene.kss if scene.kss else None)
    try:
        play(emu, scene)
        if emu.get_state().stp:
            raise RuntimeError(f"{scene.name}: CPU halted")
        path = OUT / f"{scene.name}.png"
        emu.screenshot(str(path))
    finally:
        emu.close()
    image = Image.open(path).crop(PICTURE)
    image.resize((image.width * SCALE, image.height * SCALE), Image.Resampling.NEAREST).save(path)
    return path


def main() -> None:
    if not ROM.exists():
        raise SystemExit(f"{ROM} missing; run `make build` first")
    OUT.mkdir(exist_ok=True)
    for scene in SCENES:
        print(capture(scene).relative_to(REPO))


if __name__ == "__main__":
    main()
