"""Legacy entry point: rebuild the recorded contact bank, including body Foley.

The old oscillator/noise generator was replaced by audio/contact_foley/build_bank.py.
See that directory's CREDITS.md for sources and offline build dependencies.
"""
from pathlib import Path
import runpy

if __name__ == "__main__":
    runpy.run_path(str(Path(__file__).resolve().parents[1] / "contact_foley" / "build_bank.py"), run_name="__main__")
