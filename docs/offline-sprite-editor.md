# Offline Assets Editor

The optional Assets Editor manages modern client assets without logging in. It is available from the top menu in builds compiled with `TOGGLE_FRAMEWORK_EDITOR=ON`. Artwork is prepared in an external sprite editor and imported as PNG; the OTClient canvas is a read-only preview with zoom and pan.

## Open and edit a work copy

1. Start the client offline and open **Assets** from the top menu.
2. Select an installed asset version in the 15.x range and open its work copy.
3. Load an appearance by category and ID to preview its linked sprites. The appearance properties window edits its name, description, boolean flags, and numeric flag values.
4. To replace a sprite, enter its ID and the absolute path to a prepared PNG. The image dimensions must match that sprite.
5. To create an appearance, choose a category, name, optional description, and PNG path. New entries receive a new sprite ID and use one static 32 x 32 sprite. The editor creates one appearance in the selected category and opens its properties for flag edits.
6. Use **Reload work copy** to reload the catalog and appearances from disk.

The editor copies the selected asset package into `<client write directory>/sprite-editor/data/things/<version>/` and mounts `<client write directory>/sprite-editor` as a resource search path. Runtime assets continue to load through `/data/things/<version>/`. Saves are restricted to this work copy; installed packages are never selected as a write destination.

New sprite images are stored in 32 x 32 sprite sheets appended to the copied `catalog-content.json`. The editor reuses its own appended sheet until its 144 slots are full. Appearance data is written to the copied protobuf file. Existing metadata not edited in the form, including animation and repeated fields, is preserved.

The package copy is created through a temporary sibling directory and renamed after completion. Sprite-sheet writes are prepared in a temporary file and validated by decompressing and comparing the full bitmap before replacement. Appearance writes are serialized to a temporary protobuf file, parsed again, and replaced with a same-directory backup and rollback. Incomplete work copies are rejected; remove that version's directory under `sprite-editor/data/things/` to recreate it.

## Build gate and scope

The work-copy write APIs and preview widget are compiled only when `FRAMEWORK_EDITOR` is enabled. Normal player builds do not register the preview widget or expose the import and appearance-write functions.

The editor supports modern directory-based asset packages in client versions 15.x only. Existing sprite replacement supports the sprite's current dimensions, up to 384 x 384 pixels. Creating a new appearance currently uses a single 32 x 32 image; animation groups, multi-pattern outfits, repeated NPC sale metadata, and deletion are not edited. Transparent pixels use the modern sheet's magenta/alpha convention. Packages that contain symbolic links or non-regular files are rejected and must resolve to a local directory.

Enter an absolute path to a PNG image. The image is limited to 4 MiB and 384 x 384 pixels. Use the wheel to zoom and middle-drag to pan the preview.

## Planned: edit a sprite in an external image editor

A future action for the selected Sprite ID can export a separate PNG into the
user's writable sprite-editor directory, open that copy in a configured desktop
editor, and let the user explicitly apply the saved PNG to the active work copy.
This keeps the installed package untouched and reuses the existing import
validation. Editors must accept the image path as a command-line argument;
[LibreSprite supports positional file inputs](https://github.com/LibreSprite/LibreSprite/blob/master/src/app/app_options.cpp).
