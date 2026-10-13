# Bundled modem73 engine

Source: https://github.com/RFnexus/modem73
Pinned commit: 3a37c290a5330bd95f4f283feafc5ba5605bdc52
Upstream version label: 2.4.2

The application bundles a headless build of modem73 with local patches that refuse audio-device fallback, verify CoreAudio playback routing, report sample rates, and correct a CoreAudio device-selection error return. See MODEM73_INTEGRATION.md for details. It does not use the terminal UI, direct Hamlib library linkage, or CM108/hidapi. rigctld, VOX, and serial PTT are available from the engine.

modem73 is released under the Unlicense. The aicodix DSP, coding and modem dependencies carry permissive license notices reproduced in Contents/Resources/Licenses. miniaudio is available under a choice of public-domain or MIT terms; this integration uses the public-domain option (see the license at the end of deps/miniaudio.h). cJSON is MIT-licensed; its notice follows.

## cJSON

Copyright (c) 2009-2017 Dave Gamble and cJSON contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
