# QSO73 Windows portable test build — third-party notices

The Windows modem engine is based on RFnexus/modem73-win commit ed2a06b21ae2f2eef57e75dcf65013c298da7d6f (2.4.2): https://github.com/RFnexus/modem73-win

QSO73 modifications add SIGBREAK shutdown handling, AX.25 sender/PING request metadata, headless activity telemetry and UTF-8 process manifests. Original notices are preserved in windows/vendor/modem73-win. This source distribution contains all engine dependencies needed by the Windows builder.

- modem73-win: Unlicense, in licenses/modem73-win.txt.
- aicodix DSP/code/modem: corresponding original licenses in licenses/aicodix-*.txt.
- miniaudio: public domain or MIT No Attribution, full dual notice in licenses/miniaudio-source-and-license.h.
- cJSON: MIT, full notice in licenses/cJSON-source-and-license.h. Used by the engine and QSO73 protocol implementation.
- HIDAPI: this distribution uses the BSD option; licenses/LICENSE-bsd.txt contains the license. Other upstream license choices are retained alongside it.

The headless modem build links the vendored PDCurses sources; their public-domain notice is included in licenses/pdcurses-README.md. See also the mingw-w64 runtime notices in licenses/mingw-runtime.txt. The compiler links its support runtimes statically; GCC runtime redistribution is governed by the GCC Runtime Library Exception, reproduced in licenses/gcc-runtime-exception.txt (with GPLv3 in licenses/gcc-gpl3.txt).


Hamlib 4.7.2 is bundled from the official Windows x64 release, unchanged: https://github.com/Hamlib/Hamlib/releases/tag/4.7.2 . Hamlib's library is LGPL v2.1 or later and its utilities (including rigctld/rigctl) are GPL v2 or later. Original LICENSE.txt, COPYING.txt and COPYING.LIB.txt and documentation remain in hamlib/. Complete corresponding Hamlib source is in hamlib/source/hamlib-4.7.2.tar.gz. The Hamlib package includes libusb-1.0.dll (1.0.24.11584), LGPL v2.1 or later; corresponding libusb 1.0.24 source and notices are in hamlib/source/libusb-1.0.24.tar.bz2. Adjacent libgcc and winpthread runtime DLLs are from the unchanged upstream Windows package; compiler runtime notices are also retained in licenses/.
