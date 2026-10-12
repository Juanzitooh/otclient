# Product roadmap

## Offline Assets Editor for 15.x

Finish the current single-window editor workflow, then reduce the import loop
for individual sprites by opening a safe PNG copy in a user-selected desktop
image editor and explicitly applying the saved image to the 15.x work copy.

The external-editor workflow must preserve the existing safety boundary:
installed assets are read-only, edits go to the isolated work copy, and the
PNG opened by another application is a separate user-data copy. See
[`docs/offline-sprite-editor.md`](../offline-sprite-editor.md) for current
behavior and limits.
