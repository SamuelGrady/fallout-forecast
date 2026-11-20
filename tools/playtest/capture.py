"""Windows game-window and microphone capture, with recoverable session files."""

from __future__ import annotations

import json
import ctypes
from ctypes import wintypes
import os
from pathlib import Path
import re
import shutil
import subprocess
import threading
import time
import uuid


ROOT = Path(__file__).resolve().parents[2]
DATA = Path(os.environ.get("LOCALAPPDATA", Path.home())) / "FalloutForecastPlaytest"
SESSIONS = Path.home() / "Videos" / "FalloutForecastPlaytests"
HIDDEN = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
if os.name == "nt":
    ctypes.windll.user32.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4))


def run(command, **kwargs):
    return subprocess.run(command, creationflags=HIDDEN, **kwargs)


def write_json(path: Path, value):
    temporary = path.with_name(path.name + "." + uuid.uuid4().hex + ".tmp")
    temporary.write_text(json.dumps(value, indent=2), encoding="utf-8")
    temporary.replace(path)


def ffmpeg_path() -> str:
    candidates = [os.environ.get("FFMPEG_EXE"), shutil.which("ffmpeg"), DATA / "bin" / "ffmpeg.exe"]
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return str(candidate)
    import imageio_ffmpeg

    return imageio_ffmpeg.get_ffmpeg_exe()


def microphones(ffmpeg: str) -> list[str]:
    result = run([ffmpeg, "-hide_banner", "-list_devices", "true", "-f", "dshow", "-i", "dummy"],
                 capture_output=True, encoding="utf-8", errors="replace", timeout=15)
    return re.findall(r'"(.+?)" \(audio\)', result.stderr)


def find_godot() -> str:
    configured = os.environ.get("GODOT_EXE")
    candidates = [configured, shutil.which("godot"), shutil.which("godot4")]
    candidates.extend(sorted((Path.home() / "Desktop").glob("Godot*_console.exe"), reverse=True))
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            executable = Path(candidate)
            # The console wrapper launches a different PID on Windows.
            gui = executable.with_name(executable.name.replace("_console", ""))
            return str(gui if gui.exists() else executable)
    raise RuntimeError("Set GODOT_EXE to your Godot console executable, then reopen the recorder.")


def game_window(pid: int):
    user32 = ctypes.windll.user32
    titles = []
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    user32.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
    user32.IsWindowVisible.argtypes = [wintypes.HWND]
    user32.EnumWindows.argtypes = [callback_type, wintypes.LPARAM]

    @callback_type
    def visit(window, _):
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(window, ctypes.byref(owner))
        if owner.value == pid and user32.IsWindowVisible(window):
            title = ctypes.create_unicode_buffer(1024)
            user32.GetWindowTextW(window, title, len(title))
            if title.value:
                titles.append((window, title.value))
        return True

    user32.EnumWindows(visit, 0)
    return titles[0] if titles else None


class Capture:
    def __init__(self, microphone: str, report):
        self.microphone = microphone
        self.report = report
        self.ffmpeg = ffmpeg_path()
        self.folder: Path | None = None
        self.game = None
        self.encoder = None
        self.voice = None
        self._capture_control = None
        self._frame_lock = threading.Lock()
        self._frame_ready = threading.Event()
        self._latest_frame = None
        self._writer = None
        self._writer_stop = threading.Event()
        self.started = 0.0
        self._ready = threading.Event()
        self._stop = threading.Event()
        self._logs = []
        self.metadata = {}

    def start(self):
        if not self.microphone:
            raise RuntimeError("Choose a microphone before recording.")
        SESSIONS.mkdir(parents=True, exist_ok=True)
        stamp = time.strftime("%Y-%m-%d_%H-%M-%S")
        self.folder = SESSIONS / f"{stamp}-{time.time_ns() % 100000:05d}"
        self.folder.mkdir()
        revision = run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True)
        changes = run(["git", "status", "--porcelain"], cwd=ROOT, capture_output=True, text=True)
        self.metadata = {"status": "starting", "created": stamp, "revision": revision.stdout.strip(),
                         "dirty": bool(changes.stdout.strip()), "microphone": self.microphone,
                         "capture": "game window + microphone; game mix captured inside Godot"}
        write_json(self.folder / "session.json", self.metadata)
        game_log = (self.folder / "process.log").open("w", encoding="utf-8")
        self._logs.append(game_log)
        self.game = subprocess.Popen(
            [find_godot(), "--path", str(ROOT), "--log-file", str(self.folder / "game.log"),
             "--", f"--playtest-session={self.folder}"],
            cwd=ROOT, stdout=game_log, stderr=subprocess.STDOUT, creationflags=HIDDEN,
        )
        ready = self.folder / "ready.json"
        deadline = time.monotonic() + 45
        while not ready.exists():
            if self.game.poll() is not None:
                raise RuntimeError(f"Game exited before capture was ready. See {self.folder / 'game.log'}")
            if self._stop.is_set() or time.monotonic() > deadline:
                self.request_stop()
                raise RuntimeError("Game startup was cancelled or timed out.")
            time.sleep(0.1)
        # Godot's root Window can append a debug suffix after autoload startup.
        # Resolve the visible window belonging to this exact launched process.
        deadline = time.monotonic() + 10
        window = game_window(self.game.pid)
        while not window and time.monotonic() < deadline:
            time.sleep(0.1)
            window = game_window(self.game.pid)
        if not window:
            raise RuntimeError("The game did not create a visible capture window.")
        window_handle, _ = window
        self._start_graphics_capture(window_handle)
        encoder_log = (self.folder / "capture.log").open("w", encoding="utf-8")
        self._logs.append(encoder_log)
        command = [
            self.ffmpeg, "-hide_banner", "-y",
            "-f", "rawvideo", "-pixel_format", "bgra", "-video_size", "960x720", "-framerate", "30", "-i", "pipe:0",
            "-c:v", "libx264", "-preset", "ultrafast", "-crf", "23", "-pix_fmt", "yuv420p",
            str(self.folder / "capture.mkv"),
        ]
        self.encoder = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                                        stderr=encoder_log, creationflags=HIDDEN)
        voice_log = (self.folder / "microphone.log").open("w", encoding="utf-8")
        self._logs.append(voice_log)
        self.voice = subprocess.Popen([
            self.ffmpeg, "-hide_banner", "-y", "-progress", "pipe:1", "-stats_period", "0.25",
            "-f", "dshow", "-audio_buffer_size", "50", "-i", f"audio={self.microphone}",
            "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", str(self.folder / "microphone.wav")],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=voice_log, text=True, creationflags=HIDDEN)
        self._writer = threading.Thread(target=self._write_frames, daemon=True)
        self._writer.start()
        threading.Thread(target=self._progress, daemon=True).start()
        deadline = time.monotonic() + 20
        while not self._ready.wait(0.1):
            if self.encoder.poll() is not None or self.voice.poll() is not None or time.monotonic() > deadline or self._stop.is_set():
                self.request_stop()
                raise RuntimeError(f"Video/microphone capture failed. Check the microphone and {self.folder / 'capture.log'}")
        self.metadata.update(status="recording", started_unix=self.started)
        write_json(self.folder / "capture.json", {"started_unix": self.started})
        write_json(self.folder / "session.json", self.metadata)
        self.report("Recording. F7 marks a moment. F12 finishes the playtest.")

    def _progress(self):
        try:
            for line in self.voice.stdout:
                key, _, value = line.strip().partition("=")
                if key == "out_time_us" and value != "N/A" and not self._ready.is_set():
                    self.metadata["microphone_start_unix"] = time.time() - max(0, int(value)) / 1_000_000
                    self._ready.set()
        except (ValueError, OSError):
            pass

    def _start_graphics_capture(self, window_handle):
        import cv2
        from windows_capture import WindowsCapture

        capture = WindowsCapture(cursor_capture=False, draw_border=True, minimum_update_interval=33,
                                 window_hwnd=window_handle)

        @capture.event
        def on_frame_arrived(frame, control):
            image = frame.frame_buffer
            # WGC includes the native title bar. Map client coordinates into its
            # extended frame bounds before encoding the fixed 4:3 client area.
            bounds = wintypes.RECT()
            client = wintypes.RECT()
            point = wintypes.POINT(0, 0)
            ctypes.windll.dwmapi.DwmGetWindowAttribute(wintypes.HWND(window_handle), 9,
                                                      ctypes.byref(bounds), ctypes.sizeof(bounds))
            ctypes.windll.user32.GetClientRect(wintypes.HWND(window_handle), ctypes.byref(client))
            ctypes.windll.user32.ClientToScreen(wintypes.HWND(window_handle), ctypes.byref(point))
            x, y = max(0, point.x - bounds.left), max(0, point.y - bounds.top)
            cropped = image[y:y + client.bottom, x:x + client.right]
            if cropped.size:
                packed = cv2.resize(cropped, (960, 720)).tobytes()
                with self._frame_lock:
                    self._latest_frame = packed
                self._frame_ready.set()

        @capture.event
        def on_closed():
            self._stop.set()

        self._capture_control = capture.start_free_threaded()
        # Retain the Python callback owner for the lifetime of the native thread.
        self._graphics_capture = capture
        if not self._frame_ready.wait(15):
            raise RuntimeError("Windows Graphics Capture did not receive game frames.")

    def _write_frames(self):
        self.started = time.time()
        deadline = time.monotonic()
        try:
            while not self._writer_stop.is_set():
                with self._frame_lock:
                    frame = self._latest_frame
                if frame:
                    self.encoder.stdin.write(frame)
                    self.encoder.stdin.flush()
                deadline += 1 / 30
                self._writer_stop.wait(max(0, deadline - time.monotonic()))
        except (OSError, ValueError):
            self._stop.set()

    def wait(self):
        while self.game.poll() is None and not self._stop.wait(0.2):
            if self.encoder.poll() is not None or self.voice.poll() is not None:
                self.request_stop()
                self.metadata["warning"] = "Encoder stopped unexpectedly. Review capture.log."
                break
        self.request_stop()
        try:
            self.game.wait(timeout=15)
        except subprocess.TimeoutExpired:
            self.metadata["warning"] = "Game did not acknowledge Stop. Capture is saved; close the game manually."
        self.close_encoder()
        self.metadata.update(status="captured", ended_unix=time.time())
        write_json(self.folder / "session.json", self.metadata)
        return self.folder

    def request_stop(self):
        self._stop.set()
        if self.folder:
            (self.folder / "stop.request").touch()

    def close_encoder(self):
        self._writer_stop.set()
        if self._capture_control:
            try:
                self._capture_control.stop()
            except RuntimeError:
                pass
            self._capture_control = None
        if self._writer:
            self._writer.join(timeout=5)
        if self.encoder and self.encoder.poll() is None:
            try:
                self.encoder.stdin.close()
                self.encoder.wait(timeout=12)
            except (OSError, subprocess.TimeoutExpired):
                self.encoder.terminate()
                self.encoder.wait(timeout=5)
        if self.voice and self.voice.poll() is None:
            try:
                self.voice.stdin.write("q\n")
                self.voice.stdin.flush()
                self.voice.wait(timeout=10)
            except (OSError, subprocess.TimeoutExpired):
                self.voice.terminate()
                self.voice.wait(timeout=5)
        for log in self._logs:
            log.close()
        self._logs.clear()

    def abort(self):
        self.request_stop()
        if self.game:
            try:
                self.game.wait(timeout=10)
            except subprocess.TimeoutExpired:
                pass
        self.close_encoder()
        if self.folder:
            self.metadata.update(status="capture_failed")
            write_json(self.folder / "session.json", self.metadata)
