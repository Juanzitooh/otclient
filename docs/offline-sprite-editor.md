# Offline Assets Editor 15.x

The optional Assets Editor edits modern 15.x client assets while the client is offline. It is available in builds compiled with `TOGGLE_FRAMEWORK_EDITOR=ON`.

## Work copy

Opening the editor creates or resumes a working copy at `<client write directory>/sprite-editor/data/things/<version>/`. The editor mounts that copy for editing; the installed `data/things/<version>/` package stays unchanged until installation.

Use **Load assets** to select an installed version. If a working copy already exists, the editor asks before replacing it with a fresh copy of the installed assets. This discards the old working copy and its saved edits.

## Edit appearances and sprites

Choose a category and appearance from the left panel. The center preview shows the selected sprite or animation frame. The Properties page edits the available flags, values, and animation settings for that appearance.

For item appearances, **Values** exposes typed scalar values, enum selections, optional values, and repeated enum choices used by fields such as Market profession restrictions. Clearing an optional value removes it from the working copy. Market and Cyclopedia metadata stay in the appearance flags data; they are not written to legacy `.dat`/`.spr` files.

Use **Duplicate** to create a new ID from the selected appearance, or **Create** to make one in the chosen category from a sprite ID or PNG. **Delete** removes only the selected appearance record from the working copy and keeps all sprite data. Reloading the installed assets discards these edits.

On the Import page, replace the selected frame with another sprite ID by selecting or dragging a sprite from the right panel onto the preview. To import artwork, choose a PNG file and import it; the editor creates a sprite ID and links it to the selected frame. The file browser opens in `data/things/pngs/` by default, and also supports navigating to another folder. PNGs placed in `data/things/pngs/` are ignored by Git.

The **Batch PNGs** option imports a folder of up to 256 individual prepared PNGs, subject to the 64 MiB decoded-image limit. **Sheet** splits a regular grid: choose the cell dimensions, select an inclusive row-major cell range (cell 1 is the top-left; last cell `0` means the rest of the sheet), and optionally skip fully transparent cells. One sheet import can inspect at most 64 cells. Imported PNGs receive new sprite IDs; they do not create appearances by themselves.

To edit a sprite in another application, choose **Edit sprite**. The editor exports a temporary PNG to the user's client profile and launches the configured external editor as a separate desktop window. Save the image in that application, return to OTClient, and apply the edit. The image must keep the sprite's original dimensions. Every appearance that shares this sprite ID uses the updated image.

The **Appearance** export creates a portable bundle for the selected appearance. It can also export the appearances currently visible in the left list after filtering, up to 8 at a time. Existing bundle folders are not overwritten. On import, choose one bundle folder or a parent folder containing bundles; up to 64 bundles are processed independently. A failed bundle does not undo earlier successful bundles, so the status reports partial results. The work copy remains separate from installed assets until installation.

## Install edited assets

The Export page installs the working copy into the standard runtime location, `data/things/<version>/`. After confirmation, the current package is moved to `data/things/backup/<version>-<timestamp>/`, the working copy replaces it, and the client reloads appearances and static data. The backup directory is ignored by Git.

When the editor closes, it unmounts the working copy and restores the installed package as the runtime source. The editor only supports directory-based client assets in the 15.x range; it does not modify older `.dat`/`.spr` clients.
