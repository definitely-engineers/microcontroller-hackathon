import sys
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
sys.path.insert(0, str(TOOLS))

import asm as assembler
import isa_config


class LoadStoreEncodingTest(unittest.TestCase):
    def assemble_one(self, source):
        return assembler.assemble_line(source, 0, {})

    def test_base_register_and_positive_offset_are_preserved(self):
        word = self.assemble_one("LOAD r8, [r30 + 4]")
        self.assertEqual(word, 0x0008F004)

        other_base = self.assemble_one("LOAD r8, [r29 + 4]")
        self.assertEqual(other_base, 0x0008E804)
        self.assertNotEqual(word, other_base)

    def test_sp_alias_and_negative_offset(self):
        word = self.assemble_one("STORE r9, [sp - 4]")
        self.assertEqual(word, 0x004917FC)

    def test_absolute_address_uses_full_low_16_bits(self):
        word = self.assemble_one("LOAD r8, [0x1234]")
        self.assertEqual(word, 0x00281234)

    def test_register_offset_boundaries(self):
        lower = self.assemble_one("LOAD r8, [r1 - 1024]")
        upper = self.assemble_one("LOAD r8, [r1 + 1023]")

        self.assertEqual(lower & 0xFFFF, 0x0C00)
        self.assertEqual(upper & 0xFFFF, 0x0BFF)

    def test_register_offset_out_of_range_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "must be -1024..1023"):
            self.assemble_one("LOAD r8, [r1 - 1025]")
        with self.assertRaisesRegex(ValueError, "must be -1024..1023"):
            self.assemble_one("LOAD r8, [r1 + 1024]")

    def test_absolute_address_boundaries(self):
        low = self.assemble_one("LOAD r8, [0]")
        high = self.assemble_one("LOAD r8, [0xFFFF]")

        self.assertEqual(low, 0x00280000)
        self.assertEqual(high, 0x0028FFFF)

    def test_absolute_address_out_of_range_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "must be 0-65535"):
            self.assemble_one("LOAD r8, [-1]")
        with self.assertRaisesRegex(ValueError, "must be 0-65535"):
            self.assemble_one("LOAD r8, [65536]")

    def test_all_memory_opcodes_use_the_same_payload_layout(self):
        cases = {
            "LOAD r10, [r3]": "LOAD",
            "STORE r10, [r3]": "STORE",
            "LOADB r10, [r3]": "LOADB",
            "STOREB r10, [r3]": "STOREB",
        }

        for source, mnemonic in cases.items():
            with self.subTest(source=source):
                expected = isa_config.encode_memory_type2(
                    isa_config.T2_OPS[mnemonic],
                    10,
                    base_reg=3,
                    offset=0,
                )
                self.assertEqual(self.assemble_one(source), expected)


if __name__ == "__main__":
    unittest.main()
