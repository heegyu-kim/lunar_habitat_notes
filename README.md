# lunar_habitat_notes

One Godot 4.7 project that merges the VR/AR@MIT **Lunar Habitat** XR template (ladder, grabbing,
passthrough, hand tracking) with the **habitat_notes** sticky-note addon (spatial review notes with voice,
screenshots and clips, session JSON, HTML report).

- With a headset connected it runs in **VR**; without one it runs as a **desktop first-person** app.
- Design background, UI principles and the data schema are in [docs/DESIGN.md](docs/DESIGN.md).

---

## 1. Running it

1. Godot **4.7** → Project Manager **Import** → `project.godot` in this folder → **Import & Edit**
2. The first open takes 1–2 minutes while the habitat glb (about 900 meshes) is imported.
3. **F5**. If Windows asks for microphone permission, **allow** it.
4. On the identity card, enter your name, pick a role (Engineer / Architect / Inhabitant) and press **Start**.

To run on the desktop even with a headset connected: `main.tscn` → **Main** node → Inspector → **Force Desktop**.
(There is no typing in VR, so open the same session on the desktop this way to write note text.)

### Desktop controls

| Key | Action |
|---|---|
| W A S D, mouse, Shift | Move, look, run |
| **Space / C** | Near the ladder: climb **up / down** one deck |
| **N (hold)** | Translucent pin follows the surface you look at. **Release** to place a note (screenshot + editor) |
| **E** | Open the note you are looking at |
| **Tab** | Open / close the list |
| **1 – 5** | Show / hide a type (Constraint, Requirement, Proposal, Question, Observation) |
| **]  [** | Tour next / previous |
| **Esc** | End tour → close panel → release the mouse |
| Right-button drag | Look around while a panel is open |

### VR controls (Quest via Quest Link, or APK)

The template's buttons are unchanged. Notes only use the **right trigger** and the **left wrist board**.

| Input | Action |
|---|---|
| Left stick | Move (head direction, horizontal) |
| Right stick left / right | Smooth continuous turn (further = faster). For snap turning: `XROrigin3D/XRMovement` → **Turn Mode** |
| Right stick up / down | Scroll the wrist board |
| **A** (right) / **X** (left) | Near the ladder: climb **up / down** one deck |
| **B** (right) | Toggle passthrough |
| Grip | Grab props (RigidBody) |
| Hands (hand tracking) | Pinch thumb and index to grab |
| **Trigger** aimed at a wall, floor or equipment | Hold for a translucent pin, **release** to place the note |
| **Trigger** tapped on a note | Open that note on the board |
| **Trigger held 3 s** on a note | Start recording screen + voice (tap again to stop) |
| **Trigger** on the board | Click a board button |

The board floats above the left hand with Note / List / Session tabs. Open a note and press **▶ Play clip**:
the view fades out, you are moved to where the author stood and looked (on their deck if it differs), and
their recording plays in front of you. Tap the trigger to return. Locomotion and the ladder are frozen during playback.

If the board does not sit well on the hand: `main.tscn` → **XROrigin3D/XRNotes** → Inspector → **Board Offset / Board Tilt Degrees**.

---

## 2. Where notes stick

Notes stick only to surfaces **with collision**. The habitat glb has none, so the
`LunarHabitat/SurfaceCollision` node (`scripts/habitat_collision.gd`) gives every mesh a trimesh
StaticBody3D named `<mesh name>_col` at startup. As a result

- notes can go on any wall, deck, rack, panel or label, and each note remembers the **mesh name** ("on Service access panel021")
- when a Constraint and a Proposal sit on the same part, their pins pulse to flag a **conflict**
- the desktop player cannot walk through walls

Meshes smaller than 8 cm (bolts, LEDs) are skipped. Adjust **Min Size** in the Inspector, or turn **Enabled** off to skip generation.
While climbing the ladder, collision in the `habitat_floor` and `habitat_surface` groups is disabled briefly.

---

## 3. Saving and sharing

**Session** tab on the board / panel.

- **Save** writes the session as JSON under the name you type
- **Load** restores a saved session
- **Export report** writes every note into one HTML file (screenshots, voice and clips embedded; send that one file and it opens in any browser)
- **Open data folder** opens the folder below

```
sticky_notes/
  sessions/   <name>.json      note data
  media/      shot_*.png       screenshots
              voice_*.wav      voice
              clip_<id>/       screen + voice clips
  reports/    <name>.html      reports
```

- Windows  `%APPDATA%\Godot\app_userdata\lunar_habitat_notes\sticky_notes\`
- Quest     `Android/data/<package name>/files/sticky_notes/`

To hand a session to another Godot user, send `sessions/<name>.json` **together with** `media/`, put them in the same place and **Load**.

### Recording (ffmpeg, Windows)

Godot has no video encoder, so on the PC clips are encoded with **ffmpeg**. Put `ffmpeg.exe` in `tools/`
as described in `tools/README.txt` and the app finds it at startup (it is not committed to git).

- **What is captured.** Not the monitor or the desktop: a **camera that follows your head** renders the VR view.
  Godot renders 1280×720 at 24 fps and pipes the frames straight into ffmpeg, which encodes x264 (`CLIP_CRF` 20).
  No window-title matching and no screen capture, so other windows on top do not matter.
- **Voice.** Godot records the microphone itself (same clock as the video, so it stays in sync) and ffmpeg
  merges it with the video when recording stops. Only if Godot cannot open a microphone does ffmpeg capture it through DirectShow.
- **Playback quality.** 1280 px, 15 fps JPG frames are extracted from the mp4 for the board and the theater. The HTML report embeds the mp4 itself.
- **For higher quality** change `REC_W / REC_H / REC_FPS / CLIP_CRF / PLAY_W / PLAY_FPS` in `addons/sticky_notes/note_manager.gd`.
  1920×1080 works, but reading frames back in VR costs more.
- Without ffmpeg the app falls back to 8 fps 640×360 JPG frames plus the Godot microphone. A standalone Quest build (APK) always uses the fallback.

**Microphone.** The Session tab of both the desktop panel and the VR board has a microphone picker with a
**level bar and dB readout**. Pick "Headset Microphone (Oculus Virtual Audio Device)" for the headset mic. Speak:
the bar must move. If it never moves, that device will not record. After each recording the voice level is measured;
if it is silent the clip player shows **mic was silent** and a warning is printed. Then check:

1. Meta Quest Link app → **Devices → headset → microphone** is on, and a Link session is actually running (the device is silent while Link is off)
2. Windows **Settings → Privacy & security → Microphone → Let desktop apps access your microphone**
3. Windows sound settings: the headset microphone is not **disabled** and its volume is not 0
4. Still nothing: pick another device (PC microphone) and see whether the bar moves. If it does, the problem is on the Quest side
5. If recording worked and suddenly goes silent, the Link session dropped and reconnected. Wear the headset, make sure Link (Dash) is up, then press **Reconnect mic**. Also check the mic mute toggle in the Quest quick settings

The **Fallback microphone for ffmpeg** dropdown is used only when Godot cannot open a microphone at all. Details are
logged to `ffmpeg_record.log` and `ffmpeg_convert.log` in the clip folder. `tools/mic_check.bat` records 5 seconds
with ffmpeg alone and prints the level, which tells you whether Windows receives any sound from the headset.

---

## 4. Installing on the Quest (APK)

`export_presets.cfg` contains a **Meta Quest 3** preset (Gradle build, Meta OpenXR plugin, hand tracking,
passthrough, microphone permission). Install the Godot OpenXR Vendors plugin (`addons/godotopenxrvendors/`)
and the Android build template, then **Project → Export → Meta Quest 3 → Export Project**.

---

## 5. Distributing to the team

### Option A. Windows executable (recommended: no Godot install needed)

1. Once: Godot editor → **Editor → Manage Export Templates → Download and Install** (4.7.2 templates, about 1 GB)
2. **Project → Export** → select the **Windows Desktop** preset (included) → **Export Project** → `build/windows/lunar_habitat_notes.exe`
   - If the dialog warns about missing D3D12 libraries, use its install button
3. **Copy `tools/ffmpeg.exe` next to the exe** (the app looks next to the exe, then in `tools/` next to the exe, then in the project). Without it, clips fall back to the low-quality frame method
4. Zip the whole `build/windows/` folder and send it

Requirements on the teammate's PC: Windows 10/11, the Meta Quest Link app with a Quest connected (cable or Air Link), OpenXR runtime set to Meta.
Without a headset the app opens in desktop mode. Windows SmartScreen may block the first run: "More info → Run anyway".

### Option B. Share the Godot project (when teammates also edit)

- GitHub: push this folder as a repository (`.gitignore` excludes `.godot/`, `build/` and `tools/ffmpeg.exe`). Teammates clone it, open it with Godot 4.7.2 and add `ffmpeg.exe` as described in `tools/README.txt`
- Zip: leave out `.godot/` and `build/`. The first open re-imports the glb (1–2 minutes)

### Passing notes around

Whichever way the app runs, note data accumulates on each PC in `%APPDATA%\Godot\app_userdata\lunar_habitat_notes\sticky_notes\`.

- **To show review results**: Session tab → **Export report** → one HTML file with screenshots, voice and clips embedded. Opens in a browser
- **To let someone continue the review**: send `sessions/<name>.json` plus the `media/` folder; the recipient puts them in the same place and presses **Load**

### Option C. Standalone Quest APK

For running on the headset alone, without a PC. See section 4. Clips then use the 640×360 frame method (no ffmpeg) and note data lives on the headset.

---

## 6. File layout

```
main.tscn / main.gd            Scene root. Starts OpenXR, or spawns the desktop player without a headset
  XROrigin3D/
    XRControllerLeft/Right     Template controllers (grip pose, models, grab, passthrough toggle)
    XRVisuals, XRHands         Controller models, hand-tracking hands
    XRMovement, XRLadder       Stick locomotion and turning, A/X ladder
    XRNotes                    Builds the note VR rig (wrist board, pointer, clip theater, teleport)
  LunarHabitat/                Habitat glb
    FloorL1-3                  Deck floor collision (for the ladder, habitat_floor group)
    SurfaceCollision           Generates note collision for every mesh
scenes/desktop_player.tscn     Desktop player (NotePlacer under the Camera3D)
scripts/
  xr_notes.gd                  Creates WristBoard / XRNotePlacer / ClipTheater under the XROrigin3D
  habitat_collision.gd         Mesh → trimesh StaticBody3D
  desktop_player.gd            WASD, mouse, Space/C ladder, note teleport
  xr_ladder.gd, xr_move.gd, xr_grab.gd, xr_grab_hands.gd, xr_hands.gd,
  xr_visuals.gd, xr_passthrough.gd, B_toggle_passthrough.gd   Template originals
addons/sticky_notes/           habitat_notes addon (no scene files, all code)
  note_manager.gd              Autoload NoteManager. CRUD, save/load, screenshots, recording, report
  note_placer.gd               Desktop input (child of the Camera3D)
  xr/xr_note_placer.gd         VR input (right trigger)
  xr/wrist_board.gd            Left-hand board (panel drawn into a SubViewport on a quad)
  xr/clip_theater.gd           Immersive playback
  ui/                          HUD, side panel, VR panel, identity card, clip player
addons/open_godot_mcp/         Editor MCP bridge (template original)
assets/models/Lunar Habitat/   Habitat glb + textures
docs/DESIGN.md                 Note design notes
tools/                         Put ffmpeg.exe here; mic_check.bat
default_bus_layout.tres        Record bus
build/                         Export output (ignored by git)
```

### What changed from the two source projects

- `main.gd`  No longer stops with an error without a headset; spawns the desktop player instead
- `main.tscn`  Added the `XRNotes` and `SurfaceCollision` nodes. Grab Area3D collision_layer set to 0 so the note pointer ray ignores the hands
- `project.godot`  NoteManager autoload, microphone input, Input Map (note, movement and ladder keys), OpenXR startup alert off
- `export_presets.cfg`  `record_audio` permission on; Windows Desktop preset added
- `scripts/xr_move.gd`  Smooth turning by default (Turn Mode switches back to snap)
- `addons/sticky_notes/xr/clip_theater.gd`  Clip playback teleport also moves the height (other decks)
- `addons/sticky_notes/note_manager.gd`  Clip recording pipes Godot-rendered frames into ffmpeg instead of screen capture (gdigrab). 1280×720 24 fps, voice from the Godot microphone, 1280 px 15 fps playback frames. Microphone level/dB readout, Reconnect mic, ffmpeg found next to an exported exe
- `addons/sticky_notes/clip_frames.gd`  Playback frames are decoded ahead on the WorkerThreadPool
- `addons/sticky_notes/note_placer.gd`, `xr/xr_note_placer.gd`  Hit normals facing away from the viewer are flipped, so notes stand on the side you see
- habitat_notes' `XRBoot` autoload, `VRPlayer`, `VRHand` and the demo room were dropped; the template's XR rig replaces them

---

Sources: [VR/AR@MIT Godot XR Template](https://docs.google.com/presentation/d/1k10QOjVzC8dSaK8WAtLZF0jyv3P6TW-NY8ZJmvSjivk/edit?usp=sharing), habitat_notes (docs/DESIGN.md).
