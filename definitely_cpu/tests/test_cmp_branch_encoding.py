import sys
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
sys.path.insert(0, str(TOOLS))

import asm as assembler
import isa_config


class CmpBranchEncodingTest(unittest.TestCase):
    def test_cmp_writes_signed_compare_result_to_r5(self):
        words = assembler.assemble(["CMP r5, r8, r9\n"])
        expected_cmp = isa_config.encode_type1(
            isa_config.T1_OPS["CMP"],
            0,
            8,
            0,
            9,
            5,
        )
        self.assertEqual(words[0], expected_cmp)

    def test_cmp_rejects_a_destination_other_than_r5(self):
        with self.assertRaisesRegex(ValueError, "must write.*r5"):
            assembler.assemble_line("CMP r6, r8, r9", 0, {})

    def test_relative_conditional_branches_use_label_offsets(self):
        for mnemonic in ("JZ", "JNZ", "JLT", "JGT"):
            with self.subTest(mnemonic=mnemonic):
                words = assembler.assemble(
                    [
                        f"{mnemonic} target\n",
                        "LI r8, #99\n",
                        "target:\n",
                        "HALT\n",
                    ]
                )
                expected_branch = isa_config.encode_type2(
                    isa_config.T2_OPS[mnemonic],
                    0,
                    0,
                    2,
                )
                self.assertEqual(words[0], expected_branch)

    def test_backward_conditional_branch_encodes_negative_offset(self):
        words = assembler.assemble(
            [
                "loop:\n",
                "LI r8, #1\n",
                "JNZ loop\n",
            ]
        )
        expected_branch = isa_config.encode_type2(
            isa_config.T2_OPS["JNZ"],
            0,
            0,
            0xFFFF,
        )
        self.assertEqual(words[1], expected_branch)

    def test_absolute_conditional_branch_sets_ri_bit(self):
        words = assembler.assemble(["JGT #12\n"])
        expected_branch = isa_config.encode_type2(
            isa_config.T2_OPS["JGT"],
            1,
            0,
            12,
        )
        self.assertEqual(words[0], expected_branch)


if __name__ == "__main__":
    unittest.main()
