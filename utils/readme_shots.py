#!/usr/bin/env python3
"""Regenerate the README screenshots, or the lab site's gallery, from the test savestates.

Each scene boots the freshly built patch, either cold or from a kintsuki
savestate, replays a short input script and saves the picture. The README
ones go 2x nearest-neighbour upscaled under `screenshots/`; with
`--gallery DIR`, the gallery ones go at 256x224 under their `ff4-*` names.
Run after `make build`.
"""
from __future__ import annotations

import argparse
import ctypes
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from katsuji import png
from kintsuki import Button, Emu
from kintsuki._native import lib

REPO = Path(__file__).resolve().parents[1]
ROM = REPO / "build" / "ff4.sfc"
SAVESTATES = REPO / "tests" / "savestates"
OUT = REPO / "screenshots"
SCALE = 2
# kintsuki pads the 256x224 picture with ares' letterbox border.
PICTURE = (13, 9, 13 + 256, 9 + 224)
# SRAM bank $71 holds only the patch's own state; a savestate carries an older build's, so it is zeroed as a boot would.
PATCH_SRAM = range(0x710000, 0x718000)


@dataclass(frozen=True)
class Scene:
    """One screenshot: a savestate, frames to settle, then inputs.

    Each step is a button name to tap, `"BUTTON:N"` to hold it N frames,
    `"*N"` to idle N frames, or `"@ADDR=VALUE"` (hex) to write a byte.
    `name` is its README file, `gallery` its lab gallery file; either may be None.
    """

    name: str | None
    kss: str | None
    settle: int = 60
    steps: list[str] = field(default_factory=list)
    gap: int = 20
    gallery: str | None = None


# Savestates freeze whatever an older build already drew: a menu saved
# open keeps its old text, and battle inventories are built at battle
# start. So menus open live and battles start live, from the world map.
FIELD = "ff4-before-field-inventory.kss"
# A save room late in the game: the whole party, Rydia's summons, no encounters.
LATE = "ff4-late-field.kss"
# Cold boot: START through the title, then A through the Red Wings intro,
# one press every 3 seconds, stopping on a three-line soldier's line.
INTRO = [
    step
    for i in range(58)
    for step in ["*60", *(["START" if i < 12 else "A"] if i % 3 == 0 and i < 57 else [])]
]
FRESH_BATTLE = ["B", *(["LEFT:40", "RIGHT:40"] * 3), "LEFT:40", "*500"]
# The savestate stands on the map: X opens the field menu.
MENU = ["X", "*60"]
# ff4.kss: into the sand worm fight, up to Edward's command menu.
DESERT = ["A", "A", "*400"]
# Two Mech Soldiers ($1800) from the late save room once $0685 is set, up to the first command menu.
LATE_BATTLE = ["@7E1800=85", "@7E1801=0", "@7E0685=1", "*600"]


def first_slot(item: int) -> list[str]:
    """Five of `item` in the first inventory slot ($7E:1440)."""
    return [f"@7E1440={item:X}", "@7E1441=5"]


SCENES = [
    Scene("battle-menu", FIELD, steps=FRESH_BATTLE, gallery="ff4-battle-menu"),
    # Edward attacks the sand worm: "Désorienté !" shows 135-225 frames later.
    Scene("battle-messages-vwf", "ff4.kss", 10, [*DESERT, "A", "A", "*140"], gallery="ff4-battle-message"),
    Scene("battle-items", FIELD, steps=[*FRESH_BATTLE, "DOWN", "DOWN", "DOWN", "A"], gallery="ff4-battle"),
    Scene("two-columns-magic", FIELD, steps=[*FRESH_BATTLE, "DOWN", "A", "*30"], gallery="ff4-magic"),
    Scene("dialog-vwf", None, 0, INTRO, gap=0, gallery="ff4-dialog"),
    Scene("key-item-picker", "ff4-key-inventory.kss", steps=["A", "A", "*60"], gap=30, gallery="ff4-key-items"),
    Scene("main-menu", FIELD, steps=MENU, gallery="ff4-main-menu"),
    Scene("load-save-menu", FIELD, steps=[*MENU, "UP", "A", "*60"], gallery="ff4-saves"),
    Scene("menu-description-vwf", FIELD, steps=[*MENU, "A", "*60", "DOWN"], gallery="ff4-items"),
    Scene("field-inventory-scroll", FIELD, steps=[*MENU, "A", "*60", *(["DOWN"] * 14)]),
    Scene("shop-sell", "ff4-buggy-item-shop-press-a.kss", steps=["RIGHT", "A"], gap=40, gallery="ff4-shop"),
    Scene("drops", "ff4-before-battle-inventory.kss", settle=600, gallery="ff4-loot"),
    Scene(None, FIELD, steps=[*MENU, "DOWN", "DOWN", "A", "*60", "A", "*120"], gallery="ff4-equip"),
    Scene(None, "ff4-fat-chocobo.kss", 30, ["A", "*40", "A", "*40"], gallery="ff4-chocobo"),
    # A Phoenix Down on Cain, alive: the refusal shows for a few frames.
    Scene(None, LATE, 10, [*first_slot(0xD4), *MENU, "A", "*40", "A", "*10", "A", "*40", "A:6"],
          gallery="ff4-refusal"),
    Scene(None, LATE, 10, [*MENU, *(["DOWN"] * 6), "A", "*60"], gallery="ff4-options"),
    # Rydia's magic: Rituel, then down to Chimère.
    Scene(None, LATE, 10, [*MENU, "DOWN", "A", "*40", *(["DOWN"] * 3), "A", "*60", "DOWN", "*40"],
          gallery="ff4-summons"),
    Scene(None, LATE, 10, [*first_slot(0xC0), *MENU, "A", "*90"], gallery="ff4-item-description"),
    Scene(None, LATE, 10, ["@7E16B3=1", *LATE_BATTLE], gallery="ff4-atb-gauge"),
    # Edward and Rydia attack, Rosa prays: the dark knight Cecil's turn.
    Scene(None, "ff4.kss", 10, [*DESERT, "A", "A", "*400", "A", "A", "*400", "DOWN", "DOWN", "A", "*30", "A", "*600"],
          gallery="ff4-vague-noire"),
    # Sauver on a save point, the first slot, Oui.
    Scene(None, LATE, 10, [*MENU, "@7E1A02=1", *(["DOWN"] * 7), "A", "*70", "A", "*70", "A", "*30"],
          gallery="ff4-save-message"),
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
    emu.write_range(PATCH_SRAM.start, bytes(len(PATCH_SRAM)))
    return emu


def play(emu: Emu, scene: Scene) -> None:
    emu.run_frames(scene.settle)
    for step in scene.steps:
        if step.startswith("*"):
            emu.run_frames(int(step[1:]))
            continue
        if step.startswith("@"):
            address, _, value = step[1:].partition("=")
            emu.write(int(address, 16), int(value, 16))
            continue
        name, _, hold = step.partition(":")
        button = getattr(Button, name)
        emu.press(0, button)
        emu.run_frames(int(hold) if hold else 6)
        emu.release(0, button)
        if not hold:
            emu.run_frames(scene.gap)
    emu.run_frames(20)


def capture(scene: Scene, path: Path, scale: int) -> Path:
    emu = load(SAVESTATES / scene.kss if scene.kss else None)
    try:
        play(emu, scene)
        if emu.get_state().stp:
            raise RuntimeError(f"{path.stem}: CPU halted")
        emu.screenshot(str(path))
    finally:
        emu.close()
    pixels, _ = png.read(path)
    left, top, right, bottom = PICTURE
    picture = pixels[top:bottom, left:right]
    png.write(path, np.ascontiguousarray(picture.repeat(scale, axis=0).repeat(scale, axis=1)))
    return path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--gallery", type=Path, help="write the lab gallery's 256x224 shots here instead")
    args = parser.parse_args()
    if not ROM.exists():
        raise SystemExit(f"{ROM} missing; run `make build` first")
    out = args.gallery or OUT
    out.mkdir(parents=True, exist_ok=True)
    for scene in SCENES:
        name = scene.gallery if args.gallery else scene.name
        if name:
            print(capture(scene, out / f"{name}.png", 1 if args.gallery else SCALE))


if __name__ == "__main__":
    main()
