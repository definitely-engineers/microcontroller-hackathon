import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "tools" / "isa_config.py"

spec = importlib.util.spec_from_file_location("isa_config", CONFIG_PATH)
isa_config = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(isa_config)


class MovEncodingTest(unittest.TestCase):
    def test_mov_r10_r8(self):
        encoded = isa_config.encode_type1(
            isa_config.T1_OPS["MOV"],
            0,
            8,
            0,
            0,
            10,
        )
        self.assertEqual(encoded, 0x801E400A)

    def test_mov_r11_imm17(self):
        encoded = isa_config.encode_type1(
            isa_config.T1_OPS["MOV"],
            1,
            17,
            0,
            0,
            11,
        )
        self.assertEqual(encoded, 0x801F880B)


if __name__ == "__main__":
    unittest.main()
