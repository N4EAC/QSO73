# QSO73

[![macOS](https://img.shields.io/badge/macOS-13%2B%20%C2%B7%20Apple%20Silicon-007AFF?logo=apple&logoColor=white)](https://github.com/N4EAC/QSO73/releases/tag/v0.4.14)
[![Windows](https://img.shields.io/badge/Windows-10%2F11%20x64%20%C2%B7%20TESTING-orange)](https://github.com/N4EAC/QSO73/releases/tag/v0.4.13-windows-test11)
[![Modem](https://img.shields.io/badge/modem73-2.4.2-008C95)](https://github.com/RFnexus/modem73)

QSO73 is an amateur-radio chat client using modem73 for HF, VHF and UHF packet communication. It offers QST broadcasts, addressed chat, shared channels with topics and heard-user lists, direct conversations, signal reports and optional beacons. Channels and direct conversations use QSO73's own radio protocol; no Internet connection or central chat server is needed.

Source, documentation and release downloads are publicly available in this repository.

## Downloads

| Platform | Version | Package | Status |
| --- | --- | --- | --- |
| macOS 13+, Apple Silicon | 0.4.14 | [macOS DMG](https://github.com/N4EAC/QSO73/releases/download/v0.4.14/QSO73-0.4.14-macOS-arm64.dmg) | Development build |
| Windows 10 (1903+) / Windows 11, x64 | 0.4.13 test 11 | [Portable Windows ZIP](https://github.com/N4EAC/QSO73/releases/download/v0.4.13-windows-test11/QSO73-0.4.13-windows-x64-test11.zip) | **Testing / prerelease** |

Use the platform-specific releases above. Windows remains a testing build with a smaller feature set. The macOS app targets Apple Silicon; an Intel Mac build is not supplied.

## User manual

Read the current [user manual (PDF)](docs/QSO73-User-Manual.pdf) or [editable manual](USER_MANUAL.md). It covers radio/audio setup, modem families and modes, channel creation and discovery, topics, user lists, direct conversations, macros, beacons and activity displays. Page 17 covers PING requests and measured automatic replies; page 16 covers the Windows portable testing build. Pages 19-20 cover Heard queries, UTC message colors, checked links and the Windows beacon countdown.

The PDF is also included in the macOS DMG and Windows portable ZIP. See the [Windows setup guide](windows/README.md) for its detailed test procedure and controls.

## macOS setup

1. Open the DMG and drag **QSO73.app** into **Applications**.
2. Open QSO73 and configure your callsign, grid, radio USB input/output and modem mode in Station Settings.
3. For rigctld CAT/PTT, install Hamlib's `rigctld` on the Mac and select the correct radio model, serial port and baud. QSO73 starts or reuses the local daemon automatically.
4. Save settings and start the modem. Confirm selected audio devices and CAT frequency readback before an agreed short radio test.

The macOS app is ad-hoc signed and is not notarized. The modem processes at 48 kHz and converts hardware sample rates automatically; the FT-710 USB audio device used during development was observed at 44.1 kHz.

## Windows setup — testing

1. Extract the entire portable ZIP to a writable folder. Keep **QSO73.exe**, **QSO73-Activity.exe**, **engine/** and **hamlib/** together.
2. Open Setup, enter your callsign/grid and select the radio's USB audio devices using Refresh audio devices.
3. With rigctl PTT selected, choose the radio model, CAT COM port and matching baud. **Hamlib 4.7.2 is bundled**; no separate installation, terminal command or PATH change is needed.
4. Save settings and start the modem. QSO73 starts its bundled rigctld, checks a frequency read and starts modem73. Stop Modem releases PTT and closes its processes.

Test 11 includes a separate text-console activity display, **Beacon Now** and actual CAT frequency readback. In the activity console, use PgUp/PgDn or arrows to navigate, Space to pause the display and Q/Esc to close it. Closing the display keeps the modem and chat running.

A tester reported successful radio connection and over-the-air transmission with Windows test 2. The new test 11 controls still need Windows hardware verification. See the [validation report](windows/TEST_RESULTS.md).

## Conversations and airtime

- Radio Chat sends ordinary AX.25 UI packets, with QST as the default broadcast destination.
- Enter `#hfchat` and click Open / Join to create or join a shared channel. Discovery alone does not join you.
- Use Topic and Users in a channel. The user list shows recently heard stations, rather than guaranteed live presence.
- Enter a callsign in Open / Join to start a separate direct conversation.
- F1 CQ, F2 measured-SNR report, F3 73 and F4 custom message submit plain Radio Chat packets immediately; modem carrier sensing controls actual airtime.
- Station beacons and optional empty-channel announcements share the same modem queue and radio frequency as chat.

Messages have no delivery acknowledgment or automatic retry. Direct messages are addressed traffic, readable over the air. For channels and direct chat, both stations need QSO73's conversation protocol. See [protocol and behavior](CHAT_PROTOCOL.md).

## Build from source

macOS requires Xcode Command Line Tools:

```sh
./build.sh
./test.sh
```

For Windows, install MSYS2 MinGW64 build tools, then run **windows/Build-Windows.ps1**, or use **windows/build.sh** in MinGW64. See [builder instructions](windows/README.md). Testers running the portable ZIP do not need MSYS2, Python or WSL. The Windows builder verifies and bundles the pinned official Hamlib package and its adjacent DLLs.

## Source layout and third-party components

- **Sources/**: macOS client and radio/chat integration.
- **Tests/**: local protocol, socket, DSP, radio and layout checks.
- **windows/**: Windows client, activity console, builder and tests.
- **vendor/**: pinned modem73 source and dependencies.
- **Assets/**: QSO73 icon artwork.
- **docs/**: current printable manual.

Local checks include packet interoperability in both directions between the C++ Windows and Swift macOS implementations, real DSP round trips and Windows package dependency checks. These do not replace radio hardware and station-to-station testing.

Third-party source and notices are preserved. See [macOS notices](THIRD_PARTY_NOTICES.md) and [Windows notices](windows/THIRD_PARTY_NOTICES.md). The Windows package includes the corresponding Hamlib and libusb source archives.


## PING and Windows activity updates

Both platforms now have a PING button and saved Auto PING replies option (off by default). PING targets To in Radio Chat, the selected direct callsign, or QST from a channel. Automatic replies provide the responder's callsign, grid and measured SNR of the specific request. Both operators need these updated builds and current bundled engines. No matching measurement means no reply. Replies wait for idle/empty-queue conditions, are rate limited, and cannot create reply loops.

Windows test 11 explicitly scrolls new conversation messages to the end and opens a compact modem-style activity dashboard showing signal/SNR/BER, CSMA timing, occupancy and activity histories, real RX/TX statistics, recent frames and CAT frequency. Full raw diagnostics and logs remain available below the summary.

## Decoder reception indicator

A compact Decoding rectangle appears beside RX/TX on macOS and beside frequency on Windows. It turns green during modem frame reception and gray when inactive, transmitting or disconnected. The bundled engine reports actual decoder activity rather than audio level or CSMA busy state. A green indication does not guarantee a valid message.

## PSK Reporter reception reporting

Version 0.4.10 introduced optional PSK Reporter on both platforms. Enable it in macOS Station Settings or beside Grid on Windows. It is off by default; your callsign/grid, working receive audio and CAT frequency/mode no older than 30 seconds are required. Decoded other-station receptions include callsign, measured SNR, RF center frequency and time. Chat text is not uploaded.

Reports use ADIF PKT and identify QSO73 in the software field. USB/LSB frequency includes the 1500 Hz modem center offset; FM uses the dial. AX.25 SSIDs are removed. Duplicate suppression and batching use a five-minute interval. Uploads use a separate Internet connection and no radio airtime. Disable cancels unsent reports. UDP submission is not confirmation of map delivery.

Native encoding/policy, independent IPFIX parsing and loopback UDP transport tests pass. PSK Reporter’s public test analyzer returned HTTP 403, so server/map acceptance remains unconfirmed. Windows radio verification is also pending. See [implementation and validation](PSK_REPORTER.md) and the updated manual.


## Heard queries, message colors and checked links

Version 0.4.11 introduced **Heard...** beside PING on both platforms. With To set to QST, ask all listening QSO73 stations for up to three recent callsigns, or ask whether they heard a specific callsign. Select a station to query it alone. **Auto Heard replies** is saved and off by default; responding operators must enable it. Replies include reception age and measured SNR when available, use a randomized delay, share idle/queue gating, and are rate limited. History is limited to the past hour of the current modem session. See [Heard protocol](HEARD_PROTOCOL.md).

Messages show UTC timestamps. Your operator messages are blue, generated queries/replies and announcements are orange, and received operator messages are green. Opaque colors/backgrounds maintain text contrast. Windows test 11 uses a rich-text transcript and shows a live beacon countdown, including paused and waiting-for-idle states.

Clicked HTTPS URLs are checked against the free Cloudflare and Quad9 malware-filtering DNS services before opening the default browser. No API key is required. Both providers must return a valid public resolution; invalid URLs, local/private destinations, blocked domains, failed checks and inconclusive results do not open. Only the hostname is submitted, and arriving messages never trigger automatic lookups. These are known-malicious-domain checks, not full URL or page scans; they cannot guarantee safety of paths, redirects or newly malicious sites. See [checked-link policy](LINK_SECURITY.md).

Swift/C++ wire interoperability, local Heard request/reply integration, actual color contrast and bounded macOS layouts, URL/DNS rejection tests, live provider checks, builds and portable dependency checks pass. Windows GUI links/colors/countdown and station-to-station radio operation remain pending tester verification.


## Audio VUs and Clear controls

Version 0.4.12 introduced live RX/TX audio meters to both clients. RX measures selected input samples; TX measures output samples after modem audio gain, including idle silence. RMS and peak are measured over approximately 100 ms and reported about five times per second. The bars span −60 to 0 dBFS, with green/yellow/red headroom bands and a peak marker. Missing or stale measurements show unavailable. These are audio levels, not radio RF/ALC readings. An older external engine may not supply telemetry.

**Clear** removes messages only in the displayed Radio Chat/channel/direct conversation; other conversations, heard history, deduplication, settings and active modem work remain. It also cancels a pending link check. **Clear Draft** empties that conversation's unsent editor. The updated manual covers these controls on page 21.

PCM level/gain/silence/staleness tests, live audio/control framing, macOS meter layouts, existing radio/chat regressions and portable dependency checks pass. Windows GUI/hardware meter verification remains pending.


Windows test 11 corrects the owner-draw styles for RX/TX audio meters and the Decoding indicator, and prevents startup overlap with the transcript. Both meter labels remain visible offline, with unavailable readings until audio telemetry arrives.


## Setup, gain, themes and contact logging (0.4.13)

Windows test 11 separates **Chat**, **Setup** and **Contact Log** into tabs. Start/Stop stays at the top; **Stop Modem keeps the client open**, releases PTT and closes its owned modem/Hamlib processes. The shutdown path now protects the GUI from the console CTRL_BREAK signal. Frequency entry is in a separately labeled radio-frequency group on both clients.

Both clients offer RX/TX software gain from **−20 to +20 dB** (attenuation through 10x amplification), saved for startup and applied while idle. RX gain acts before decoding; TX gain multiplies the existing TX audio percentage. Adjusted samples are limited at digital full scale and reflected in the VUs. Watch peak levels: excessive gain clips and amplifies noise. Use the updated bundled engine for this feature.

Choose **Default** or **CP (Cyberpunk)** in Setup/Station Settings. CP uses dark purple/navy surfaces, cyan accents and magenta outlines. Themes apply immediately and persist, preserving blue/orange/green message categories.

**Contact Log** creates and edits operator-reviewed contacts, storing them locally and exporting ADIF 3.1.6 .adi files. Records contain UTC start/end dates/times, callsign/station/operator, MHz frequency, derived band and MODE=PKT, with optional grids, reports and notes. AX.25 SSIDs are stripped; portable slash callsigns are accepted. Contacts are never auto-created from packets or beacons. Use **TQSL** with your certificate/station location to sign and submit the exported file to LoTW; QSO73 does not directly upload unsigned ADIF. See [ARRL's submission instructions](https://lotw.arrl.org/lotw-help/submitting-qsos/).

The 23-page manual covers Setup/gain/themes on page 22 and contacts/LoTW on page 23. Windows contacts.json and settings.json are personal files: preserve them during portable-folder updates; release ZIPs exclude them.

Validation includes gain/silence/clipping PCM checks, live gain command/readback, existing CAT/chat/reporting regressions, protocol and DSP interoperability, identical macOS/Windows ADIF fixtures with independent field-length parsing, contact save/edit/corruption checks, bounded macOS theme/contact layouts, and portable dependency checks. Actual Windows GUI/radio Stop/restart verification and TQSL/LoTW acceptance with a station certificate remain pending.

macOS 0.4.14 removes the contact editor’s fixed-height scrolling form. All fields and Save Contact stay visible, with the saved-contact list using the remaining window space.
