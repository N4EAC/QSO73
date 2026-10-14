# QSO73 Windows portable test client

**Version 0.4.12 Windows test 8 — Windows 10 (1903 or later) / Windows 11, x64.**

This is an early Windows companion for testing with QSO73 0.4.12 on macOS. It implements the same QSO73 v1 channel/direct protocol and bundles the official Windows modem73 engine. Extract the **entire folder** to a writable directory and run **QSO73.exe**. No installer, Python, MSYS2 or WSL is required by the tester. Keep both the `engine` and `hamlib` folders beside the client. Hamlib 4.7.2 and all its runtime DLLs are included; no separate Hamlib installation or PATH changes are needed. Settings and logs stay inside the portable folder. Running inside the ZIP is not supported.

The Windows executable has been cross-compiled on macOS. Packet compatibility and the modem DSP have local automated checks. A tester has reported successful radio connection and over-the-air message transmission with Windows test 2. The PING controls, improved activity dashboard and automatic chat scrolling in test 8 still require verification on Windows hardware. The upstream Windows modem port is itself experimental. This package is unsigned.

## Prepare the Windows station

1. Connect the radio's USB audio interface. Install its manufacturer's driver if required by that radio. Make sure Windows allows desktop applications to use the audio input.
2. Open QSO73. Enter your own **Station callsign** (optional SSID 0–15) and **Grid**.
3. Click **Refresh audio devices**. Select the radio USB device under **Radio RX audio input** and **Radio TX audio output**. Default speakers/microphone are deliberately excluded. Refresh again after reconnecting a radio. If two devices have the same name, disconnect the unused one for this test.
4. Choose **robust / RDM-600S** to start an HF trial. This matches the suggested Mac starting mode. Stop the modem to change settings. OFDM choices use rate 1/2; MFSK modes are also available. Receivers decode the supported modem families automatically.
5. Choose **rigctl** PTT (default). Choose your exact **Radio model (bundled Hamlib)**, **CAT COM port** and **baud** matching the radio menu. The model list comes from the bundled Hamlib and shows the number, brand and model. COM ports are detected locally; refresh after reconnecting a radio. Some radios expose two serial ports: select the CAT port specified by the manufacturer's documentation. Stop other radio programs that hold that port. Alternatively choose **vox** if the radio is configured for data VOX; no CAT daemon is started in that mode.
6. Click **Save settings**, then **Start Modem**. QSO73 starts its bundled rigctld on localhost, waits for a successful radio frequency read, then starts modem73. Wait for **Connected**, **Audio ready** and **CAT connected** in the bottom status line. Transmission is inhibited when audio or rigctl PTT is unavailable or status is stale. Failed CAT startup reports an error; inspect **Modem Activity** or `rigctld.log` for details.
7. Set the radio to its USB data mode and select USB/audio-interface input as its data modulation source. Begin at a low radio power and suitable TX audio level (QSO73 default 25%). Verify the radio's own ALC and power indication on the first agreed short transmission.

You do not need to enter a rigctld command or configure TCP ports. CAT uses internal localhost port 4532. If another service already occupies it, QSO73 asks you to stop that service instead of attaching to an unknown radio. **Stop Modem** releases PTT, stops modem73 and closes the rigctld process it started. Exiting also stops both processes; a Windows job object prevents orphaned children after the client exits unexpectedly.

**Set Frequency** accepts MHz (for example `7.105`) and requires rigctl and an idle modem; check the radio dial afterward. It does not send a tuning carrier. Hamlib support varies by model and driver; correct CAT readback and actual PTT must be checked on the tester's radio.

## First Mac-to-Windows test

Agree on the dial frequency, sideband, radio passband and an appropriate operating frequency for both stations. Use actual station callsigns and compatible modem settings.

1. Start with **Radio Chat**, **To: QST**. Send a short greeting using **Send Packet**. Confirm it appears as received at the other station, then ask that station to reply. A local “You” entry confirms socket submission, not radio delivery.
2. On both clients, enter **#hfchat** in the channel/callsign box and click **Open / Join**. The name is case insensitive. With audio ready, joining sends a membership announcement. If joined offline, use Open / Join again once connected.
3. Select **#hfchat** in **Conversation**, then exchange a short message in each direction. The channel routing data shares the 200-byte UTF-8 limit; shorten the message if instructed.
4. Click **Topic...**, enter a short topic and click **Transmit Topic**. Check the other station sees it. An empty topic clears it. Any member can change a topic.
5. Click **Users...** to see callsigns heard in the channel within ten minutes, plus your own locally joined callsign. This is a heard list rather than confirmed live presence. In this Windows test UI, copy/type a listed callsign into **Open / Join** to open a direct conversation.
6. Enter the other operator's callsign in **Open / Join**, then send from the resulting direct conversation. Verify the received message appears in a separate direct conversation at the other end. Switch back to the channel with Conversation.
7. Select **Radio Chat** to return to plain chat; To resets to QST. To is editable for an addressed plain packet and also collects received callsigns. Addressed plain packets are separate from QSO73 direct conversations.
8. Before finishing, use **Export Chat** at each end and keep `engine.log` if there were problems. Click **Stop Modem** before unplugging the radio or exiting.

Discovery from another station's channel traffic/invitation does not automatically join you. Select the discovered channel and click **Open / Join** to subscribe. Messages received before joining are not replayed. **Leave** announces departure when connected and removes your local subscription. Drafts and unread counts are separate for each conversation.

Channels and direct messages use QSO73's own radio protocol; no Internet or IRC server is needed. All conversations share the same frequency and modem queue. Private messages are addressed but readable over the air. There is no delivery acknowledgment, automatic retry or authenticated sender identity.

## Macros, beacons and activity

- **F1 / CQ:** immediately submits CQ to QST. **F2 / SNR:** sends a measured report to the station in To; requires a decoded sender-labelled measurement from that station within ten minutes. **F3 / 73:** submits a closing message to To. **F4 / Custom:** uses the saved custom message; supports `{call}`, `{to}`, `{locator}`, `{snr}`. F keys always send plain Radio Chat packets and preserve the composer draft, even while a channel is selected.
- **Beacon Now:** request a one-shot QST beacon containing the saved callsign, grid and QSO73 version. Works while repeating Beacon is off. Requires a valid saved grid and ready audio/PTT; a busy modem defers it until idle with an empty queue. Repeated clicks while pending do not add duplicate requests. Stopping the modem cancels a pending request. If repeating Beacon is on, a successful submission restarts its interval.
- **Beacon:** optional station beacon every 1–60 minutes with callsign, grid and QSO73 title/version. The first beacon waits one full interval. It is off on every app launch in this test client. Changing the interval applies after the next submission; turn off/on to restart the countdown.
- **Announce channel:** optional repeated invitation for the currently joined channel, every 1–60 minutes. It includes the channel/topic and sender callsign. A received join/message from another station stops it. Only one channel can be announced at a time in this test build. It starts off on every app launch. Long topics are shortened to fit.
- Automatic submissions wait for fresh healthy status, idle modem and an empty queue; they share a five-second minimum spacing and do not send catch-up bursts. Disconnecting pauses them; reconnecting waits a fresh interval.
- **Modem Activity:** opens a separate Windows text console with a compact two-column modem73-style dashboard. It shows carrier/audio level, level bar, threshold, SNR/BER and history, CSMA busy/quiet/window/slot timing, occupancy history, sampled RX/TX activity, packet/error statistics, clients/queue, recent RX/TX frames and CAT frequency. Full raw status/configuration/recent-frame fields and control events remain below the dashboard, together with and the latest `engine.log` / `rigctld.log` output. Use **PgUp/PgDn**, **arrow keys**, **Home/End** to navigate, **Space** to pause/resume the display and **Q** or **Esc** to close it. Pause affects the display only; chat and the modem continue operating. Resize the console for a wider view. Closing it keeps the radio connection running, and clicking Modem Activity reopens it. No PowerShell or CMD commands are needed. Keep **QSO73-Activity.exe** in the portable folder.
- **CAT frequency display:** the actual radio readback appears beside Set Frequency in MHz, refreshed about every two seconds while the modem is not transmitting. During a longer transmission it may show **(last read)**; failed or unavailable CAT reads show **CAT: unavailable**. Stopping the modem clears it. The input field remains separate and changes the dial only when Set Frequency is clicked.


## Scope of this test build

Included: bundled Hamlib 4.7.2 with automatic rigctld lifecycle, radio-model dropdown, detected/editable CAT COM port and baud selection, local Windows modem lifecycle, explicit radio audio routing selection, rigctl/VOX PTT, ROBUST/OFDM/MFSK transmission, plain chat, channels, topics, heard users, direct chat, unread counts, per-conversation drafts, macros, automatic beacons/invitations, activity details and transcript export.

Not included: Mac settings-profile import, the Mac engine update/rollback interface, direct serial/CM108 PTT selection, docking activity, Mac meter graphics or CAT meter polling. These controls are not exposed in this client. Joined names and station settings persist; message history, topics, heard users, direct tabs, drafts and invitations are session-only. The UI retains up to 10,000 chat entries and exports the retained session.

## Build it on Windows

Only the **builder** needs MSYS2. The recipient of a built ZIP does not.

1. Install official MSYS2, then open **MSYS2 MinGW64**.
2. Install the build tools: `pacman -S --needed make zip unzip mingw-w64-x86_64-gcc`.
3. From Windows PowerShell, run `./Build-Windows.ps1` in this source folder. If MSYS2 is elsewhere, use `./Build-Windows.ps1 -MsysRoot 'D:\msys64'`.
4. The script builds the client and bundled engine and creates **dist/QSO73-0.4.12-windows-x64-test8.zip**. Share that ZIP, not just QSO73.exe.

Alternatively, in MinGW64, run `CXX=g++ CC=gcc WINDRES=windres ./build.sh`. On macOS/Linux with mingw-w64 available, run `./build.sh`. The source dependencies are vendored and pinned; no engine or Hamlib downloads occur during a build. `build.sh` can be rerun after editing the client. The root Mac build is unchanged.

## Sources

- Windows engine and its experimental status: https://github.com/RFnexus/modem73-win
- Hamlib Windows packages and documentation: https://github.com/Hamlib/Hamlib/releases
- Windows build environment: https://www.msys2.org/

Engine source: `ed2a06b21ae2f2eef57e75dcf65013c298da7d6f` (modem73 2.4.2). QSO73 integration patches add graceful SIGBREAK shutdown and sender/SSID extraction from decoded AX.25 frames for signal reports, plus UTF-8 process manifests for device names and folder paths. The DSP and fragmentation wire format remain unchanged. See THIRD_PARTY_NOTICES.md and licenses/ in the portable package.


Hamlib source and notices are included under **hamlib/source/** and **hamlib/** in the portable package. The official Hamlib binaries are unmodified. Its adjacent DLLs must remain in hamlib/bin; removing them breaks CAT. The builder verifies the pinned package and source checksums before packaging.


## PING

Click PING to request a measured signal report from To in Radio Chat. QST requests replies from listening stations; a direct conversation targets its callsign and a channel uses QST. Requests and replies appear in Radio Chat. Both stations need macOS 0.4.8 or later or Windows 0.4.8 test 4 or later with the current bundled engines.

Enable **Auto PING replies** at stations that should respond. This saved option is off by default. Replies contain the responder's callsign, saved grid and the measured SNR of the decoded request, matched by source and unique application ID. No matching measurement or invalid grid means no reply. The SNR is how the other station heard your request. Replies wait for idle audio/PTT and an empty queue, with at least two seconds for metadata and thirty seconds maximum waiting time. They share automatic-traffic spacing with beacons/invitations. Duplicate requests are ignored, each source is limited to one automatic reply per thirty seconds, and replies do not trigger replies. Disabling the option or stopping the modem clears pending replies; submitted packets cannot be withdrawn.

Incoming and submitted messages now scroll their selected conversation to the end. The console dashboard is sampled telemetry, rather than an FFT waterfall. Quiet/window timing describes the last CSMA acquisition; unavailable values are shown as --. TX counts and recent TX rows use engine transmission completion rather than socket submission.

The small Decoding rectangle beside the frequency turns green during modem frame reception and gray when idle, transmitting or disconnected. Green indicates a decoding attempt, not a guaranteed valid message. It requires the current bundled engine.

## PSK Reporter (optional)

Enable PSK Reporter beside Grid to upload decoded station receptions over the Internet. The setting is off by default and saved. It needs your callsign/grid, working audio and CAT frequency/mode no older than 30 seconds. Status appears below Save settings. Disable it at any time to cancel pending reports.

Reports contain received callsign, frame SNR, RF center frequency and time, plus your receiving callsign/grid and QSO73 version. Chat text is not uploaded. Reports use PKT; choose All modes or PKT on the PSK Reporter map. USB/LSB frequency includes the modem’s 1500 Hz center offset, while FM uses the dial. AX.25 SSIDs are removed. Batches upload about every five minutes; UDP submission does not confirm map delivery.

## Heard queries, UTC colors, links and countdown

Click Heard beside PING: leave its prompt blank for up to three recent callsigns, or enter a specific callsign. To=QST asks all listening stations; a callsign asks only that station. Replies return to the requester and appear in Radio Chat. Both ends need QSO73 0.4.12+. Enable Auto Heard replies at answering stations (off by default, saved). History covers up to one hour of the current modem session; it shows age and available SNR, supports exact SSIDs, excludes stale/unverified calls, and is cleared on disconnect. Allow one minute between queries. Broadcast responses use randomized delay, carrier sensing and queue/rate limits.

The transcript uses UTC headers with blue own messages, orange generated messages and green received operator messages, all opaque on white. Checked web links retain those colors and open the default browser only after HTTPS URL validation and free Cloudflare/Quad9 malware-domain DNS checks. No account/API key is required. Failed or blocked checks do not open a browser. This checks known malicious domains, not full URL paths, page contents or redirects. No system DNS changes are made.

The beacon row displays MM:SS until its next submission, waiting idle, paused or off. Changing its valid interval restarts the countdown.


## RX/TX audio VUs and clearing text (0.4.12)

The bundled engine measures RX input and TX output samples after gain: approximately 100 ms RMS/peak dBFS windows, pushed every 200 ms. Meters become unavailable on stopped/stale callbacks; clients blank stale telemetry after one second. No waveform, routing, CAT, PTT or gain behavior is changed. TX silence measures −100 dBFS; TX audio is not RF power or radio ALC.

Clear removes only the currently displayed conversation's messages while preserving rooms, heard history, deduplication and settings; Clear Draft empties only its editor. Clearing cancels pending link opening.
