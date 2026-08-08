import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "tools" / "isa_config.py"

spec = importlib.util.spec_from_file_location("isa_config", CONFIG_PATH)
isa_config = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(isa_config)


class SubEncodingTest(unittest.TestCase):
    def test_sub_r10_r8_r9(self):
        encoded = isa_config.encode_type1(
            isa_config.T1_OPS["SUB"],
            0,
            8,
            0,
            9,
            10,
        )
        self.assertEqual(encoded, 0x8002412A)

    def test_sub_r11_r8_imm5(self):
        encoded = isa_config.encode_type1(
            isa_config.T1_OPS["SUB"],
            0,
            8,
            1,
            5,
            11,
        )
        self.assertEqual(encoded, 0x800244AB)


if __name__ == "__main__":
    unittest.main()
