"""Battle lines show the characters' current names: build.py encodes them as name codes ($04 n), like vanilla's,
so a renamed Caïn reads renamed in "Pourquoi, Caïn !?"."""
from __future__ import annotations

from pathlib import Path

from script import Table
from test_battle_message_text_pointer import _use_monsters

from _ff4kintsuki import assert_screenshot_matches_golden, kss_path, load_emu_from_kss
from build import SMALL_VWF_TABLE, battle_text_table


def test_a_name_is_its_name_code() -> None:
    table = battle_text_table(SMALL_VWF_TABLE, "text/ff4fr.tbl")
    assert table.to_bytes("Pourquoi, Caïn !?")[10:12] == bytes([0x04, 0x01])


def test_the_script_spellings_share_a_code() -> None:
    table = battle_text_table(SMALL_VWF_TABLE, "text/ff4fr.tbl")
    assert table.to_bytes("Tellah") == table.to_bytes("Tella") == bytes([0x04, 0x03])


SCRIPT_READ = 0x02BF4F  # btlgfx reads the next graphics-script command: lda ($3F)
SCRIPT_POINTER = 0x7E003F
SHOW_MESSAGE = 0xF8  # the Monsters item's first message command
SHOW_DIALOG = 0xF2  # a battle dialogue: the next byte is its battle_messages id
WHY_CAIN = 58  # "Pourquoi, Caïn !?"
CHAR_NAMES = 0x7E1500  # 6 menu-code bytes per name index
CAIN = 1
RENAMED = "Zorro"
GOLDEN = Path(__file__).parent / "goldens" / "battle_messages" / "renamed_cain.png"
MESSAGE_WINDOW = (0, 0, 256, 24)
SHOWN = 40  # frames from the swapped command to the dialogue on screen


def show_battle_dialog(emu, message: int, shown: int) -> bytes:
    """Have the Monsters item's battle script show battle dialogue `message`: its first message command becomes a
    dialogue command ($F2 id) when btlgfx reads it. The savestate `shown` frames later: the item's turn goes on well
    past the dialogue before the inventory helper returns."""
    state = {"at": None, "snapshot": None}

    def swap(*_) -> None:
        pointer = emu.read(SCRIPT_POINTER) | emu.read(SCRIPT_POINTER + 1) << 8
        if state["at"] is None and emu.read(0x7E0000 | pointer) == SHOW_MESSAGE:
            emu.write_range(0x7E0000 | pointer, bytes([SHOW_DIALOG, message]))
            state["at"] = emu.frame_count

    emu.add_exec_callback(SCRIPT_READ, SCRIPT_READ, swap)
    run_frames = emu.run_frames

    def frame_by_frame(frames: int) -> None:
        for _ in range(frames):
            run_frames(1)
            if state["snapshot"] is None and state["at"] is not None and emu.frame_count >= state["at"] + shown:
                state["snapshot"] = emu.save_state()

    emu.run_frames = frame_by_frame
    try:
        _use_monsters(emu)
        frame_by_frame(shown)
    finally:
        emu.run_frames = run_frames
    assert state["snapshot"] is not None, "the battle script never showed a message"
    return state["snapshot"]


def test_a_battle_line_draws_the_current_name() -> None:
    """Caïn renamed in RAM, battle dialogue 58 ("Pourquoi, Caïn !?") shown through the battle's own path: it reads
    the new name."""
    emu = load_emu_from_kss(kss_path("ff4-battle-monsters-item.kss"), settle_frames=10)
    try:
        emu.write_range(CHAR_NAMES + CAIN * 6, Table(SMALL_VWF_TABLE).to_bytes(RENAMED).ljust(6, b"\xff"))
        emu.load_state(show_battle_dialog(emu, WHY_CAIN, SHOWN - 1))
        emu.run_frames(1)  # the framebuffer keeps the last picture drawn until a frame runs
        assert_screenshot_matches_golden(emu, GOLDEN, region=MESSAGE_WINDOW)
    finally:
        emu.close()
