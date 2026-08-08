import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "tools" / "isa_config.py"

spec = importlib.util.spec_from_file_location("isa_config", CONFIG_PATH)
isa_config = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(isa_config)


class AddEncodingTest(unittest.TestCase):
    def test_add_r10_r8_r9(self):
        encoded = isa_config.encode_type1(
            isa_config.T1_OPS["ADD"],
            0,
            8,
            0,
            9,
            10,
        )
        self.assertEqual(encoded, 0x8000412A)

    def test_li_operands(self):
        li_opcode = isa_config.T2_OPS["LI"]
        self.assertEqual(
            isa_config.encode_type2(li_opcode, 1, 8, 21),
            0x03680015,
        )
        self.assertEqual(
            isa_config.encode_type2(li_opcode, 1, 9, 21),
            0x03690015,
        )


if __name__ == "__main__":
    unittest.main()
