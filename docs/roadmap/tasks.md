# Tasks

### T1.1 - Finalize the offline 15.x editor workflow

Status: `doing`

Tipo:
- `impl`

Depends on:
- `none`

Arquivos-alvo:
- `modules/game_sprite_editor/sprite_editor.lua`
- `modules/game_sprite_editor/sprite_editor.otui`
- `docs/offline-sprite-editor.md`

Objetivo:
- Finalize the current editor's contextual property panel, pending-edit
  prompts, status feedback, and visible client validation.

Escopo:
- Keep the single-window browse, preview, and edit workflow for client 15.x.
- Show only property sections supported by the selected appearance.
- Ensure save, discard, cancel, reload, replace, and export give clear feedback.

Fora de escopo:
- Supporting client versions before 15.x.
- Drawing or animating artwork in the OTClient preview canvas.
- Launching an external image editor; tracked by `T1.2`.

Passos de execucao:
1. Review the current branch diff and preserve the established 15.x asset-write
   safety boundary.
2. Exercise pending-edit dialogs and category/appearance selection in an
   isolated client profile.
3. Capture the editor in a human-visible client session and record any manual
   review still needed.

Saida esperada:
- A validated editor workflow and updated current usage guide.

Validacao automatica:
- `git diff --check` passes.
- The isolated client log contains no editor Lua errors.
- The pending-edit dialog test leaves no unsaved test text in the profile.

Gate manual:
- User review of the visible editor session.

Criterio de aceite:
- The editor opens on a 15.x work copy, updates the right panel when selection
  changes, and safely handles save/discard/cancel without clipping controls.

Referencias:
- `docs/offline-sprite-editor.md`
- `modules/game_sprite_editor/sprite_editor.lua`
- `modules/game_sprite_editor/sprite_editor.otui`

Skills aplicaveis:
- `otclient-lua`
- `otclient-runtime-qa`
- `otui-designer`
- `ui-visual-qa`

Evidencias esperadas:
- Isolated client log, interaction result, and screenshot with display size.

Artefatos visuais:
- Offline Assets Editor on a 15.x work copy at the user's desktop resolution.

### T1.2 - Edit a selected sprite in an external image editor

Status: `todo`

Tipo:
- `impl`

Depends on:
- `T1.1`

Arquivos-alvo:
- `modules/game_sprite_editor/sprite_editor.lua`
- `modules/game_sprite_editor/sprite_editor.otui`
- `docs/offline-sprite-editor.md`

Objetivo:
- Let the user open a safe PNG copy of the selected Sprite ID in a configured
  desktop image editor, then explicitly apply the saved PNG to the active 15.x
  work copy.

Escopo:
- Add an **Edit image** action associated with the selected Sprite ID.
- Export that sprite to a separate PNG under the user's writable sprite-editor
  data directory; never pass an installed asset file to the external editor.
- Let the user configure an editor executable path and launch it with the PNG
  path as a positional argument, without invoking a shell command string. On
  Unix, accept an absolute executable path because the current launcher uses
  `execv` rather than searching `PATH`.
- Give each edit session its own generated PNG path so reopening an editor does
  not overwrite another pending edit.
- Keep an explicit **Apply edited image** action. Do not import automatically
  when the external process exits; the existing process API is asynchronous.
- Bind the edit session to the asset version and Sprite ID that were selected
  when the copy was created. Reject applying it to a different target.
- Reuse the existing PNG import path so dimension validation and work-copy
  writes remain centralized.
- Make the action unavailable when desktop process launch is unsupported.

Fora de escopo:
- Editing pixels or animation timelines inside the OTClient canvas.
- Launching an editor from browser or mobile builds.
- Supporting editors that require custom shell syntax or do not accept a file
  path as an argument; custom argument templates can be a later task.
- Editing appearance flags or animation metadata in the external application.

Passos de execucao:
1. Add a temporary PNG export for the selected sprite in the user write area.
2. Add a configurable editor path and launch it with the exported PNG path
   through the existing platform process API.
3. Add an explicit apply action that validates the captured version and Sprite
   ID, imports through the existing work-copy API, and refreshes the preview.
4. Validate launch errors, cancellation, dimensions, target changes, and that
   the installed asset package remains untouched.

Saida esperada:
- A safe external-edit loop for one selected sprite, with user documentation.

Validacao automatica:
- `git diff --check` passes.
- Automated or focused checks confirm the export target is inside the user
  write directory and import uses the captured work-copy version and Sprite ID.
- Desktop launch reports unsupported platforms, missing executable paths, and
  launch API failures clearly.

Gate manual:
- Review opening the generated PNG in LibreSprite and one other configured
  editor, then applying each saved image in the running editor.

Criterio de aceite:
- The user can select a Sprite ID, open its isolated PNG copy in a configured
  desktop editor, save it, apply it back to that same Sprite ID in the active
  15.x work copy, and see the refreshed preview without modifying installed
  assets.

Referencias:
- `docs/offline-sprite-editor.md`
- `modules/game_sprite_editor/sprite_editor.lua`
- `modules/game_sprite_editor/sprite_editor.otui`
- `src/client/spriteappearances.cpp`
- `src/client/luafunctions.cpp`
- `src/framework/platform/platform.h`
