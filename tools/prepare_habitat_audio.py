"""Prepare optional spatial WAVs from the user's locally available source files."""
import argparse
from pathlib import Path
import shutil
import subprocess
from tempfile import TemporaryDirectory


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Folder containing the five authorized source WAVs")
    args = parser.parse_args()
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        parser.error("FFmpeg must be on PATH.")
    vent = "ambience fan:vent.wav"
    if not (args.source / vent).is_file():
        vent = "ambience fan-vent.wav"
    files = (vent, "liquid flowing in pipe.wav", "machine beeping 1.wav",
             "machine beeping 2.wav", "sticky note.wav")
    missing = [name for name in files if not (args.source / name).is_file()]
    if missing:
        parser.error("Missing source WAV(s): " + ", ".join(missing))
    destination = Path(__file__).resolve().parents[1] / "assets" / "audio"
    destination.mkdir(parents=True, exist_ok=True)

    with TemporaryDirectory(prefix="habitat-audio-") as tmp:
        staging = Path(tmp)

        def encode(name, output, *options):
            subprocess.run([ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error",
                            "-i", str(args.source / name), *options, "-vn", "-map_metadata", "-1",
                            "-c:a", "pcm_s16le", str(staging / output)], check=True)

        def loop(name, output, duration, fade, boost=0):
            # The last segment blends tail into head. At the actual wrap,
            # playback continues through adjacent samples in the source.
            graph = (
                f"[0:a:0]aformat=channel_layouts=mono,aresample=48000,volume={boost}dB,asplit=3[m][t][h];"
                f"[m]atrim=start={fade}:end={duration-fade},asetpts=PTS-STARTPTS[mid];"
                f"[t]atrim=start={duration-fade}:end={duration},asetpts=PTS-STARTPTS[tail];"
                f"[h]atrim=end={fade},asetpts=PTS-STARTPTS[head];"
                f"[tail][head]acrossfade=d={fade}:c1=tri:c2=tri[join];"
                "[mid][join]concat=n=2:v=0:a=1[out]"
            )
            encode(name, output, "-filter_complex", graph, "-map", "[out]")

        loop(vent, "vent_ceiling_loop.wav", 36.202458, 1.2)
        loop("liquid flowing in pipe.wav", "pipe_flow_loop.wav", 200.0, 1.2)
        loop("machine beeping 2.wav", "machine_room_loop.wav", 96.944, 0.35, boost=8)
        encode("machine beeping 1.wav", "machine_dry_3s_10s_pause.wav",
               "-map", "0:a:0", "-ac", "1", "-ar", "48000", "-af", "atrim=end=3,apad=pad_dur=10")
        encode("sticky note.wav", "sticky_note_placed.wav", "-map", "0:a:0", "-ac", "1")
        # Optional opening sting (played once at app start by scripts/opening_sound.gd).
        if (args.source / "opening sound.wav").is_file():
            encode("opening sound.wav", "opening.wav", "-map", "0:a:0", "-ac", "2", "-ar", "48000")
        for output in sorted(staging.glob("*.wav")):
            shutil.move(str(output), str(destination / output.name))
            print(destination / output.name)


if __name__ == "__main__":
    main()
