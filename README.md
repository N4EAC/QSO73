# QSO73

[![macOS](https://img.shields.io/badge/macOS-13%2B%20%C2%B7%20Apple%20Silicon-007AFF?logo=apple&logoColor=white)](https://github.com/N4EAC/QSO73/releases/tag/v0.4.8)
[![Windows](https://img.shields.io/badge/Windows-10%2F11%20x64%20%C2%B7%20TESTING-orange)](https://github.com/N4EAC/QSO73/releases/tag/v0.4.8-windows-test4)
[![Modem](https://img.shields.io/badge/modem73-2.4.2-008C95)](https://github.com/RFnexus/modem73)

QSO73 is an amateur-radio chat client using modem73 for HF, VHF and UHF packet communication. It offers QST broadcasts, addressed chat, shared channels with topics and heard-user lists, direct conversations, signal reports and optional beacons. Channels and direct conversations use QSO73's own radio protocol; no Internet connection or central chat server is needed.

Source, documentation and release downloads are publicly available in this repository.

## Downloads

| Platform | Version | Package | Status |
| --- | --- | --- | --- |
| macOS 13+, Apple Silicon | 0.4.8 | [macOS DMG](https://github.com/N4EAC/QSO73/releases/download/v0.4.8/QSO73-0.4.8-macOS-arm64.dmg) | Development build |
| Windows 10 (1903+) / Windows 11, x64 | 0.4.8 test 4 | [Portable Windows ZIP](https://github.com/N4EAC/QSO73/releases/download/v0.4.8-windows-test4/QSO73-0.4.8-windows-x64-test4.zip) | **Testing / prerelease** |

Use the platform-specific releases above. Windows remains a testing build with a smaller feature set. The macOS app targets Apple Silicon; an Intel Mac build is not supplied.

## User manual

Read the current [user manual (PDF)](docs/QSO73-User-Manual.pdf) or [editable manual](USER_MANUAL.md). It covers radio/audio setup, modem families and modes, channel creation and discovery, topics, user lists, direct conversations, macros, beacons and activity displays. Page 17 covers PING requests and measured automatic replies; page 16 covers the Windows portable testing build.

The PDF is also included in the macOS DMG and Windows portable ZIP. See the [Windows setup guide](windows/README.md) for its detailed test procedure and controls.

## macOS setup

1. Open the DMG and drag **QSO73.app** into **Applications**.
2. Open QSO73 and configure your callsign, grid, radio USB input/output and modem mode in Station Settings.
3. For rigctld CAT/PTT, install Hamlib's `rigctld` on the Mac and select the correct radio model, serial port and baud. QSO73 starts or reuses the local daemon automatically.
4. Save settings and start the modem. Confirm selected audio devices and CAT frequency readback before an agreed short radio test.

The macOS app is ad-hoc signed and is not notarized. The modem processes at 48 kHz and converts hardware sample rates automatically; the FT-710 USB audio device used during development was observed at 44.1 kHz.

## Windows setup — testing

1. Extract the entire portable ZIP to a writable folder. Keep **QSO73.exe**, **QSO73-Activity.exe**, **engine/** and **hamlib/** together.
2. Enter your callsign/grid and select the radio's USB audio devices using Refresh audio devices.
3. With rigctl PTT selected, choose the radio model, CAT COM port and matching baud. **Hamlib 4.7.2 is bundled**; no separate installation, terminal command or PATH change is needed.
4. Save settings and start the modem. QSO73 starts its bundled rigctld, checks a frequency read and starts modem73. Stop Modem releases PTT and closes its processes.

Test 4 includes a separate text-console activity display, **Beacon Now** and actual CAT frequency readback. In the activity console, use PgUp/PgDn or arrows to navigate, Space to pause the display and Q/Esc to close it. Closing the display keeps the modem and chat running.

A tester reported successful radio connection and over-the-air transmission with Windows test 2. The new test 4 controls still need Windows hardware verification. See the [validation report](windows/TEST_RESULTS.md).

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

Windows test 4 explicitly scrolls new conversation messages to the end and opens a compact modem-style activity dashboard showing signal/SNR/BER, CSMA timing, occupancy and activity histories, real RX/TX statistics, recent frames and CAT frequency. Full raw diagnostics and logs remain available below the summary.
