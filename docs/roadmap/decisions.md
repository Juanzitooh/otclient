# Decisions

## D001 - External sprite editing uses an isolated PNG copy

Status: `accepted for T1.2`

The external editor receives a separately exported PNG in the user's writable
sprite-editor area. It never edits an installed asset or the packed work-copy
file directly. The user explicitly applies the saved PNG back through the
existing import API, which validates dimensions and writes only to the active
15.x work copy.

The selected asset version and Sprite ID are captured when the PNG is created
so a later selection change cannot silently redirect the import.

## D002 - Launch configured desktop editors through the platform API

Status: `accepted for T1.2`

Reuse `g_platform.spawnProcess(executable, { pngPath })` rather than building a
shell command or adding a new native bridge. LibreSprite declares positional
`[FILES]` inputs, starts the UI by default, and disables it only for batch mode
in [`app_options.cpp`](https://github.com/LibreSprite/LibreSprite/blob/master/src/app/app_options.cpp).
Other configured editors are supported when they also accept a file path as an
argument. Browser and mobile launch are outside this milestone.
