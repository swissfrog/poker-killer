"""Load bundled, open-source 6-max cash opening ranges."""

import json
from functools import lru_cache
from pathlib import Path

POSITIONS = ("LJ", "HJ", "CO", "BTN", "SB")
DATA_FILE = Path(__file__).resolve().parent / "data" / "ranges" / "Cash_100_GTO.json"


@lru_cache(maxsize=6)
def opening_range(position):
    """Return the 100bb 6-max GTO open frequency for each starting hand."""
    if position not in POSITIONS:
        raise ValueError("Unbekannte 6-max-Position: {}".format(position))
    try:
        data = json.loads(DATA_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError("Das mitgelieferte Range-Set konnte nicht geladen werden: {}".format(exc))
    result = data.get("Open" + position)
    if not isinstance(result, dict):
        raise ValueError("Im Range-Set fehlt Open{}.".format(position))
    return {hand: float(frequency) for hand, frequency in result.items()
            if float(frequency) > 0.0}
