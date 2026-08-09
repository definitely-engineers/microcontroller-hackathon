import sys
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
sys.path.insert(0, str(TOOLS))

import asm as assembler
import isa_config


class PushPopEncodingTest(unittest.TestCase):
    def test_push_encodes_source_register(self):
        words = assembler.assemble(["PUSH r8\n"])
        expected = isa_config.encode_type2(
            isa_config.T2_OPS["PUSH"], 0, 8, 0
        )
        self.assertEqual(words, [expected])

    def test_pop_encodes_destination_register(self):
        words = assembler.assemble(["POP r9\n"])
        expected = isa_config.encode_type2(
            isa_config.T2_OPS["POP"], 0, 9, 0
        )
        self.assertEqual(words, [expected])


if __name__ == "__main__":
    unittest.main()
