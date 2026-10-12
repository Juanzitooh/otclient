# Architecture

The Offline Assets Editor UI is implemented in
`modules/game_sprite_editor/`. Asset reading and safe work-copy mutation live in
the client asset APIs (`src/client/spriteappearances.cpp` and
`src/client/thingtypemanager.cpp`). Platform process launch is provided by
`g_platform.spawnProcess`.

External image editing crosses the UI and platform boundary only through a
PNG file in the user's writable directory. Import returns through the existing
sprite import API, preserving its target-size validation and work-copy rules.
Do not make installed `/data/things/<version>/` files a write target.
