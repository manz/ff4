import unittest
from pathlib import Path

from script import Table
from utils.smallvwf import VwfAsset


class VwfRendererTestCase(unittest.TestCase):
    def test_render(self):
        table = Table("./text/ff4_menus.tbl")
        vwf = VwfAsset("./fonts/8x8vwf.png", table)
        strings = []
        # with open("./text/fr/monsters.xml", encoding='utf-8') as datasource:
        #     tree = ElementTree.parse(datasource)
        #     root = tree.getroot()
        #
        #     for child in root:
        #         text = child.text
        #         if text:
        #             strings.append(text)

        strings = [
            "Objets",
            "Magie",
            "Equiper",
            "Statut",
            "Placer",
            "Changer",
            "Options",
            "Sauver",
        ]

        vwf.set_strings(strings)

        vwf.render()
        renderd = Path("./renderd.bin")
        serialized = vwf.serialize()

        renderd.write_bytes(serialized)
