"""Build an offline playback and agent handoff from a completed capture."""

from __future__ import annotations

import argparse
import html
import json
from pathlib import Path

from capture import ffmpeg_path, run, write_json


def timestamp(seconds: float) -> str:
    minutes, seconds = divmod(max(0, seconds), 60)
    hours, minutes = divmod(int(minutes), 60)
    return f"{hours:02d}:{minutes:02d}:{seconds:06.3f}"


def convert(ffmpeg: str, args, folder: Path):
    result = run([ffmpeg, "-hide_banner", "-y", *map(str, args)],
                 capture_output=True, encoding="utf-8", errors="replace")
    with (folder / "processing.log").open("a", encoding="utf-8") as log:
        log.write(result.stderr + "\n")
    if result.returncode:
        raise RuntimeError(f"Media processing failed. The original capture is preserved in {folder}.")


def transcribe(folder: Path, report, offset=0.0):
    from faster_whisper import WhisperModel

    report("Transcribing your microphone locally…")
    model = WhisperModel("base.en", device="cpu", compute_type="int8", cpu_threads=4)
    segments, _ = model.transcribe(str(folder / "microphone.wav"), language="en",
                                   vad_filter=True, beam_size=3, condition_on_previous_text=False)
    transcript = [{"start": max(0, float(segment.start) + offset), "end": max(0, float(segment.end) + offset), "text": segment.text.strip()}
                  for segment in segments]
    write_json(folder / "transcript.json", transcript)
    (folder / "transcript.txt").write_text("\n".join(
        f"[{timestamp(item['start'])}] {item['text']}" for item in transcript) + "\n", encoding="utf-8")
    cues = ["WEBVTT\n"]
    for item in transcript:
        cues.append(f"{timestamp(item['start'])} --> {timestamp(item['end'])}\n{item['text']}\n")
    (folder / "transcript.vtt").write_text("\n".join(cues), encoding="utf-8")
    return transcript


def process(folder: Path, report=print, skip_transcription=False):
    folder = folder.resolve()
    metadata_path = folder / "session.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    ffmpeg = ffmpeg_path()
    report("Preparing video and voice audio…")
    if not (folder / "microphone.wav").exists():
        convert(ffmpeg, ["-i", folder / "capture.mkv", "-map", "0:a:0", "-ac", "1", "-ar", "16000",
                         "-c:a", "pcm_s16le", folder / "microphone.wav"], folder)
    inputs = ["-i", folder / "capture.mkv"]
    voice_offset = metadata.get("microphone_start_unix", metadata["started_unix"]) - metadata["started_unix"]
    inputs += ["-itsoffset", str(voice_offset), "-i", folder / "microphone.wav"]
    game_audio = folder / "game_audio.wav"
    if game_audio.exists() and (folder / "audio_start.json").exists():
        audio_start = json.loads((folder / "audio_start.json").read_text(encoding="utf-8"))["unix"]
        offset = max(0, audio_start - metadata["started_unix"])
        inputs += ["-itsoffset", str(offset), "-i", game_audio,
                   "-filter_complex", "[1:a]aresample=48000,aformat=channel_layouts=stereo,volume=1.0[voice];[2:a]volume=0.65[game];"
                   "[voice][game]amix=inputs=2:duration=longest:normalize=0:dropout_transition=0,alimiter=limit=0.95,apad[mix]",
                   "-map", "0:v:0", "-map", "[mix]"]
        metadata["game_audio_offset_seconds"] = offset
    else:
        inputs += ["-filter_complex", "[1:a]apad[mix]", "-map", "0:v:0", "-map", "[mix]"]
        metadata["warning"] = "Game audio was unavailable. Video and microphone audio were preserved."
    convert(ffmpeg, [*inputs, "-c:v", "copy", "-c:a", "aac", "-b:a", "160k", "-shortest", "-movflags", "+faststart",
                     folder / "playtest.mp4"], folder)
    transcript = []
    if (folder / "transcript.json").exists():
        transcript = json.loads((folder / "transcript.json").read_text(encoding="utf-8"))
    elif not skip_transcription:
        try:
            transcript = transcribe(folder, report, voice_offset)
            metadata.pop("transcription_error", None)
        except Exception as error:
            metadata["transcription_error"] = str(error)
            report("Video saved. Transcription needs a retry; see the review folder.")
    markers = []
    events = []
    if (folder / "events.jsonl").exists():
        for line in (folder / "events.jsonl").read_text(encoding="utf-8").splitlines():
            try:
                event = json.loads(line)
                event["seconds"] = round(max(0, event["unix"] - metadata["started_unix"]), 3)
                events.append(event)
            except (ValueError, KeyError):
                continue
    markers = [event for event in events if event["type"] == "marker"]
    report("Building screenshots and the review timeline…")
    frames = folder / "frames"
    frames.mkdir(exist_ok=True)
    convert(ffmpeg, ["-i", folder / "playtest.mp4", "-vf",
                     "select='isnan(prev_selected_t)+gte(t-prev_selected_t,10)',scale=480:-2",
                     "-fps_mode", "vfr", "-frames:v", "720", frames / "frame-%04d.jpg"], folder)
    write_json(folder / "timeline.json", events)
    metadata.update(status="ready", transcript_segments=len(transcript), markers=len(markers))
    write_json(metadata_path, metadata)
    build_review(folder, metadata, transcript, events)
    write_json(folder.parent / "latest.json", {"folder": str(folder), "review": str(folder / "review.html")})
    return folder / "review.html"


def build_review(folder: Path, metadata, transcript, events):
    markers = [event for event in events if event["type"] == "marker"]
    frame_files = sorted((folder / "frames").glob("frame-*.jpg"))
    handoff = ["# Playtest feedback", "", f"Session folder: {folder}",
               f"Build commit: {metadata.get('revision', 'unknown')}",
               f"Uncommitted changes at capture: {metadata.get('dirty', False)}", "",
               "Open review.html for synchronized video, voice captions, markers and screenshots.",
               "Read transcript.txt and timeline.json for spoken feedback and game state.",
               "frames/frame-0001.jpg starts at 00:00. Subsequent frames are ten seconds apart.",
               "Speech recognition may mistranscribe words. Check microphone.wav or playtest.mp4 when uncertain.",
               "Feedback expresses observations and proposed changes. Review before changing gameplay.", ""]
    if metadata.get("warning"):
        handoff += [metadata["warning"], ""]
    if metadata.get("transcription_error"):
        handoff += ["Transcription needs retry: " + metadata["transcription_error"], ""]
    handoff += ["## Marked moments", ""]
    handoff.extend(f"- [{timestamp(event['seconds'])}] {event['data'].get('image', '')}" for event in markers)
    handoff += ["", "## Spoken feedback", ""]
    handoff.extend(f"- [{timestamp(item['start'])}] {item['text']}" for item in transcript)
    (folder / "AGENT_REVIEW.md").write_text("\n".join(handoff) + "\n", encoding="utf-8")
    data = json.dumps({"transcript": transcript, "events": [event for event in events if event["type"] != "snapshot"],
                       "frames": [path.relative_to(folder).as_posix() for path in frame_files]}, ensure_ascii=True)
    data = data.replace("<", "\\u003c")
    title = html.escape(folder.name)
    warning = html.escape(metadata.get("transcription_error", metadata.get("warning", "")))
    document = """<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Playtest review</title><style>
*{box-sizing:border-box}body{margin:0;background:#101923;color:#e8e9dd;font:16px system-ui,sans-serif}
main{max-width:1400px;margin:auto;padding:24px}header{display:flex;justify-content:space-between;align-items:center}
h1{font-size:24px}h2{font-size:18px;color:#78d9d4}video{width:100%;max-height:70vh;background:#000}
.layout{display:grid;grid-template-columns:minmax(0,2fr) minmax(280px,1fr);gap:24px}
button{font:inherit;color:inherit;background:#20303e;border:1px solid #3d5967;padding:10px;cursor:pointer;border-radius:5px}
button:hover,button.active{background:#32525c;border-color:#78d9d4}.timeline{max-height:68vh;overflow:auto}
.timeline button{display:block;text-align:left;width:100%;margin:6px 0}.time{color:#78d9d4;font-variant-numeric:tabular-nums}
.frames{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:12px}.frames img{width:100%}
textarea{display:block;width:100%;min-height:100px;background:#17242f;color:inherit;border:1px solid #3d5967;padding:12px;font:inherit}
.warning{color:#f7ca71}a{color:#78d9d4}small{color:#a9bac4}@media(max-width:800px){.layout{grid-template-columns:1fr}}
</style><main><header><h1>Playtest review</h1><small>SESSION_TITLE</small></header><p class="warning">WARNING_TEXT</p>
<div class="layout"><section><video id="video" controls preload="metadata" src="playtest.mp4"></video>
<p><button id="mark">Add note at current time</button> <button id="download">Save feedback notes</button></p>
<textarea id="notes" placeholder="Your notes…"></textarea><small>Notes save in this browser. Save feedback notes to include them in the session folder.</small>
</section><aside><h2>Voice feedback</h2><div class="timeline" id="transcript"></div><h2>Marked moments and events</h2><div id="events"></div></aside></div>
<h2>Timeline screenshots</h2><div id="frames" class="frames"></div><p><a href="AGENT_REVIEW.md">Agent handoff</a> · <a href="microphone.wav">Microphone audio</a> · <a href="game.log">Game log</a></p></main>
<script>const data=SESSION_DATA;const video=document.querySelector('#video');const notes=document.querySelector('#notes');
const key='playtest-notes-'+location.pathname;try{notes.value=localStorage.getItem(key)||''}catch{}
notes.addEventListener('input',()=>{try{localStorage.setItem(key,notes.value)}catch{}});
const stamp=s=>new Date(Math.max(0,s)*1000).toISOString().slice(11,19);
function seekButton(parent,time,text){const button=document.createElement('button');button.textContent=stamp(time)+'  '+text;
button.onclick=()=>{video.currentTime=time;video.play()};parent.append(button);return button}
const transcript=document.querySelector('#transcript');
if(!data.transcript.length){transcript.textContent='No transcript is available. Listen to the video or retry processing.'}
data.transcript.forEach(item=>{const button=seekButton(transcript,item.start,item.text);item.button=button});
video.ontimeupdate=()=>data.transcript.forEach(item=>item.button.classList.toggle('active',video.currentTime>=item.start&&video.currentTime<item.end));
const events=document.querySelector('#events');data.events.filter(item=>['marker','phase','player_state','run_finished'].includes(item.type)).forEach(item=>{
seekButton(events,item.seconds,item.type==='marker'?'Marked feedback':item.type+' '+JSON.stringify(item.data))});
const frames=document.querySelector('#frames');data.frames.forEach((src,i)=>{const button=document.createElement('button');
const image=document.createElement('img');image.src=src;image.loading='lazy';image.alt='Game at '+stamp(i*10);button.append(image,document.createTextNode(stamp(i*10)));
button.onclick=()=>{video.currentTime=i*10;video.play();video.scrollIntoView({behavior:'smooth'})};frames.append(button)});
document.querySelector('#mark').onclick=()=>{notes.value+='\\n['+stamp(video.currentTime)+'] ';notes.focus();notes.dispatchEvent(new Event('input'))};
document.querySelector('#download').onclick=()=>{const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([notes.value],{type:'text/markdown'}));a.download='feedback-notes.md';a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000)};
</script></html>"""
    document = document.replace("SESSION_TITLE", title).replace("WARNING_TEXT", warning).replace("SESSION_DATA", data)
    (folder / "review.html").write_text(document, encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("session", type=Path)
    parser.add_argument("--skip-transcription", action="store_true")
    args = parser.parse_args()
    print(process(args.session, skip_transcription=args.skip_transcription))
