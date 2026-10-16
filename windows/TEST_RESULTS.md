# QSO73 1.1.0 Windows — validation and testing status

The Windows x64 client and bundled engine are cross-compiled on macOS. Windows remains a testing build. Earlier tester feedback confirmed CAT connection and over-the-air transmission; the new 1.1.0 Windows GUI controls require verification on Windows hardware.

## Local checks

- Swift/C++ bidirectional packet, channel/direct, PING, Heard and PSK Reporter fixtures pass.
- Matching modem PHY/DSP definitions, waveform round trips, AX.25 metadata and decoder-control telemetry checks pass.
- Portable Hamlib model/COM/baud validation and DLL closure pass: 61 official Hamlib files and 22 x64 executables/DLLs are checked.
- Activity console wrapping, UTC/color classification, link safety/DNS rejection, gain/audio VU telemetry and field validation checks pass.
- ADIF 3.1.6 UTC rollover, field lengths, calendar/frequency rejection, contact persistence and macOS/Windows fixture matching pass. ADIF header versions now identify both clients as 1.1.0.
- New directory tests cover JSON persistence/reload, received beacon/PING grids, favorite-preserving Clear, individual delete, full reset and invalid records. A bad saved file is preserved until explicit Full reset.
- Shared offline map checks cover 4/6/8-character Maidenhead grid centers, invalid grids, safe text labels, no remote resources and Default/CP/Crimson CSS. The actual map opened and centered a sample station in a macOS browser. Windows embeds the same HTML as a PE resource.
- UI source checks cover owner-drawn tabs/meters, shared theme redraw, contact dialog colors and preserved control visibility.

## Windows hardware verification still needed

Verify the Contacts/Favorites tab, individual deletion and confirmation dialogs, persisted data after restart, themed local-map launch, Crimson rendering, Stop/restart, device routing and two-station operation on Windows. No Windows GUI execution or radio transmission was performed by these local checks. TQSL signing/LoTW acceptance requires the operator's certificate and station location; QSO73 exports unsigned ADIF locally.

## Package contents and personal data

The portable folder includes QSO73.exe, QSO73-Activity.exe, modem73, official Hamlib 4.7.2 runtime/dependencies, corresponding Hamlib/libusb source archives, licenses and the current manual. The offline map is embedded in QSO73.exe. Distribution uses an explicit whitelist, excluding settings.json, contacts.json, station-directory.json, operator logs and test data. Keep those personal files from an existing portable installation when replacing its program files.
