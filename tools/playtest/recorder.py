"""One-click local playtest recorder. Start capture only after the user presses Record."""

from __future__ import annotations

import json
import os
from pathlib import Path
import queue
import threading
import tkinter as tk
from tkinter import messagebox, ttk

from capture import Capture, DATA, SESSIONS, ffmpeg_path, microphones, run, write_json
from review import process


class Recorder:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.capture = None
        self.busy = False
        self.closing = False
        self.messages = queue.Queue()
        self.latest = None
        root.title("Fallout Forecast · Playtest recorder")
        root.geometry("620x410")
        root.minsize(580, 400)
        root.configure(bg="#111d28")
        style = ttk.Style()
        style.theme_use("clam")
        style.configure("TFrame", background="#111d28")
        style.configure("TLabel", background="#111d28", foreground="#eceddf", font=("Segoe UI", 11))
        style.configure("TButton", font=("Segoe UI", 11), padding=10)
        style.configure("Title.TLabel", font=("Segoe UI Semibold", 22))
        frame = ttk.Frame(root, padding=24)
        frame.pack(fill="both", expand=True)
        ttk.Label(frame, text="Play. Talk. Mark the moment.", style="Title.TLabel").pack(anchor="w")
        ttk.Label(frame, text="Records the game window, game sound, and your microphone.").pack(anchor="w", pady=(8, 18))
        ttk.Label(frame, text="Microphone").pack(anchor="w")
        self.microphone = tk.StringVar()
        self.devices = ttk.Combobox(frame, textvariable=self.microphone, state="readonly")
        self.devices.pack(fill="x", pady=(6, 16))
        buttons = ttk.Frame(frame)
        buttons.pack(fill="x")
        self.start_button = ttk.Button(buttons, text="Record playtest", state="disabled", command=self.start)
        self.start_button.pack(side="left", padx=(0, 10))
        self.stop_button = ttk.Button(buttons, text="Finish recording", state="disabled", command=self.stop)
        self.stop_button.pack(side="left")
        ttk.Label(frame, text="F7 marks feedback + a screenshot. F12 finishes and saves.").pack(anchor="w", pady=(18, 6))
        self.status = tk.StringVar(value="Finding microphones…")
        ttk.Label(frame, textvariable=self.status, wraplength=560).pack(anchor="w", pady=(2, 12))
        links = ttk.Frame(frame)
        links.pack(side="bottom", fill="x")
        ttk.Button(links, text="Open latest review", command=self.open_review).pack(side="left")
        ttk.Button(links, text="Recordings folder", command=self.open_folder).pack(side="right")
        root.protocol("WM_DELETE_WINDOW", self.close)
        DATA.mkdir(parents=True, exist_ok=True)
        latest = SESSIONS / "latest.json"
        if latest.exists():
            try:
                self.latest = Path(json.loads(latest.read_text())["review"])
            except (OSError, ValueError, KeyError):
                pass
        threading.Thread(target=self.load_devices, daemon=True).start()
        root.after(100, self.poll)

    def emit(self, kind, value=None):
        self.messages.put((kind, value))

    def load_devices(self):
        try:
            found = microphones(ffmpeg_path())
            if not found:
                raise RuntimeError("No microphone found. Connect one, enable Windows microphone access, then reopen this launcher.")
            self.emit("devices", found)
        except Exception as error:
            self.emit("error", str(error))

    def poll(self):
        while not self.messages.empty():
            kind, value = self.messages.get_nowait()
            if kind == "devices":
                self.devices["values"] = value
                selected = value[0]
                config = DATA / "config.json"
                if config.exists():
                    try:
                        saved = json.loads(config.read_text())["microphone"]
                        if saved in value:
                            selected = saved
                    except (OSError, ValueError, KeyError):
                        pass
                self.microphone.set(selected)
                self.start_button["state"] = "normal"
                self.status.set("Ready. Your recordings and transcript stay on this PC.")
            elif kind == "status":
                self.status.set(value)
            elif kind == "recording":
                self.stop_button["state"] = "normal"
                self.status.set("Recording. Switch to the game and talk through what you notice.")
                self.root.iconify()
            elif kind in ("done", "error"):
                self.busy = False
                self.start_button["state"] = "normal" if self.microphone.get() else "disabled"
                self.stop_button["state"] = "disabled"
                self.devices["state"] = "readonly"
                self.root.deiconify()
                if kind == "done":
                    self.latest = value
                    self.status.set("Saved. The review includes video, voice feedback, markers, and game events.")
                    if not self.closing:
                        self.open_review()
                else:
                    self.status.set(value)
                    if not self.closing:
                        messagebox.showerror("Playtest recorder", value)
                if self.closing:
                    self.root.destroy()
                    return
        self.root.after(100, self.poll)

    def start(self):
        if self.busy or not self.microphone.get():
            return
        self.busy = True
        self.start_button["state"] = "disabled"
        self.devices["state"] = "disabled"
        self.status.set("Launching the game and connecting the recorder…")
        microphone = self.microphone.get()
        write_json(DATA / "config.json", {"microphone": microphone})
        threading.Thread(target=self.record, args=(microphone,), daemon=True).start()

    def record(self, microphone):
        try:
            self.capture = Capture(microphone, lambda text: self.emit("status", text))
            self.capture.start()
            if self.closing:
                self.capture.request_stop()
            self.emit("recording")
            folder = self.capture.wait()
            self.emit("status", "Recording saved. Preparing your review…")
            self.emit("done", process(folder, lambda text: self.emit("status", text)))
        except Exception as error:
            if self.capture:
                if self.capture.metadata.get("status") == "captured":
                    self.capture.metadata.update(status="review_failed", review_error=str(error))
                    write_json(self.capture.folder / "session.json", self.capture.metadata)
                else:
                    self.capture.abort()
            self.emit("error", str(error))
        finally:
            self.capture = None

    def stop(self):
        if self.capture:
            self.capture.request_stop()
            self.stop_button["state"] = "disabled"
            self.status.set("Saving the recording…")

    def open_review(self):
        if self.latest and self.latest.exists():
            os.startfile(self.latest)
        else:
            self.status.set("Finish a playtest to create your first review.")

    def open_folder(self):
        SESSIONS.mkdir(parents=True, exist_ok=True)
        os.startfile(SESSIONS)

    def close(self):
        if self.busy:
            self.closing = True
            self.stop()
            self.status.set("Finishing and saving before closing…")
        else:
            self.root.destroy()


if __name__ == "__main__":
    root = tk.Tk()
    Recorder(root)
    root.mainloop()
