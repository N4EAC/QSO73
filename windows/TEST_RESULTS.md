# QSO73 Windows test 3 — validation

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

Tester feedback for Windows test 2 confirms radio connection and over-the-air message transmission. New test 3 activity console, Beacon Now and live CAT frequency display still need Windows hardware verification. Windows audio levels, graceful shutdown and two-radio conversations have not been independently verified here. Follow START-HERE.md / README.md for the first hardware test.

Reproduce the Mac-side compatibility/DSP checks from the full QSO73 workspace with `windows/test-mac-interop.sh`. The Windows builder source ZIP includes the C++ tests; compile them in MinGW64 against the included cJSON source to run them on Windows.
