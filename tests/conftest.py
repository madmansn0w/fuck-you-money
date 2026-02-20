"""Pytest configuration: ensure src is on path when running tests from repo root."""

import sys
from pathlib import Path

_root = Path(__file__).resolve().parents[1]
_src = _root / "src"
if _src.is_dir() and str(_root) not in sys.path:
    sys.path.insert(0, str(_src))
