# QSO73 Windows test 7 — validation

Validated on macOS with the installed x86_64-w64-mingw32 cross-compiler.

- QSO73.exe, QSO73-Activity.exe and modem73.exe compiled as x64 Windows PE executables.
- CAT MHz formatting rejects error replies and preserves six decimal places. Console line wrapping is tested beyond 32 KB, including CRLF and blank lines.
- Both executables link their compiler support runtimes statically. QSO73 and modem73 import Windows system DLLs without MSYS2 or Python. The bundled Hamlib utilities load adjacent Hamlib/libusb/compiler runtime DLLs; package dependency closure is checked.
- C++ protocol tests pass: callsign/channel validation, UTF-8 and payload bounds, KISS escapes and segmented framing, channel/direct routing, discovery, duplicate suppression, unread counts, topic updates and heard-user expiry.
- Six C++ Windows event fixtures (message, join, leave, topic, invitation and direct message) are decoded and routed by the actual Swift Mac implementation.
- Six Swift Mac event fixtures are decoded by the Windows protocol implementation.
- Actual DSP round trips from the pinned Windows-port source pass for OFDM QPSK 1/2, ROBUST RDM-600 and MFSK-16, with no audio devices or RF transmission.
- All 102 relevant PHY/DSP source files and fragmentation/reassembly definitions match the pinned Mac engine.
- Build shell scripts pass bash syntax checks; the Windows PowerShell launcher has been inspected but cannot be executed on this Mac.

- Hamlib Windows/source archives match the official published SHA-256 values. Radio catalog parsing, exact model/COM/baud arguments, CAT PTT selection local binding and CAT frequency-response readiness checks have native C++ tests.

Tester feedback for Windows test 2 confirms radio connection and over-the-air message transmission. New test 7 activity console, Beacon Now and live CAT frequency display still need Windows hardware verification. Windows audio levels, graceful shutdown and two-radio conversations have not been independently verified here. Follow START-HERE.md / README.md for the first hardware test.

Reproduce the Mac-side compatibility/DSP checks from the full QSO73 workspace with `windows/test-mac-interop.sh`. The Windows builder source ZIP includes the C++ tests; compile them in MinGW64 against the included cJSON source to run them on Windows.


Test 7 adds PING on both platforms and fixes Windows end-of-transcript scrolling. PING request/reply fixtures pass in both directions between C++ and Swift; tests cover opt-in behavior, missing measurements, duplicate suppression, no reply loops, per-source rate limiting and cancellation. The dashboard has a tested 21-row summary with numeric live-data and unavailable-data handling. Windows engine instrumentation supplies actual TX completion counters/history, audio level, DCD and last CSMA window/quiet values. Hardware verification remains outstanding for the new controls.

Test 7: both engines build with decoder-only telemetry and 200 ms state heartbeats. A loopback control-port test verifies green/idle events and interleaved responses. Mac socket integration verifies decoder activation and clearing while DCD/audio remain active, plus disconnect reset; minimum-size chat layout passes with the indicator. Windows GUI is cross-compiled; its new indicator still needs a Windows radio test.

Test 7 adds opt-in PSK Reporter with off-by-default saved settings, an independent DNS/UDP worker, 30-second CAT freshness, actual decoded AX.25 station/SNR metadata, five-minute dedup and batching. Swift and C++ encoders produce identical IPFIX bytes verified by an independent Python parser. Policy tests cover SSIDs, own calls, stale/history data, frequency offsets, queue bounds, disable/re-enable and missing CAT. A test-only analyzer datagram was submitted to the documented port; its result page returned HTTP 403, so server acceptance remains unconfirmed. A native macOS service test receives a complete IPFIX datagram on loopback UDP and verifies immediate disable. Existing chat/channel/CAT socket and minimum-window layout tests pass. Actual map delivery and Windows radio integration require field verification.

Test 7: native Swift/C++ Heard fixtures interoperate; policy tests cover last-hour history, SSID-zero/exact/base lookup, unavailable SNR, multi-station QST responses, matching request IDs, duplicates, rate limits and busy expiry. Simulated control/KISS stations exercise recent, measured-SNR specific and stale/not-heard replies. UTC/category and beacon-countdown tests pass. macOS message colors are measured above 4.5:1 contrast in both themes. Both URL validators/DNS parsers reject unsafe schemes, private/malware answers, wrong/truncated/compression-loop responses. Live Cloudflare/Quad9 public-domain checks pass without opening a browser. Windows GUI now uses system Rich Edit and WinHTTP HTTP/2; its actual rendering, links and countdown still need a Windows test.
