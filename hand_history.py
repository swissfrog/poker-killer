"""Lokale, begrenzte Historie stabil erkannter Poker-Hände."""

import json
from datetime import datetime
from pathlib import Path


class HandHistory:
    """Speichert erkannte Karten-Zustände zur späteren Ansicht."""

    def __init__(self, path="hand_history.json", max_entries=500, stable_frames=4):
        self.path = Path(path)
        self.max_entries = max_entries
        self.stable_frames = stable_frames
        self.entries = self._load()
        self._pending_signature = None
        self._pending_count = 0
        self._last_saved_signature = self._signature_from_entry(self.entries[-1]) if self.entries else None

    def _load(self):
        if not self.path.exists():
            return []
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
            return data if isinstance(data, list) else []
        except (OSError, json.JSONDecodeError):
            return []

    @staticmethod
    def _signature_from_entry(entry):
        return (tuple(entry.get("player_cards", [])),
                tuple(entry.get("community_cards", [])),
                entry.get("pot_size", 0),
                entry.get("current_bet", 0),
                entry.get("recommendation", ""))

    def observe(self, player_cards, community_cards, pot_size, current_bet, recommendation):
        """Speichert einen Zustand erst nach mehreren identischen Kamerabildern."""
        if len(player_cards) < 2:
            self._pending_signature = None
            self._pending_count = 0
            return False

        signature = (
            tuple(str(card) for card in player_cards),
            tuple(str(card) for card in community_cards),
            float(pot_size),
            float(current_bet),
            recommendation or "",
        )
        if signature != self._pending_signature:
            self._pending_signature = signature
            self._pending_count = 1
            return False

        self._pending_count += 1
        if self._pending_count < self.stable_frames or signature == self._last_saved_signature:
            return False

        entry = {
            "number": (self.entries[-1].get("number", 0) if self.entries else 0) + 1,
            "recorded_at": datetime.now().astimezone().isoformat(timespec="seconds"),
            "player_cards": list(signature[0]),
            "community_cards": list(signature[1]),
            "pot_size": signature[2],
            "current_bet": signature[3],
            "recommendation": signature[4],
        }
        self.entries.append(entry)
        self.entries = self.entries[-self.max_entries:]
        self._last_saved_signature = signature
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            temporary_path = self.path.with_suffix(self.path.suffix + ".tmp")
            temporary_path.write_text(
                json.dumps(self.entries, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
            temporary_path.replace(self.path)
        except OSError as exc:
            self.entries.pop()
            self._last_saved_signature = None
            print("Hand-History konnte nicht gespeichert werden: {}".format(exc))
            return False
        return True

    def print_recent(self, limit=10):
        """Zeigt die letzten gespeicherten Zustände im Terminal."""
        if not self.entries:
            print("Noch keine Hände in der Hand-History.")
            return
        for entry in self.entries[-limit:]:
            date = entry.get("recorded_at", "Zeit unbekannt")
            cards = " ".join(entry.get("player_cards", []))
            board = " ".join(entry.get("community_cards", [])) or "kein Board erkannt"
            recommendation = entry.get("recommendation", "keine Empfehlung")
            print("#{} | {} | {} | Board: {} | {}".format(
                entry.get("number", "?"), date, cards, board, recommendation
            ))
