import struct
import unicodedata

from script import Table

if __name__ == "__main__":
    table = Table("text/ff4_menus.tbl")
    accents = set()
    accents_mapping = {" ̀": b"\x8a", " ̈": b"\x8d", " ̂": b"\x8b", " ́": b"\x8c"}

    dakutens = [b"\x00\00"] * 256
    count = 0

    lowest = 0xFF
    highest = 0

    for key in table.lookup.keys():
        normalized = unicodedata.normalize("NFD", key).encode("utf-8")
        font_char = table.to_bytes(key)[0]

        if len(normalized) > len(key):
            if normalized[1] == 0xCC and normalized[2] != 0xA7:
                print(key)
                lookup_key = (b"\x20" + normalized[1:]).decode("utf-8")
                non_accentuated_char = table.to_bytes(normalized[:1].decode("utf-8"))

                lowest = min(lowest, font_char)
                highest = max(highest, font_char)
                dakutens[font_char] = accents_mapping[lookup_key] + non_accentuated_char
        count += 1
        # accents.add((b"\x20" + normalized[1:]).decode("utf-8"))
    # print((b"\x20" + normalized[1:]).decode("utf-8"))
    print(b"".join(dakutens[lowest:highest]))

    with open("assets/dakuten.bin", "wb") as f:
        f.write(struct.pack("<H", lowest))
        f.write(struct.pack("<H", highest + 1))
        f.write(b"".join(dakutens[lowest : highest + 1]))
