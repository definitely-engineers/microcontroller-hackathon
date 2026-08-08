import sys
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
sys.path.insert(0, str(TOOLS))

import asm as assembler
import isa_config


class CallRetEncodingTest(unittest.TestCase):
    def test_relative_call_uses_pc_relative_offset(self):
        words = assembler.assemble(
            [
                "CALL target\n",
                "HALT\n",
                "target:\n",
                "RET\n",
            ]
        )
        expected_call = isa_config.encode_type2(
            isa_config.T2_OPS["CALL"],
            0,
            0,
            2,
        )
        self.assertEqual(words[0], expected_call)

    def test_absolute_call_sets_ri_bit(self):
        words = assembler.assemble(["CALL #9\n"])
        expected_call = isa_config.encode_type2(
            isa_config.T2_OPS["CALL"],
            1,
            0,
            9,
        )
        self.assertEqual(words[0], expected_call)

    def test_ret_has_no_operands(self):
        words = assembler.assemble(["RET\n"])
        expected_ret = isa_config.encode_type2(
            isa_config.T2_OPS["RET"],
            0,
            0,
            0,
        )
        self.assertEqual(words[0], expected_ret)


if __name__ == "__main__":
    unittest.main()
