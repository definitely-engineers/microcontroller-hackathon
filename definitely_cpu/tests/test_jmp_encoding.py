import sys
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
sys.path.insert(0, str(TOOLS))

import asm as assembler
import isa_config


class JmpEncodingTest(unittest.TestCase):
    def test_forward_label_uses_pc_relative_offset(self):
        words = assembler.assemble(
            [
                "LI r8, #1\n",
                "JMP skip\n",
                "LI r8, #99\n",
                "skip:\n",
                "LI r9, #7\n",
                "HALT\n",
            ]
        )

        expected_jmp = isa_config.encode_type2(
            isa_config.T2_OPS["JMP"],
            0,
            0,
            2,
        )
        self.assertEqual(words[1], expected_jmp)

    def test_backward_label_encodes_negative_offset(self):
        words = assembler.assemble(
            [
                "loop:\n",
                "ADD r8, r8, #1\n",
                "JMP loop\n",
            ]
        )

        expected_jmp = isa_config.encode_type2(
            isa_config.T2_OPS["JMP"],
            0,
            0,
            0xFFFF,
        )
        self.assertEqual(words[1], expected_jmp)

    def test_absolute_address_sets_ri_bit(self):
        words = assembler.assemble(["JMP #6\n"])
        expected_jmp = isa_config.encode_type2(
            isa_config.T2_OPS["JMP"],
            1,
            0,
            6,
        )
        self.assertEqual(words[0], expected_jmp)


if __name__ == "__main__":
    unittest.main()
