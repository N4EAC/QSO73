# QSO73 modem73 integration

Source: [RFnexus/modem73](https://github.com/RFnexus/modem73), pinned commit `3a37c290a5330bd95f4f283feafc5ba5605bdc52`, upstream version 2.4.2.

## Client and transport

`Protocol.swift` implements bounded KISS and JSON framing, AX.25 UI packets/address validation, mode settings and process arguments. Control messages use a four-byte big-endian length followed by JSON. Defaults are KISS TCP 8001 and control TCP 8073. Incoming chat accepts the station's exact callsign/SSID and QST/CQ/ALL broadcasts. PHY callsigns omit the AX.25 SSID.

`Modem.swift` owns the two socket connections, serialized control requests, status polling, packet filtering, CAT reads and frame metadata. Requests have timeouts and session-generation guards. Events do not consume pending request responses. A timed-out control session is closed so late replies cannot be assigned to another request.

`EmbeddedEngine.swift` owns process launch, audio permission, device enumeration, logs and termination. Arguments are passed directly to Process without a shell. Ports are checked before launch. The helper starts with an explicit empty configuration and localhost-only socket bindings. The selected engine can be bundled or independently installed.

`RigController.swift` probes rigctld readiness, starts a configured local daemon if required and available, reuses an existing service, and stops only services owned by this client. CAT reads use `f`/`m`; frequency changes use `F <Hz>` and a confirming readback. Radio-meter reads rotate without invoking tuner/PTT actions. Engine shutdown is allowed to release PTT before an owned daemon is stopped.

## Interface and persistence

`App.swift` exposes Radio Chat, Modem Activity and Station Settings. `ActivityView.swift` provides the compact dashboard and diagnostic sheets; `ActivityPresentation.swift` manages one detached window or a docked chat panel. Views share the same modem instance. Draft, destination and frequency input remain in shared workspace state through layout changes.

`SettingsProfile.swift` provides versioned native QSO73 JSON profiles, validating station, modem, radio and optional macro settings before import. Preferences retain the QSO73 app identity. Engine selection is stored separately from station profiles.

`EngineInstallation.swift` stages independent engines in unique Application Support folders, copying adjacent bundled libraries. Native-format, CLI and audio enumeration probes run before committing a selection. Failed installation leaves the previous selection intact. An executable SHA-256 check detects later modification. The bundled engine remains available. These probes do not replace validation of a live compatible KISS/control API or hardware commissioning.

`RadioMacros.swift` expands configurable CQ/report/73 messages with validated destinations, measured SNR and the packet byte limit. App-wide F1/F2/F3 menu shortcuts and chat buttons submit them through the existing send path without modifying the draft. Report lookup is limited to sender-labelled frames from the target within ten minutes.

`Beacon.swift` validates callsign/grid payloads and owns a single main-actor scheduler attached to the modem lifecycle. It sends QST packet beacons only after ready/idle/empty-queue checks, retries due requests without queue accumulation and schedules the next deadline from submission rather than catching up missed intervals. BeaconControls observes the controller directly, including when chat layouts change.

## Local engine patches

- Refuse unavailable explicitly selected audio devices instead of silently choosing defaults.
- Verify the CoreAudio output unit's current-device UID against the requested playback device before starting and before writes.
- Correct the miniaudio CoreAudio device-selection error return to use the failing status.
- Report actual audio routes/rates and input level.
- Expose CSMA gate telemetry and an eight-frame encoded-TX history in get_status.
- Extract source callsign/SSID from two-address AX.25 UI packets into receive metadata for accurate report matching.
- Count RX frames delivered by the decoder and non-beacon TX frames encoded for transmission.

Waveforms, CSMA decisions and PTT behavior retain upstream implementations. The engine processes 48 kHz audio, with hardware-rate conversion through miniaudio. See ACTIVITY_DATA.md for field coverage and counter semantics. Extra telemetry may be absent in independently installed upstream engines.

## Validation and limits

The headless engine and SwiftUI client compile for macOS 13 on Apple Silicon. The engine links system libraries. Tests exercise protocol/settings checks, native profile round trips and invalid-profile rejection, local chat/control/CAT fixtures, real OFDM/ROBUST/MFSK PCM round trips, fake-rigctld lifecycle, missing-output handling, 48↔44.1 kHz conversion and independent engine installation/rollback. Tests do not transmit RF.

FT-710 USB audio was observed at 44.1 kHz; user testing confirmed transmit audio through the radio. CAT readback confirmed 7.105 MHz. Radio-meter support, over-the-air decoding, older macOS runtime behavior, Intel builds and distribution signing/notarization remain to be verified.

The control API is unauthenticated. Bundled local sockets bind to localhost; external engines need a trusted network or tunnel. A remote radio needs a corresponding audio path or an engine running at that station. Chat is unacknowledged AX.25 UI traffic; reliable sessions, mail, file transfers and automatic logging are outside the current implementation.


## QSO73 0.4.8 PING metadata

Both bundled engines include the QSO73 PING request UUID as `application_id` in decoded-frame metadata. The UUID is extracted from the completed AX.25 UI payload, including reassembled packets, alongside the source callsign/SSID. Automatic PING replies match this metadata to the received request before using its SNR. The Windows headless engine also exports audio level, DCD, last CSMA timing, completed TX count and recent TX frame data for the console dashboard. PHY and fragmentation code remain unchanged.
