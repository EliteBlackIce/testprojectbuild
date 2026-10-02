# Underdog - Roblox prototype

Files
- `UnderdogGame.rbxmx` - drag-and-drop model (contains both scripts)
- `Server.lua`, `Client.lua` - the same scripts as plain text, if you'd rather paste them by hand

Import
1. Roblox Studio -> New -> Baseplate. Delete the `Baseplate` part and `SpawnLocation` in Workspace.
2. Drag `UnderdogGame.rbxmx` into the 3D view (or right-click Workspace -> Insert from File...).
3. Press Test -> Local Server, Players: 2 -> Start (the game needs 2 players; for solo testing set `MIN_PLAYERS = 1` at the top of `Server`).

Controls: mouse aim/shoot, RMB aim, 1/2/3 weapons, R reload. The loser of each round picks a power card (click or press 1/2/3). First to 5 round wins takes the match.
