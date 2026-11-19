# Quest standalone version (APK)

This folder is the `holonotes-testing` project with everything added on 2026-11-18 (3D deck map,
standing hologram, habitat sounds, main lobby), set up to run **on the headset itself** as an APK.
The PC + Quest Link version used for the video is the folder `lunar_habitat_notes-holonotes-testing`
and is not touched by anything here.

All features are the same in both. Only how they are drawn differs.

## What is different from the PC + Link version

| Area | PC + Link version | This version |
|---|---|---|
| Renderer | Forward+ | **Mobile**, also in the editor and the desktop window, so they show what the headset shows (`project.godot`) |
| Indoor light | SDFGI, SSIL, SSAO, live lights with shadows | **Baked lightmap** (`LunarHabitat/BakedLighting`, `main.lmbake`, `main.exr`), re-baked here on 2026-11-18 because the sun's direction had changed |
| Reflections | SSR | the 3 reflection probes already in the scene |
| Glow, SSR, SSAO, SSIL, SDFGI | on | off in `assets/environment/lunar_environment.tres` (not available on the Mobile renderer; glow would switch off foveated rendering) |
| Screen-space AA | SMAA on the desktop | off; MSAA 4x everywhere |
| Foveated rendering | - | medium, dynamic (`project.godot` `[xr]`, `main.gd` sets the viewport's VRS mode) |
| Deck map | every mesh of the habitat | **light version**: coarser meshes, no pieces under 20 cm, the decks you are not on show hull and floors only (`LITE_*` in `scripts/xr_minimap.gd`). About 40 000 to 100 000 triangles instead of 280 000 to 360 000 |
| Lobby picture | 3840 x 2160, unpacked at start | imported compressed with mipmaps at 2560 x 1440 (`lobby_background.png.import`); the habitat and the Moon are not drawn while the lobby is open |
| Clips | ffmpeg video | frame method (no ffmpeg on the headset) |

The desktop window of this project keeps the baked lighting too (`main.gd`), for the same reason as
the renderer.

## After changing the model or the lights: bake again

- in the editor: **Project > Tools > Bake habitat lightmaps (Quest)**, or
- unattended (PowerShell, in this folder):

```
$env:QUEST_BAKE = "1"; & "Godot_v4.7.2-stable_win64_console.exe" --editor --xr-mode off --path .
```

The bake took 16 seconds on an RTX 5070 Ti (213 meshes). The plugin is `addons/quest_bake`.

## Sounds

The six sounds in `assets/audio/` (four ambience loops, the opening sting, the note cue) are part of
this branch, so a fresh clone has sound without any extra step. On the other branches they are
git-ignored and prepared locally with `tools/prepare_habitat_audio.py`.

## Building the APK

The APK is not part of this branch (`build/` is git-ignored) and nothing here has been run in a
headset yet. The export preset "Meta Quest 3" writes `build/quest/astronote_quest.apk`.

Needs, once per PC: JDK 17, the Android SDK (platform-tools, build-tools 36.1.0, platform android-36,
NDK 29.0.14206865, CMake 3.22.1; `tools/install_android_sdk.cmd`), the Godot 4.7.2 Android export
templates, the Godot OpenXR Vendors plugin 5.2.0 in `addons/godotopenxrvendors/` and the Android
build template in `android/` (both git-ignored; on a fresh clone install the plugin from the Asset
Library and add `--install-android-build-template` to the first export).

```
$env:JAVA_HOME = "$env:LOCALAPPDATA\Android\jdk-17"
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = "$env:APPDATA\Godot\keystores\debug.keystore"
$env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = "androiddebugkey"
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = "android"
& "Godot_v4.7.2-stable_win64_console.exe" --xr-mode off --path . --export-release "Meta Quest 3" build/quest/astronote_quest.apk
```

Do **not** add `--headless`: the export then skips the Shader Baker and the headset has to compile
every shader while you look at it.

Install (developer mode on, USB debugging allowed in the headset):

```
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install -r build\quest\astronote_quest.apk
```

## If the headset cannot hold its frame rate

Nothing here has been measured in a headset. In order of how much they give back:

1. `main.gd` > `render_scale` 1.2 -> 1.0.
2. `project.godot` > `[xr]` > `openxr/foveation_level=3` (high).
3. `scenes/lunar_exterior.tscn` > Sun > Shadow: lower Max Distance (`vr_sun_shadow_distance` in `main.gd`).
4. `project.godot` > `anti_aliasing/quality/msaa_3d=1` (2x).
