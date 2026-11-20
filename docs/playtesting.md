# Recorded playtests

Double-click `Playtest.cmd` in the repository, choose your microphone, then select **Record playtest**. The launcher starts a dedicated 960 by 720 game window and minimizes after capture connects. Recording begins only after you select Record.

Play normally and describe what you notice. **F7** adds a timestamped marker and screenshot. **F12**, closing the game, or the launcher's **Finish recording** button ends the session. The game closes after saving its audio and event log. Returning to the title or playing another run stays within the same recording.

Afterward, the launcher prepares and opens `review.html`. The page plays the game video with microphone commentary and game sound. Click transcript lines, markers, or screenshots to jump to that moment. Written notes can be saved as `feedback-notes.md` into the session folder.

Sessions live in `~/Videos/FalloutForecastPlaytests/`. `latest.json` identifies the most recently processed session. Tell the agent **review my latest playtest** to have it read that pointer, the transcript, marked screenshots, game logs, and the recorded build revision.

Each session contains these review artifacts.

| File | Purpose |
| --- | --- |
| `playtest.mp4` | H.264 video with microphone commentary and game sound |
| `microphone.wav` | Isolated voice audio for listening and transcription |
| `game_audio.wav` | Game sound recorded directly from Godot's master bus |
| `transcript.txt`, `transcript.json`, `transcript.vtt` | Locally recognized speech with video-aligned timestamps |
| `AGENT_REVIEW.md` | Agent entry point with build revision, spoken feedback, and marked moments |
| `timeline.json`, `events.jsonl` | Scenes, phases, shots, damage, player states, and periodic position/vitals snapshots |
| `frames/`, `mark-*.png` | Screenshots every ten seconds plus full-resolution F7 captures |
| `session.json`, `game.log`, `capture.log`, `microphone.log`, `processing.log` | Recording status and diagnostic information |

Windows Graphics Capture targets the launched game process, including its Direct3D content. A borderless fixed-size window keeps the captured area stable. The game shows a small **CAPTURE** timer separate from the fictional VHS **REC** display. F11 fullscreen switching is suppressed during a recorded session. Pause menus remain usable and recording continues while paused.

Video, voice, and telemetry stay on the PC. The launcher uses `uv` to cache Python 3.13 and pinned dependencies on its first launch. Whisper's `base.en` model is downloaded if it is missing, then transcription runs locally. Initial dependency/model downloads need internet access. FFmpeg can be supplied through `FFMPEG_EXE`, PATH, the local recorder cache, or the bundled `imageio-ffmpeg` dependency. Set `GODOT_EXE` if the engine is outside the usual Desktop location.

To retry processing a saved session, run this from the repository in PowerShell.

```powershell
uv run --no-project --python 3.13 --with faster-whisper==1.2.1 --with av==16.0.1 --with imageio-ffmpeg==0.6.0 python tools/playtest/review.py 'C:/path/to/session'
```

The recorder preserves the original capture if processing fails. A game crash can leave game sound unavailable, while the external video and microphone capture remain recoverable. Recognition can miss or mishear words, so uncertain feedback should be checked against the original audio.

Implementation follows the [Windows Graphics Capture bindings](https://github.com/NiiightmareXD/windows-capture/tree/main/windows-capture-python), [FFmpeg device documentation](https://ffmpeg.org/ffmpeg-devices.html), and [faster-whisper API](https://github.com/SYSTRAN/faster-whisper).
