# LAN netcode simulator (developer tool)

Runs the real game in two headless Chromium pages with a **virtual clock** and an in-process "network" you control
(latency, jitter, packet loss, per-side frame rate), so results are exact and repeatable.

- `vsim.js`   - createSim({lat,jitter,loss,fpsHost,fpsGuest}) / startLan(sim,map)
- `bench.js`  - measures movement response, opponent smoothness, shot feedback, hit registration, loss, fps
  (`MODE=lat|hit|loss|fps node bench.js`; compares the OLD behaviour config against the NEW one)

It expects a test build of `index.html` served at `http://localhost:8765/test.html` that exports `window.__T`
(NET, NETCFG, NS, netRecv, netOpen, ...) and honours `window.__NORENDER` - see the notes at the top of `vsim.js`.
For quick checks on real machines use the in-game overlay instead: **F4** shows route / RTT / tick / loss / prediction,
F6 tick rate, F7 prediction, F8 added latency, F9 added loss, F10 interpolation mode.
