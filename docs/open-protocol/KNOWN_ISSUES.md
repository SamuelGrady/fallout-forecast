# Known issues and wire quirks

Applies to Open Protocol `v:1`, game protocol `19`.

## 1. Thin ping number format

A Thin connection can send `{"t":"ping","ms":4242}` and receive
`{"t":"pong","ms":4242.0}`. Thin echoes the parsed JSON number. Compare the
numeric value and accept an integral float in an integer field. Full normalizes
integral ping values to integers.

## 2. Full lobby handshake timeout

The five-second transport hello deadline ends at `welcome`. The server does not
impose a second deadline for `Net._hello`. It also ignores a `Net._hello` whose
inner string does not parse to a dictionary. A client should send a valid
inner JSON object once and impose its own deadline for a roster containing
`welcome.you` or a `Net._reject` reply. Close on timeout.

## 3. Full results broadcasts

`GameManager._finish` ends the client run. Global RPCs can still arrive while
the dedicated server waits five seconds to unload the scene, including a
mutation reset at teardown. Stop transforming and issuing run requests at
`_finish`. Keep handling transport controls and `Net` messages, and start
applying run state again on the next `Net._start_run`.

## 4. Full callsign cleaning

The Full game handshake truncates the name to 32 characters without the Thin
callsign cleanup. `Net._request_name` trims it to 18 and ignores empty names.
Use a short printable callsign and render all names and chat as plain text.

## 5. Packed array and typed dictionary decoding

A Full client must understand both the Godot built-in type word before a typed
binary array's count and tagged dictionaries with non-string keys in JSON.
Mutation lists use typed arrays even when empty; the lobby roster uses integer
keys, and the puddle sync uses NodePath keys. The worked examples in
[spec-full.md](spec-full.md#10-worked-binary-examples) and the matching
[JSON mapping](spec-full.md#7-variant--json-mapping) show both cases.
