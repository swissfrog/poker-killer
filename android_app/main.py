"""Kivy Android UI for private, manual poker analysis."""

import json
from datetime import datetime
from pathlib import Path

from kivy.app import App
from kivy.clock import Clock
from kivy.metrics import dp
from kivy.platform import platform
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.button import Button
from kivy.uix.camera import Camera
from kivy.uix.gridlayout import GridLayout
from kivy.uix.label import Label
from kivy.uix.scrollview import ScrollView
from kivy.uix.slider import Slider
from kivy.uix.spinner import Spinner
from kivy.uix.textinput import TextInput

from poker_logic import PokerLogic
from android_app.card_input import validate_deal


class PokerKillerAndroidApp(App):
    title = "Poker Killer · privat"

    def build(self):
        self.logic = PokerLogic()
        self.pot_input = TextInput(text="100", hint_text="Pot", input_filter="float",
                                   multiline=False, size_hint_y=None, height=dp(48))
        self.call_input = TextInput(text="0", hint_text="Call-Betrag", input_filter="float",
                                    multiline=False, size_hint_y=None, height=dp(48))
        self.hole_input = TextInput(text="", hint_text="Hole Cards, z. B. As Kh",
                                    multiline=False, size_hint_y=None, height=dp(48))
        self.board_input = TextInput(text="", hint_text="Board, z. B. 2c 3d 4h",
                                     multiline=False, size_hint_y=None, height=dp(48))
        self.position = Spinner(text="BTN", values=("UTG", "MP", "CO", "BTN", "SB", "BB"),
                                 size_hint_y=None, height=dp(48))
        self.result = Label(text="Trage deine Karten ein und tippe auf „Auswerten“.",
                            size_hint_y=None, height=dp(120), halign="left", valign="middle")
        self.result.bind(size=lambda widget, size: setattr(widget, "text_size", (size[0], None)))
        self.camera_status = Label(text="Kamera ist aus. Vorschau wird nur lokal angezeigt.",
                                   size_hint_y=None, height=dp(32))
        self.camera = Camera(play=False, resolution=(640, 480), size_hint_y=None, height=dp(190))
        self.history_label = Label(text="", size_hint_y=None, height=dp(100), halign="left", valign="top")
        self.history_label.bind(size=lambda widget, size: setattr(widget, "text_size", (size[0], None)))

        root = BoxLayout(orientation="vertical", padding=dp(12), spacing=dp(8))
        scroll = ScrollView()
        content = BoxLayout(orientation="vertical", spacing=dp(8), size_hint_y=None)
        content.bind(minimum_height=content.setter("height"))

        content.add_widget(Label(text="[b]Poker Helper[/b]  ·  private Android-Version",
                                 markup=True, size_hint_y=None, height=dp(42)))
        content.add_widget(self.camera)
        camera_button = Button(text="Kamera-Vorschau ein/aus", size_hint_y=None, height=dp(44))
        camera_button.bind(on_release=self.toggle_camera)
        content.add_widget(camera_button)
        content.add_widget(self.camera_status)
        content.add_widget(self.hole_input)
        content.add_widget(self.board_input)

        money_row = BoxLayout(size_hint_y=None, height=dp(48), spacing=dp(8))
        money_row.add_widget(self.pot_input)
        money_row.add_widget(self.call_input)
        content.add_widget(money_row)
        content.add_widget(self.position)

        content.add_widget(Label(text="Vorgeschlagene Bet-Größe (Pot-Anteil)",
                                 size_hint_y=None, height=dp(30)))
        bet_row = BoxLayout(size_hint_y=None, height=dp(44), spacing=dp(5))
        self.bet_label = Label(text="Bet-Preset: —", size_hint_x=1.1)
        bet_row.add_widget(self.bet_label)
        for fraction, label in ((1 / 3, "1/3"), (1 / 2, "1/2"), (2 / 3, "2/3"), (1.0, "Pot")):
            button = Button(text=label)
            button.bind(on_release=lambda _button, f=fraction: self.set_bet_preset(f))
            bet_row.add_widget(button)
        content.add_widget(bet_row)

        content.add_widget(Label(text="Gegnerprofil (manuelle Schätzung)",
                                 size_hint_y=None, height=dp(30)))
        self.vpip_slider = Slider(min=0, max=100, value=25, size_hint_y=None, height=dp(38))
        self.pfr_slider = Slider(min=0, max=100, value=18, size_hint_y=None, height=dp(38))
        self.bluff_slider = Slider(min=0, max=100, value=25, size_hint_y=None, height=dp(38))
        self.profile_label = Label(text="", size_hint_y=None, height=dp(42))
        for label, slider in (("VPIP", self.vpip_slider), ("PFR", self.pfr_slider),
                              ("Bluff-Schätzung", self.bluff_slider)):
            row = BoxLayout(size_hint_y=None, height=dp(42), spacing=dp(6))
            row.add_widget(Label(text=label, size_hint_x=0.35))
            row.add_widget(slider)
            content.add_widget(row)
        self.vpip_slider.bind(value=self.update_profile)
        self.pfr_slider.bind(value=self.update_profile)
        self.bluff_slider.bind(value=self.update_profile)
        content.add_widget(self.profile_label)
        self.update_profile()

        analyze_button = Button(text="Hand auswerten", size_hint_y=None, height=dp(52))
        analyze_button.bind(on_release=self.analyze)
        content.add_widget(analyze_button)
        content.add_widget(self.result)
        content.add_widget(Label(text="Letzte Hände (lokal gespeichert)",
                                 size_hint_y=None, height=dp(30)))
        content.add_widget(self.history_label)
        self.refresh_history()
        scroll.add_widget(content)
        root.add_widget(scroll)
        return root

    def update_profile(self, *_args):
        vpip = int(self.vpip_slider.value)
        pfr = min(int(self.pfr_slider.value), vpip)
        self.pfr_slider.value = pfr
        style = "loose" if vpip >= 35 else "tight" if vpip < 20 else "mittel"
        aggression = "ausgeglichen" if vpip == 0 else (
            "aggressiv" if pfr / float(vpip) >= 0.65 else
            "passiv" if pfr / float(vpip) <= 0.35 else "ausgeglichen"
        )
        fish = " · moeglicherweise loose/passiv" if vpip >= 35 and aggression == "passiv" else ""
        self.profile_label.text = "VPIP {}% · PFR {}% · {} / {}{}".format(
            vpip, pfr, style, aggression, fish
        )

    def set_bet_preset(self, fraction):
        try:
            pot = max(0.0, float(self.pot_input.text.replace(",", ".")))
        except ValueError:
            self.result.text = "Bitte zuerst einen gültigen Pot eintragen."
            return
        self.bet_label.text = "Bet-Preset: {:.2f}".format(pot * fraction)

    def toggle_camera(self, *_args):
        if self.camera.play:
            self.camera.play = False
            self.camera_status.text = "Kamera ist aus."
            return
        if platform == "android":
            try:
                from android.permissions import Permission, request_permissions
                request_permissions([Permission.CAMERA], self._camera_permission_result)
            except Exception as exc:
                self.camera_status.text = "Kamerazugriff konnte nicht angefordert werden: {}".format(exc)
        else:
            self._start_camera()

    def _camera_permission_result(self, *args):
        results = args[-1] if args else []
        first = results[0] if isinstance(results, (list, tuple)) and results else None
        granted = first is True or first == 0
        Clock.schedule_once(lambda _dt: self._camera_result(granted), 0)

    def _camera_result(self, granted):
        if granted:
            self._start_camera()
        else:
            self.camera_status.text = "Kamerazugriff verweigert. Karten bitte manuell eintragen."

    def _start_camera(self):
        self.camera.play = True
        self.camera_status.text = "Lokale Vorschau; Kartenerkennung ist nicht aktiv."

    def analyze(self, *_args):
        try:
            hole, board = validate_deal(self.hole_input.text, self.board_input.text)
            pot = max(0.0, float(self.pot_input.text.replace(",", ".")))
            call = max(0.0, float(self.call_input.text.replace(",", ".")))
            category, _category_rank = self.logic.evaluate_hand(hole + board)
            action, reason = self.logic.recommend(hole, board, pot, call, self.position.text)
            equity, error = self.logic.calculate_equity(hole, board)
        except ValueError as exc:
            self.result.text = "Eingabe prüfen: {}".format(exc)
            return

        self.result.text = (
            "[b]Hand: {}[/b]\nEntscheidungshinweis: {}\n{}\n"
            "Equity gegen Zufallshand: {:.1f}% +/- {:.1f}%"
        ).format(category, action, reason, equity * 100, error * 100)
        self.save_history(hole, board, category, action, reason, pot, call)
        self.refresh_history()

    def _history_path(self):
        return Path(self.user_data_dir) / "hand_history.json"

    def save_history(self, hole, board, category, action, reason, pot, call):
        path = self._history_path()
        try:
            entries = json.loads(path.read_text(encoding="utf-8")) if path.exists() else []
            entries.append({
                "recorded_at": datetime.now().astimezone().isoformat(timespec="seconds"),
                "hole_cards": ["{}{}".format(rank, suit[0]) for rank, suit in hole],
                "board": ["{}{}".format(rank, suit[0]) for rank, suit in board],
                "category": category,
                "action": action,
                "reason": reason,
                "pot": pot,
                "call_amount": call,
            })
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(entries[-100:], ensure_ascii=False, indent=2), encoding="utf-8")
        except (OSError, json.JSONDecodeError) as exc:
            self.result.text += "\nVerlauf konnte nicht lokal gespeichert werden: {}".format(exc)

    def refresh_history(self):
        try:
            entries = json.loads(self._history_path().read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            entries = []
        lines = ["{} · {} · {}".format(
            entry.get("recorded_at", "")[:16],
            " ".join(entry.get("hole_cards", [])),
            entry.get("category", "")
        ) for entry in entries[-4:]]
        self.history_label.text = "\n".join(lines) if lines else "Noch keine gespeicherten Hände."
