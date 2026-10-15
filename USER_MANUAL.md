# QSO73 User Manual

## Amateur-radio chat with modem73

**macOS 0.4.15 / Windows 0.4.13 test 11 | modem73 2.4.2**

Edition: October 14, 2026

QSO73 combines a chat client with a local radio modem. Use it for plain packet chat, shared channels, addressed direct conversations, station beacons and channel invitations.

Chapters 1-13 describe the macOS client in version 0.4.15; the channel walkthrough applies to both clients. See page 16 for Windows test 11 setup and its interface differences. Instructions for an independently installed engine may differ where that engine supplies fewer diagnostics.

### Find what you need

| Page | Topic |
| --- | --- |
| 2 | First contact: a quick-start checklist |
| 3 | Radio, audio and CAT setup; FT-710 notes |
| 4 | Choosing a modem family |
| 5 | ROBUST modes and their names |
| 6 | OFDM and MFSK choices |
| 7 | Radio Chat and F-key macros |
| 8 | Creating, discovering and leaving channels |
| 9 | Topics, users and private conversations |
| 10 | Station beacons and channel announcements |
| 11 | Reading and docking Modem Activity |
| 12 | Engine updates, saved settings and chat export |
| 13 | Troubleshooting |
| 14 | Shortcuts, saved state and source reference |
| 15 | IRC-style channel and private-chat walkthrough |
| 16 | Windows portable testing build: setup and controls |
| 17 | PING requests, measured replies and user controls |
| 18 | PSK Reporter reception reporting |
| 19 | Heard queries: recent and specific callsigns |
| 20 | UTC colors, checked links and Windows beacon countdown |
| 21 | Clearing text and RX/TX audio meters |
| 22 | Setup tabs, audio amplification and themes |
| 23 | Creating contacts and exporting ADIF for LoTW |

**Start here:** for an HF chat trial, use ROBUST / RDM-600S with the radio's USB audio input and output selected. This is a suggested starting point, not a guaranteed link setting.

The current build has passed local protocol, socket and DSP tests. CAT frequency readback and transmit audio were checked with the FT-710 setup used during development. The new channel protocol has not been verified over the air between two radios.

<!-- page -->

# 1. First contact

### Before starting

You need a Mac running macOS 13 or later, a compatible QSO73 build for that Mac, a radio audio connection and an appropriate PTT method. CAT/PTT through rigctld also requires Hamlib's rigctld to be installed. The supplied build is for Apple Silicon.

For channels and direct conversations, both stations need QSO73 0.4 or later. For channel invitation discovery, use 0.4.1 or later. Both operators must use the same radio frequency and compatible radio sideband/audio setup. Their transmit modem modes need not be identical because the bundled engine listens for all three modem families.

### Quick-start checklist

1. Connect the radio's USB cable or audio interface and turn on the radio.
2. Open **Station Settings**. Enter your callsign, operator name, QTH and Maidenhead locator. An optional callsign SSID uses the form `N4EAC-1`.
3. Leave **Run local native modem on this Mac** enabled for the internal modem.
4. Click **Refresh Audio Devices**. Select the radio device for both **Input / radio receive** and **Output / radio transmit**.
5. Choose the PTT method. **rigctld (default)** is selected in a fresh setup; saved choices are preserved. Select your radio in the model dropdown, configure serial/baud and enable automatic startup.
6. Choose **ROBUST** and **RDM-600S** as an initial HF chat setting.
7. Click **Save**, return to **Radio Chat**, then click **Start Modem**. Allow microphone access if macOS asks; this permission covers radio audio capture too.
8. Check that audio is ready and that the activity display responds to received audio. If CAT is enabled, check that frequency and radio mode are read back.
9. In **Conversation**, keep **Radio Chat** selected. Select `QST` in **To** and send a short CQ, or use **F1 / CQ**.
10. Confirm that another station decodes your message. A submitted packet or TX counter alone does not prove reception.

### Finish or change settings

Click **Stop Modem** before changing audio devices, modem mode or radio connection settings. Save the changes, then start again. Stop Modem also pauses automatic beacon and channel-announcement timers.

**Keep the first test short.** Start with a simple message such as `CQ de N4EAC`. Confirm audio routing and decoding before enabling periodic transmissions.

<!-- page -->

# 2. Radio, audio and CAT

### Two separate connections

| Connection | What it does |
| --- | --- |
| Radio receive audio -> QSO73 input | Supplies audio for modem decoding |
| QSO73 output -> radio transmit audio | Supplies the transmitted modem waveform |
| CAT serial -> rigctld | Reads frequency/mode and controls PTT/frequency where supported |

CAT can key the transmitter while audio is routed incorrectly. A radio entering TX silently is therefore an audio-path problem until shown otherwise; CAT working does not prove TX audio is correct.

### Select explicit audio devices

Choose the radio USB audio device in **both** input and output selectors. Avoid **System default** for radio operation: the default output can be the Mac speakers. After a cable or device change, stop the modem, refresh the list, save the selection and restart. If the explicitly selected device disappears, the bundled engine refuses to fall back silently to another device.

Start with the saved TX output level, then adjust against the radio's meter and receiving station's reports. The setting ranges from 5% to 100%; it controls audio drive, not RF watts. Excess drive can distort the waveform. Aim for a clean signal with little ALC action, following the radio's data-mode guidance.

### FT-710 setup used with QSO73

| Setting | Development setup / instruction |
| --- | --- |
| Radio model | Hamlib model **1049** |
| CAT serial device | Select your radio's `/dev/cu...` device; the exact name varies |
| CAT baud | **115200** was used; QSO73 must match the radio's setting |
| PTT | **rigctld**; automatic startup enabled |
| Radio mode/audio source | PKTUSB, with PSK/DATA modulation source USB in the radio setup |
| QSO73 audio | USB Audio Device selected in both directions |
| Hardware sample rate | **44.1 kHz** observed on this FT-710/Mac setup |

The modem processes at 48 kHz and the bundled engine converts automatically to/from the hardware rate. Do not force the radio device to 48 kHz simply because the modem uses it internally. QSO73 does not automatically change the radio's USB modulation-source setting.

### Set Frequency

With CAT connected and the modem idle, enter MHz, for example **7.105**, and click **Set Frequency**. QSO73 asks the radio to change its dial and checks the readback. This control does not run an antenna tuner or transmit a tuning carrier.

<!-- page -->

# 3. Choose a modem family

The **Family** selector controls your transmitted waveform. It does not create a chat channel or change the radio's dial frequency. The bundled receiver listens for OFDM, ROBUST and MFSK concurrently.

| Family | Best starting use | Initial choice |
| --- | --- | --- |
| **ROBUST** | HF with fading or changing propagation | **RDM-600S** for short chat |
| **OFDM** | Stable HF paths; clear VHF/UHF FM links | **QPSK**, coding rate 1/2 |
| **MFSK** | Weak-signal fallback when other choices fail | **MFSK-16**; try MFSK-8 if needed |

These are starting recommendations. Noise, fading, interference, audio filtering and distortion all affect decoding; a single SNR number cannot guarantee success.

### A practical selection sequence

1. Start an HF chat with **RDM-600S**.
2. If decoding is consistently good, try **RDM-1200S** for shorter airtime per message.
3. If 600S is unreliable, try **RDM-300S**. For very weak paths, compare **MFSK-16** and **MFSK-8**.
4. For a stable, strong path, try **OFDM QPSK**. Increase modulation only after confirming successful reception.
5. For narrow-band operation, choose an **RDMN** mode or an appropriately narrow MFSK mode.

### Radio passband matters

Standard RDM and OFDM occupy approximately **2400 Hz**. RDMN occupies approximately **600 Hz**. MFSK choices range from roughly 250 to 1000 Hz. Keep the radio's receive/transmit audio passband wide enough to pass the whole waveform. A narrow CW filter can cut away carriers and prevent decoding.

Choosing a narrow waveform does not automatically narrow the radio's filter. Start with a passband that clearly contains the signal; narrow it only after confirming signal placement and decoding.

### Apply a change

**Stop Modem -> Station Settings -> Family/mode -> Save -> Start Modem.** The internal modem's mode settings take effect at the next start. QSO73 does not automatically step the transmit speed up or down.

Station beacons, channel invitations, direct messages and channel chat all use the selected transmit mode. There is no separate beacon-only modulation setting in this release.

<!-- page -->

# 4. ROBUST modes explained

ROBUST modes are intended for fading HF paths. Their names combine a speed class, bandwidth choice and optional short framing.

- **Number:** approximate speed class, not a guaranteed delivered text rate.
- **N:** narrow waveform, approximately 600 Hz instead of 2400 Hz.
- **S:** short frames. They reduce the duration of each frame and carry less data per frame.

| QSO73 mode | Bandwidth | Use / tradeoff |
| --- | --- | --- |
| **RDM-1200** | 2400 Hz | Faster choice for reliably decoding HF paths |
| **RDM-800** | 2400 Hz | Intermediate choice between 1200 and 600 |
| **RDM-600** | 2400 Hz | General fading-HF choice with longer frames |
| **RDM-300** | 2400 Hz | More redundancy and lower speed; try when 600 fails |
| **RDMN-300** | 600 Hz | Narrow-band 300-class operation |
| **RDMN-150** | 600 Hz | Slower narrow-band operation |
| **RDM-1200S** | 2400 Hz | Short-frame version of 1200 |
| **RDM-600S** | 2400 Hz | Suggested starting point for short HF chat/beacons |
| **RDM-300S** | 2400 Hz | Slower short-frame option for difficult paths |
| **RDMN-300S** | 600 Hz | Short-frame narrow-band 300-class operation |
| **RDMN-150S** | 600 Hz | Short-frame narrow-band 150-class operation |

### Short versus normal frames

The bundled engine has a 512-byte normal RDM data block and a 172-byte short block, before application/transport overhead. QSO73 enables modem fragmentation, so a message that exceeds one modem frame can be split and reassembled automatically.

Short frames suit short conversational messages and station beacons. They are not automatically better in every fading condition: shorter coding/interleaving blocks and additional framing overhead change the tradeoff. Compare successful reception, not just the time spent transmitting.

### Beacon starting point

For a callsign/grid/version beacon on HF, start with **RDM-600S** at a **10-minute** interval. If receiving stations cannot decode reliably, compare **RDM-300S**. Use **RDMN-150S** when a narrow waveform is required and its slower airtime is acceptable. The application's default station-beacon interval is 5 minutes; 10 minutes is an operating suggestion.

<!-- page -->

# 5. OFDM and MFSK

### OFDM: higher throughput on cleaner paths

All OFDM choices exposed by QSO73 use coding rate **1/2** and approximately **2400 Hz** bandwidth. Higher modulation packs more data into the waveform but needs a cleaner signal.

| Modulation | Practical choice |
| --- | --- |
| **BPSK** | Most conservative OFDM option in this menu |
| **QPSK** | Suggested first OFDM trial |
| **8PSK** | Step up after reliable QPSK reception |
| **QAM16** | Strong, stable links with clean audio; more demanding |

On fading HF, compare ROBUST rather than continually increasing OFDM drive or modulation. For a clear FM path, OFDM is a useful family to try. QSO73 does not expose every modulation or coding rate available in the upstream engine.

### MFSK: weak-signal alternative

MFSK sends multiple audio tones. The number in the name is the tone count, not the bit rate. Smaller choices occupy less bandwidth; decoding performance still depends on the complete signal path.

| Mode | Approx. bandwidth | Coding / use |
| --- | --- | --- |
| **MFSK-8** | 250 Hz | Rate 1/2; narrow weak-signal fallback |
| **MFSK-16** | 500 Hz | Rate 1/2; suggested first MFSK trial |
| **MFSK-32** | 1000 Hz | Rate 1/2; wider alternative |
| **MFSK-32R** | 1000 Hz | Rate 3/4; less redundancy and more payload |

**The R in MFSK-32R does not mean “more robust.”** It uses a higher coding rate, trading redundancy for payload. Do not select it solely because the signal is weak.

### Choose by decoded messages

A changing RX audio meter proves that audio is reaching the input. A waveform being audible proves neither correct filtering nor decoding. Compare actual decoded packets at the receiving station. Keep messages short and ask for a reply; QSO73 does not provide automatic delivery confirmation.

The bandwidth, framing and coding values in these tables follow the bundled engine definitions. They are not universal SNR thresholds, minimum power guarantees or promises of range.

<!-- page -->

# 6. Radio Chat and F keys

### Plain packet chat

1. Choose **Radio Chat** in the **Conversation** selector.
2. In **To**, select **QST / Broadcast** (the default) or a known callsign. Use **Add Callsign...** to enter a new callsign/SSID.
3. Type your message and click **Send Packet**, or press **Command-Return**.
4. Read “submitted” as handed to the modem connection, not received by another station.

QST broadcasts can be received by all compatible listening stations. The To list adds callsigns as messages are received or submitted. **Clear Callsigns** empties this session list and selects QST without deleting chat history. New traffic can add callsigns again. Returning from a direct conversation to Radio Chat selects QST automatically; selecting a callsign here sends a plain packet, not a structured direct message.

Plain Radio Chat allows up to **200 UTF-8 bytes** of text. Bytes are not always characters: accented text and emoji can use multiple bytes. The counter helps you stay within the limit.

### F1, F2, F3 and F4 transmit immediately

| Key / button | Action | Required destination |
| --- | --- | --- |
| **F1 / CQ** | Broadcast your CQ template | Automatically QST |
| **F2 / SNR** | Send a measured signal report | Other station's callsign in To |
| **F3 / 73** | Send the contact-closing template | Other station's callsign in To |
| **F4 / Custom** | Send your custom message template | Callsign in To, or QST for broadcast |

On some Mac keyboards, hold **Fn** with the function key. The **Radio** menu provides the same commands. The modem's listen-before-transmit rules can still defer RF transmission after a key is pressed. Macros preserve your typed draft.

**F-key macros remain plain Radio Chat packets.** They do not become channel messages when a channel is selected. For F2/F3, select Radio Chat and check To first; opening a direct conversation also changes the macro target to that station.

### F2 uses an actual measurement

F2 needs a recent decoded packet with a measured SNR identified as coming from the target station within the preceding ten minutes. It cannot report for QST or invent a missing measurement. Some independent engines may lack the sender-labelled metadata needed for this function.

### Customize templates

In **Station Settings -> Radio macros**, edit the templates and click Save. Enter **F4 / Custom message** to enable F4; leave it blank to disable. F4 uses To and preserves your draft. If its template includes `{snr}`, a recent measured SNR is required. Available tokens are `{call}`, `{name}`, `{qth}`, `{locator}`, `{to}` and `{snr}`. The expanded message must fit the 200-byte limit, and the signal-report template must include `{snr}`.

Example report template: `{to} de {call}. Your signal report is SNR {snr}.`

<!-- page -->

# 7. Create and use channels

QSO73 offers IRC-style channels, topics, heard-user lists and direct conversations over radio. No Internet connection or IRC server is needed. Both stations must use QSO73 for these features. A channel is a named conversation shared by stations on the same radio path. Channels organize messages; they do not allocate different RF frequencies or independent airtime.

### Create or join a channel

1. In Radio Chat, enter **#hfchat** in the **#channel or callsign** field.
2. Click **Open / Join**. If the name is new, it creates a local channel; if already known, it joins that conversation.
3. With the modem connected and audio ready, joining sends a membership announcement. While offline, joining is local only.
4. Type a short message and click **Send Packet**. The packet is routed to the selected channel.
5. Use **Conversation** to switch between channels, direct conversations and Radio Chat.

Names contain **1-20 letters, digits, hyphens or underscores** after the #. They are case insensitive, so `#HFChat` and `#hfchat` identify the same channel. Spaces are not allowed.

### Discover a channel

Received channel traffic can add a name to the Conversation list. QSO73 0.4.1 also discovers channels from optional channel invitations. Discovery does not automatically join you. Select the channel and click **Join** before reading or sending its messages. Traffic received before joining is not kept as a replayable backlog.

If you joined while offline, send a channel message or use Open / Join again after connection to make your presence known. Quiet local membership by itself cannot be detected by another radio station.

### Leave

Click **Leave**. When connected, QSO73 submits a departure announcement and removes your local subscription. It returns to Radio Chat and removes that channel's automatic-announcement settings. A known channel can remain in the list for later rejoining.

### Drafts, unread messages and size

Each conversation keeps its own draft during the application session. Numbers beside conversation names indicate unread received entries; selecting the conversation clears its count.

Channel packets include routing data inside the 200-byte limit, so the usable text length is smaller than plain Radio Chat's 200 bytes. If the composer says **shorten message**, reduce the text. Unicode can increase the byte count.

Joined channel names are saved between application runs. Message history, topics, user lists, direct conversations and drafts are session state; export your chat before quitting if you want a record.

<!-- page -->

# 8. Topics, users and private chat

### Set a channel topic

1. Join the channel and connect the modem.
2. Click **Topic...**.
3. Enter a short description, such as `40m evening chat - all welcome`.
4. Click **Transmit Topic**. An empty value clears the topic.

Any joined station can change a topic. QSO73 displays the latest topic change it received; there is no central owner or server enforcing a single global value. A station that missed the packet may see a different topic. Transmit it again when needed. Invitations carry the channel's topic and can supply an initially unknown topic to a listening station.

### Read the user list

Click **Users...** in a channel. The list contains stations heard there within the preceding **ten minutes**, plus your locally joined station. Channel messages, joins and other channel events provide this activity evidence. A received leave removes the sender from the heard-member list.

This is not a guaranteed online list. A silent station may be listening, and a recently heard station may already have gone away. Click a listed callsign to open a direct conversation.

### Open a private / direct conversation

1. Enter a callsign such as **K1ABC**, optionally with an SSID, in **#channel or callsign**.
2. Click **Open / Join**. QSO73 opens a separate **Direct: K1ABC** conversation.
3. Type and send. Incoming direct conversations addressed to your configured callsign appear automatically and can show unread counts.
4. Switch back to a channel or Radio Chat using Conversation.

Both stations need QSO73's conversation protocol. Plain packets addressed to your callsign remain in Radio Chat instead of being automatically converted into structured direct conversations.

**Private means addressed to one station, not confidential.** Direct traffic remains readable over the air. Callsigns are routing identifiers and are not cryptographically authenticated. There is no delivery acknowledgment or automatic retry.

### Session behavior

Channels, direct messages and plain Radio Chat share the modem and transmit queue. Changing frequency does not automatically clear the session's conversations or heard-user state. Recently observed information can therefore refer to the previous frequency until it ages out.

<!-- page -->

# 9. Beacons and channel invitations

These are two separate functions. Both use the same selected modem transmit mode as your chat and share the radio's airtime.

| Function | Payload / purpose | Default interval |
| --- | --- | --- |
| **Station Beacon** | Callsign, grid, QSO73 title/version | 5 minutes |
| **Channel announcement** | Channel name, topic, sender callsign | 10 minutes |

### Station Beacon

Enable **Beacon** in Radio Chat and select **Interval**, or configure it in Station Settings. The selectable range is **1-60 minutes**. A valid 4-, 6- or 8-character Maidenhead grid is required.

Example for this release: `BEACON N4EAC FM18FW QSO73 v0.4.15`

It broadcasts to QST without changing your selected conversation or draft. **Beacon Now** requests a beacon while enabled and connected; a busy modem defers the request. The first automatic beacon follows one full interval after connection or configuration.

Stopping the modem pauses the timer. The station-beacon enabled preference and interval are saved, so a later start can resume scheduling. The feature is off by default. For an HF trial, 600S every ten minutes is a suggested starting point.

### Announce an empty channel

1. Create/join your channel. Set a topic when connected, if desired.
2. Enable **Announce until another station is heard** below the topic.
3. Choose **Every** from 1-60 minutes. Ten minutes is the default.
4. The first automatic invitation follows one full interval after enabling or connecting.

A received **join or channel message from another callsign stops repetition**. Own echoes, private/direct messages, topics and other invitations do not stop it. If another participant was heard in that channel in the preceding ten minutes, enabling immediately stops announcements. A silent join cannot be detected.

Leaving removes the channel's announcement settings. Disconnecting pauses them; reconnecting waits a full interval. They do not automatically restart after another participant leaves, and they start off again when QSO73 is relaunched. Long topics are shortened to fit the invitation packet.

### Airtime behavior

Automatic packets wait for ready audio, idle modem status and an empty TX queue. Beacon and invitation submissions are spaced by at least five seconds, and missed intervals are not replayed in a burst. They can still briefly delay a chat message arriving afterward. The modem's carrier-sensing rules decide actual RF timing.

<!-- page -->

# 10. Read Modem Activity

**Decoding indicator:** Beside RX/TX (macOS) or frequency (Windows), green means a frame is being decoded; gray means inactive. A successful message is not guaranteed. Requires the current bundled engine.

Open **Modem Activity** from the sidebar for the full dashboard. To watch activity while chatting, use **Dock with Chat**, or **Undock** it into a separate window. The same modem session serves both views.

In the detached window, **Keep on Top** keeps the dashboard above other windows. **Dock** returns it below Radio Chat. In the docked panel, **Hide** closes the panel view without stopping the modem.

| Indicator | What it tells you |
| --- | --- |
| RX audio level / input meter | Audio energy is reaching the selected input; not proof of decoding |
| Carrier / threshold | Signal-level and carrier-detection information |
| Last SNR / history | Measurements from decoded frames; not a continuous reception guarantee |
| BER | Decoder bit-error estimate, where supplied |
| RX / TX counts | Delivered received frames / encoded transmit frames; not confirmed contacts |
| CSMA / DCD / occupancy | Listening, detected activity and channel-use information |
| Quiet / window / slot / queue | Why a queued transmission may be waiting |
| Recent RX / TX | Frame size, mode, age and available metadata |
| Radio frequency / mode / meters | CAT readback, power setting, and fresh TX-only RF/SWR/ALC meters |
| Audio routes / rates / PTT | Selected device path, sample-rate and keying state |

### A useful three-part check

1. **Input activity:** Does the RX audio meter change when the radio receives a signal? If not, inspect the input device and radio USB output.
2. **Decoded activity:** Does a received frame or chat message appear? If audio is present but frames are absent, check frequency, sideband, filtering and mode compatibility.
3. **Transmit path:** Does TX route identify the radio, and does the receiving operator decode the packet? A TX count alone is insufficient.

### Power setting versus TX meters

**Power setting** is the CAT power-control value converted to watts by Hamlib; it is not measured RF output. **RF output (TX)**, **SWR (TX)** and **ALC (TX)** show only fresh readings during confirmed radio transmission. In RX they show a dash. The FT-710 driver can report 5 W and SWR 1 while idle; those are calibration-floor values, not a live power or antenna measurement.

### Details and unavailable fields

Open the available detail views for full status, configuration, audio and frame metadata. Unsupported radio meters or missing independent-engine fields can show a dash or Unavailable. This is different from a valid zero reading.

The activity plot is a sampled input/activity history. It is not a live RF spectrum, waterfall or constellation display. Short events can occur between samples. CAT meters are polled in rotation rather than all at once, and not every radio supports every meter.


<!-- page -->

# 11. Updates, settings and records

### Updating the modem engine

The modem engine can be replaced separately from the QSO73 application. Do this with the modem stopped.

1. Open **Station Settings -> modem73 engine**.
2. Click **Check Updates**. When versions can be compared, QSO73 reports **Up to date** or **Update available**. If the selected engine does not report a usable version, it states that comparison is unavailable.
3. Use **Upstream Releases** to obtain the appropriate macOS package and unpack it.
4. Click **Install Local Engine...** and select the native modem73 executable from that package.
5. Wait for validation, then start the modem and check its audio routes and diagnostics.

**Install Local Engine** is a manual package selector, so it remains available when no newer release exists. Check Updates does not automatically download or install anything. Installing an engine does not replace QSO73.app.

Use **Use Bundled Engine** to return to the packaged engine. **Use Previous Engine** selects the preceding engine within the current application session. Independent engines may provide fewer diagnostic fields or different audio behavior; recheck the device path after changing engines.

### Save, import and export settings

**Save** stores station, modem, radio, macro and station-beacon settings. **Export Settings...** writes a QSO73 JSON profile; **Import Settings...** reads a compatible profile while the modem is stopped.

The selected installed-engine package is local to the Mac and is not included in the profile. Channel subscriptions are separate local preferences. The To callsign list, direct conversations, message history, drafts, topics, unread counts and channel-announcement settings are not restored from a settings profile.

### Export Chat

Before quitting, use **Export Chat...** to write the session's collected chat entries to a text file. Export includes collected conversations, not just the currently selected one. Submitted outgoing packets can be present even if reception was not confirmed. Automatic station beacons also appear as plain Radio Chat entries.

### Select the correct radio model

The **Radio model** dropdown lists the model number, brand and model from the installed Hamlib. Use **Find radio by brand, model or number** to filter it, and **Refresh Radio Models** after updating Hamlib. Select the exact supported model, not an arbitrary number. Saved selections are retained if lookup is unavailable.

### External modem option

Disable **Run local native modem on this Mac** to connect to a modem73 already running elsewhere. Configure its host, KISS port and control port. These ports are hidden and managed automatically for the internal modem. External settings do not change the remote engine's audio devices or waveform configuration.

A remote radio needs its modem and audio path at that station, or an explicit audio path to this Mac. Remote CAT alone does not transport radio audio. The external modem manages its own rigctld connection.

<!-- page -->

# 12. Troubleshooting

Use **Modem events** in Radio Chat when diagnosing startup, device routing or connection errors.

| Symptom | First checks |
| --- | --- |
| Radio keys, but modem audio comes from Mac speakers | Stop Modem; select radio output explicitly; save/restart; inspect TX route |
| Radio keys silently | Check radio USB modulation source and QSO73 output device/level |
| RX meter never moves | Check input device, USB cable, radio audio output and microphone permission |
| RX meter moves but no messages decode | Check frequency, sideband, passband and other station's modem/application |
| Send Packet disabled | Start modem, check audio readiness, join channel, and shorten oversized text |
| F2 has no report | Receive a measured packet from the exact target callsign within ten minutes |
| Frequency does not change | Check CAT connection, serial device, model and matching baud; wait for idle |
| Beacon or invitation stays deferred | Audio unavailable, busy channel, queued traffic or automatic submission spacing |
| Channel announcements stop immediately | Another participant was heard there within ten minutes |
| User list seems incomplete | It lists recently heard users; silent listening cannot be detected |
| Local modem port is already in use | Stop the other modem application using that port, then retry |
| Radio meter shows Unavailable | That meter may be unsupported or CAT disconnected; inspect details |

<!-- page -->

# 13. Quick reference

### Keep versus session-only

| Kept locally between runs | Session-only / export if needed |
| --- | --- |
| Saved station, modem, radio and macro settings | Chat entries and per-conversation drafts |
| Station-beacon enable preference and interval | Topics, heard users and unread counts |
| Joined channel names | Direct-conversation list |
| Installed-engine selection | Channel-announcement options and To callsign list |

### Useful shortcuts and meanings

**Command-Return:** Send Packet. **F1/F2/F3/F4:** CQ / measured SNR report / 73 / custom message, immediately submitted as plain packets. **QST:** broadcast destination. **CAT:** radio control/readback. **PTT:** transmitter keying. **CSMA:** listen and contend before transmitting. **SSID:** optional callsign suffix 0-15.

**Default reminders:** station beacon 5 minutes; channel announcement 10 minutes; both optional. First automatic transmissions wait one full interval. “Submitted” and TX counters do not mean delivered. Channels share RF airtime, and private conversations are not confidential.

### Basis of this manual

Application behavior was checked against QSO73 0.4.15 macOS source and its local tests. Mode bandwidth/framing/coding tables were checked against the bundled modem73 2.4.2 definitions. Starting-mode recommendations are operating suggestions, not measured range or SNR guarantees.

Engine source: https://github.com/RFnexus/modem73/tree/3a37c290a5330bd95f4f283feafc5ba5605bdc52

Upstream operating guidance: https://github.com/RFnexus/modem73/blob/master/QUICKSTART.md


<!-- page -->

# 14. Channel chat walkthrough

### Start a shared room

1. Agree on an RF frequency and compatible modem settings with the other stations. Connect your radio audio and CAT/PTT, then start the modem.
2. Enter **#hfchat** in **#channel or callsign**, then click **Open / Join**. You are now locally joined to that channel.
3. Click **Topic...**, enter `40m chat - all welcome`, then click **Transmit Topic**. Other stations learn the topic when they receive its packet.
4. If waiting for company, enable **Announce until another station is heard** and choose **Every**, for example ten minutes. Keep the radio and modem connected while waiting.
5. A listening station selects the discovered channel in **Conversation** and clicks **Join**, or types **#hfchat** and clicks **Open / Join**. Discovery alone does not subscribe it to messages.
6. With the channel selected, type a message and click **Send Packet**. Other joined stations that decode the packet see it in their #hfchat conversation. A received join or message from another station stops your repeated invitation.

### Move from the channel to a private chat

1. Click **Users...** and select a callsign to open its direct conversation. Alternatively, enter **K1ABC** in **#channel or callsign** and click **Open / Join**.
2. Confirm **Direct: K1ABC** is selected, then type and send. The recipient gets a separate direct conversation when the packet is decoded.
3. Choose **#hfchat** in **Conversation** to return to the room. Choose **Radio Chat** to return to plain chat; its **To** selection returns to **QST** for broadcasts.

Opening a direct conversation does not leave your channels. Unread counts help you notice received messages in other conversations. Drafts stay with their respective conversations during the session.

### What to expect

**Topics and Users:** any joined station can transmit a topic. Users shows stations heard in that room within ten minutes, plus your own joined callsign; it is not confirmation that every listed station is still listening.

**Plain addressed chat:** selecting a callsign in Radio Chat's **To** menu sends a plain addressed packet. Use a **Direct:** conversation when you want a separate private-chat transcript.

**Finish:** select a channel and click **Leave** to stop participating. Export Chat before quitting if you need a record. Joined channel names are saved, but topics, heard users, direct conversations and messages are session-only.

All rooms share one radio frequency and transmit queue. Private chat is addressed traffic, readable over the air. Messages have no delivery acknowledgment, and traffic missed before joining is not replayed.


<!-- page -->

# 15. Windows portable testing build

The Windows companion is **0.4.13 test 11**, for Windows 10 (1903+) or Windows 11 on x64. It uses the same QSO73 channel/direct protocol as the Mac. A tester has reported a working radio connection and over-the-air message transmission with test 2. Test 11 adds Setup/Contact Log tabs, audio gain and themes, and fixes Stop Modem closing the client. Windows hardware verification remains pending.

### Extract and configure

1. Extract the whole portable ZIP to a writable folder and run **QSO73.exe**. Keep **QSO73-Activity.exe**, **engine/** and **hamlib/** together. No installer, MSYS2, Python, WSL or separate Hamlib installation is needed by the operator.
2. Open the **Setup** tab. Enter your **Station callsign** and **Grid**. Click **Refresh audio devices**, then choose the radio USB device for both RX input and TX output. System-default audio devices are excluded.
3. Choose **robust / RDM-600S** for an initial HF trial. With **rigctl** PTT selected, choose your exact **Radio model**, **CAT COM port** and **baud** matching the radio's settings. Use Refresh models / COM ports after reconnecting. Other applications must release the CAT serial port.
4. Click **Save settings**, then **Start Modem**. QSO73 starts bundled Hamlib 4.7.2, checks a radio frequency read, and starts modem73. Wait for Connected, Audio ready and CAT connected. Failed startup details appear in Modem Activity / rigctld.log.
5. Use USB data mode and the radio's USB data modulation source. Start with low radio power and adjust TX audio using the radio's own ALC indication. Agree on frequency and operating settings with your test partner.

Open **Chat** for messages, meters and frequency controls. **Contact Log** contains the contact creator and ADIF export. Start/Stop stays available above the tabs.

**Stop Modem** keeps QSO73 open, releases PTT and closes the modem and Hamlib processes QSO73 started. CAT ports are internal. An occupied port reports an error instead of taking over another radio service. VOX is an alternative PTT choice when configured on the radio; it does not provide CAT frequency readback.

### Read activity and frequency

**Modem Activity** opens a compact two-column text dashboard with signal level, SNR/BER, CSMA timing, occupancy, activity history, RX/TX statistics, recent frames and CAT frequency. Full configuration, events and engine / CAT logs are available below it. Use PgUp/PgDn, arrows and Home/End to navigate; Space pauses the display and Q or Esc closes it. Pausing or closing the display keeps the modem and chat operating. Reopen it from the same button.

Actual CAT frequency appears beside **Set Frequency**, refreshed about every two seconds outside modem TX. Older data is labelled **(last read)**; failed reads show unavailable. The MHz input field changes the dial only when Set Frequency is clicked. This does not transmit a tuning carrier.

### Beacon Now and conversations

**Beacon Now** requests a one-shot QST beacon with the saved callsign, valid grid and QSO73 version, even when repeating Beacon is off. It waits for ready audio/PTT, an idle modem and an empty queue. Repeated clicks while pending do not queue duplicates. Repeating Beacon and channel invitations remain optional, with 1-60 minute intervals.

Use Conversation and Open / Join for channels or direct callsigns, Topic... to set a topic, and Users... for recently heard members. In Windows, type a listed callsign into Open / Join to start a direct chat. F1-F4 submit plain Radio Chat packets even while a channel is selected. Export Chat before quitting to keep the session.

The Windows client omits Mac profile import, engine updates, docking and graphical CAT meters. Settings and joined names persist in settings.json; chat and drafts are session-only. Preserve settings.json when updating.

<!-- page -->

# 16. PING and automatic signal reports

PING checks whether an updated QSO73 station can decode your request and send a reply. The reply contains the responding station's **callsign**, **saved grid** and the **measured SNR of your received request**. This SNR describes reception at that station, rather than the strength of its reply at your radio.

### Send a PING

1. Use **QSO73 0.4.8 or later on macOS** or **Windows 0.4.8 test 4 or later** at both ends, with their current bundled engines. Older clients do not implement this PING protocol. Independently installed engines need the decoded-frame application_id metadata used to associate each request with its own SNR.
2. Configure your callsign, grid, radio audio and PTT; start the modem and confirm audio is ready. The receiving station also needs a valid saved Maidenhead grid to reply.
3. In Radio Chat, choose the other callsign in **To** and click **PING**. QST requests replies from listening QSO73 stations. If a direct conversation is selected, PING targets that station; from a channel, it uses QST. PING is shown in Radio Chat rather than as a channel message.
4. Look for a **PING reply** in Radio Chat. It shows the responding callsign/grid and request SNR in dB. A local request entry confirms submission, not radio reception or delivery.

### Enable or disable automatic replies

**Auto PING replies** is a checkbox in the chat controls on both platforms. It is **off by default**, and the selection is saved. Enable it at stations that should answer requests automatically. Clearing it cancels waiting replies and prevents future automatic replies; packets already submitted to the modem cannot be withdrawn.

A station can send requests while its own automatic replies are disabled. With QST, several enabled stations may answer, sharing the same radio channel and carrier sensing. Use an individual callsign for a focused link check.

### Reply timing and measured data

Replies wait for ready audio, idle modem status and an empty transmit queue. They share the automatic-traffic spacing used by beacons and channel invitations. A request waits at least two seconds so its decoded-frame metadata can arrive. Waiting replies expire after thirty seconds. Disconnecting the modem cancels them.

The client matches the source callsign and unique request ID to that request's decoded-frame SNR. It does not substitute an older signal report or invent zero when a measurement is missing. Without matching metadata or a valid grid, no automatic reply is sent.

Duplicate requests are ignored. Each source can receive at most one automatic reply per thirty seconds, and replies never trigger another reply. Requests are not repeated automatically. If retrying, allow the reply interval to expire first.

### If no reply arrives

Check that the other operator uses the updated client and bundled engine, has enabled Auto PING replies and saved a valid grid. Confirm matching frequency, usable radio audio and working PTT. A busy channel, missed request, missing measurement or lost reply can prevent an answer. PING does not provide delivery guarantees or a connected session.

PING uses ordinary AX.25 UI packets with QSO73 application data. Callsigns and grids are readable over the air. Keep the reply option off when you do not want automatic transmissions.


<!-- page -->

# 17. PSK Reporter reception reporting

PSK Reporter is an Internet service that maps received amateur-radio signals. QSO73 can upload successful packet receptions without transmitting anything over the radio. Reporting is optional, off by default, and its setting is saved.

### Enable reporting

1. Enter your own valid callsign and Maidenhead grid in Station Settings. Use your receiving location; four, six or eight characters are accepted.
2. Configure CAT and start the modem. Reporting needs recent radio frequency and mode readback, plus working receive audio. The bundled modem uses a 1500 Hz audio center.
3. On macOS, enable **PSK Reporter reception reporting** in Station Settings. On Windows, enable **PSK Reporter** beside Grid. You can disable it while the modem is running.
4. Receive another station's successfully decoded packet. QSO73 queues the reception and submits a batch after approximately five minutes. The reporting status shows queued, submitted or Internet error; it is outside the chat transcript.
5. Open **https://pskreporter.info/pskmap** in your browser. Choose your callsign as receiver to see stations you heard, or as transmitter to see reports submitted by other receiving stations. Select **All modes** or **PKT**. Allow time for processing.

### What is reported

Each report contains the decoded sender callsign, reception time, measured frame SNR and RF center frequency. Your callsign and grid identify the receiving station, and the software field identifies QSO73 and modem73 versions. AX.25 SSIDs are removed for the callsign lookup. Chat contents, topics, private-conversation text and files are not uploaded. The sender's grid is not invented; it is omitted from this reporting profile.

Reports use **PKT**, the standard packet mode label. QSO73 is identified in the software field; modem73's ROBUST, OFDM and MFSK choices are not reported as unrelated named digital modes. Reported SNR is the modem's estimate and can differ from estimates made by other decoders.

### Frequency, duplicates and limits

CAT frequency/mode must be no more than 30 seconds old. For USB and PKTUSB, QSO73 adds 1500 Hz to the dial; for LSB and PKTLSB, it subtracts 1500 Hz. FM uses the dial frequency. Unsupported or unavailable CAT modes are skipped. macOS external engines must confirm a 1500 Hz center in configuration. Old frame history and your own callsign are excluded.

A sender/frequency pair is queued at most once per five minutes. Batches are bounded to 56 receptions, expire after 15 minutes if unsent, and use packets below 1400 bytes. Uploads run separately from CAT and radio audio, use a randomized initial delay and do not add radio airtime.

UDP delivery has no acknowledgment. **Submitted** means the operating system accepted the datagram; it does not confirm that a spot appears on the map. Disabling cancels pending uploads; a datagram already submitted cannot be recalled. Check Internet access, receiver grid and fresh CAT data if reports are absent.

Protocol reference: https://www.pskreporter.info/pskdev.html


<!-- page -->

# 18. Heard queries

Use **Heard...** beside PING to ask stations for their reception history. Both ends need **QSO73 0.4.13 or later**. The modem engine itself does not need a new radio command or waveform. Queries and replies use ordinary radio packets and share airtime with chat.

### Ask everyone, or one station

1. Choose **Radio Chat** and set **To** to **QST** to ask all listening QSO73 stations. Select a callsign to ask only that station. In a channel, the button uses QST; in a direct conversation it uses that conversation's callsign.
2. Click **Heard...**. On macOS, choose **Recent callsigns** or **A specific callsign**. On Windows, leave the prompt blank for recent callsigns, or enter the callsign to look for.
3. Click **Send query**. Recent queries ask for up to three other callsigns heard in the last hour of each responder's current modem session. The responder excludes itself and the requester from that recent list.
4. Read the orange responses in **Radio Chat**. The header identifies the responding station. Each returned call includes its reception age and measured SNR when available. A specific query can return **not heard**; a recent query can return **no other recent callsigns**.
5. Allow one minute between queries. A QST query may receive replies from several stations. Replies are addressed back to the requester, rather than broadcast to QST.

Example: set To to QST, click Heard, and enter **K1ABC**. Stations with automatic replies enabled answer whether their local histories include that station. A query for K1ABC matches its SSIDs; a query for **K1ABC-7** or **K1ABC-0** checks that exact SSID. The most recent matching reception is returned.

### Allow your station to answer

Enable **Auto Heard replies** beside the button. This is a separate saved option from Auto PING replies, and is off by default. A grid is not required for Heard replies. Disabling it cancels pending replies; already submitted packets cannot be withdrawn.

QST responses wait a randomized 4-24 seconds and then an idle modem with an empty queue. Automatic actions share a minimum five-second spacing. A station answers the same requester at most once per minute; pending requests expire after two minutes if they cannot be submitted. Duplicate queries and responses are suppressed, and replies never generate further replies.

### What heard history means

The history contains successfully decoded AX.25 station callsigns from this modem session. Where engine frame metadata is available, it supplies SNR and reception time. Otherwise a decoded packet can establish the callsign with SNR marked unavailable. Failed decodes and unverified carrier IDs are excluded. History is bounded to 256 callsign/SSID entries and cleared when the modem disconnects.

The window is at most one hour, and can include earlier frequencies used during the same session. Reception ages describe the history at reply creation; radio queue and airtime add delay. **Not heard** does not prove that a station is offline. A station's current query can itself be a reception for a specific-callsign answer. Packets have no delivery acknowledgment or automatic retry.


<!-- page -->

# 19. Message display and checked links

### UTC time and message colors

Every message header uses a 24-hour **HH:mm:ss UTC** timestamp, replacing the old You prefix. Headers retain the station identity. The timestamp is local reception or KISS submission time; it does not prove delivery or identify the exact RF transmission instant.

| Color | Meaning |
| --- | --- |
| Blue | Your operator messages, including manually sent macros |
| Orange | Generated traffic: PING/Heard queries and automatic replies, beacons and channel notices |
| Green | Received operator messages |

Automatic traffic remains orange even when sent by your own station. macOS uses opaque colors selected for its light and dark message backgrounds; Windows uses a white rich-text transcript with dark, contrasting colors. Links are underlined and keep their message color. New Windows messages continue to scroll to the bottom automatically.

### Open a checked web link

Click a web URL in a message. QSO73 checks its hostname using the free malware-blocking DNS services from **Cloudflare** and **Quad9** over HTTPS before opening the default browser. No account or API key is required, and your system DNS settings are not changed. Only the clicked hostname is submitted to these services; chat text and URL paths/query strings are not sent to them.

Only **HTTPS** links are opened. Credentials embedded in a URL, unusual ports, local hostnames, IP literals, internationalized/ambiguous hosts and control characters are rejected. Private, reserved or blocking addresses returned by a security resolver are rejected. Both providers must resolve the hostname without blocking it. Failed, timed-out, malformed or unavailable checks leave the browser closed and show a warning.

These are **known-malicious-domain checks**, not page-content or full-URL scans. They do not guarantee that a new malicious URL, a bad path on an otherwise legitimate site, a redirect or a later DNS change is safe. Your browser's own protection remains relevant. The Mac displays a cancelable checking panel; Windows shows Checking link while its separate network worker runs. A newer click replaces an older pending check.

### Windows beacon countdown

The beacon row shows **Beacon MM:SS** until the next periodic submission, **Beacon waiting idle** when a due/one-shot beacon is waiting for the channel, **Beacon paused** when radio/audio readiness is unavailable, or **Beacon off**. Changing a valid interval while beaconing restarts its countdown. Stopping the modem pauses beaconing; the next start schedules a full interval.

Security-service references:

https://developers.cloudflare.com/1.1.1.1/setup/

https://docs.quad9.net/services/


<!-- page -->

# 20. Clearing text and audio VUs

## Clear conversation messages

Click **Clear** to remove messages from the conversation currently displayed: Radio Chat, a channel, or a direct conversation. On macOS it is beside Export Chat; on Windows it is beside the channel controls. Clearing is available while offline as well as online. It takes effect immediately. Export the chat first if you want to keep a copy.

Clear does not leave a channel, clear callsigns or reception history, alter modem settings, cancel transmissions, or erase other conversations. Fresh messages appear normally. Duplicate suppression remains active, so clearing does not make previously received packets appear again. A pending web-link check is canceled when the conversation is cleared.

Use **Clear Draft** beside Send Packet to empty unsent text in the current editor. It does not transmit or remove received messages. Other conversations' drafts remain available.

## Incoming and outgoing audio

Both clients show compact **RX audio** and **TX audio** meters while chatting. On macOS they are above the sidebar's online/offline indicator. On Windows they are above the message transcript. The bundled engine sends updates about five times per second, independently of CAT polling.

| Meter | What it measures |
| --- | --- |
| RX audio | Digital samples from the selected radio input after software RX gain |
| TX audio | Digital samples delivered to the selected audio output, after modem TX audio gain, including silence when idle |
| Number | RMS level over approximately 100 milliseconds, in dBFS |
| Thin marker | Peak sample level in that same measurement window |
| Bar | Scale from −60 dBFS at the left to 0 dBFS at the right |
| Colors | Green below −12 dBFS; yellow from −12 to −3 dBFS; red near full scale |
| — or -- | Audio telemetry is unavailable or more than one second old |

Zero dBFS is digital full scale. Normal idle TX silence reads −100 dBFS and leaves the bar empty. Red indicates little digital headroom; it does not by itself identify clipping inside the radio. The TX meter is not an RF-power, SWR or ALC reading and does not prove that the selected audio device is the radio. Check the device selection and the radio's own meters during an agreed test.

A changing RX meter confirms incoming audio activity, not a successfully decoded message. Use Decoding and the received transcript to check modem reception. An older independently installed engine may not provide these audio measurements; the clients show unavailable rather than estimating TX levels from gain or PTT state.


<!-- page -->

# 21. Setup, amplification and themes

## Windows Setup tab

Windows has three separate pages: **Chat**, **Setup** and **Contact Log**. Setup contains callsign/grid, radio input/output devices, modem mode, PTT method, bundled Hamlib model/COM/baud, macros, gain and theme choices. Configure and Save settings before Start Modem. Device and CAT changes require stopping the modem; the gain and theme controls remain available while it is running.

Start/Stop is always at the top. Stop Modem shuts down QSO73's modem and Hamlib processes and releases PTT; QSO73 remains open. You can change settings and start it again in the same window. The radio-frequency controls occupy their own labeled group, separately from To / QST, in both clients.

## Input and output gain

In macOS Station Settings, use **RX gain**, **TX gain** and **Apply Gain**. In Windows Setup, enter the gain values in dB and click Apply Gain. Values are saved for the next startup and applied to a connected updated engine when idle. The engine rejects a gain update while receiving/transmitting; wait and apply again. Independently installed older engines may lack this feature: select the updated bundled engine to use gain controls.

| Gain | Amplitude multiplier |
| --- | --- |
| −20 dB | 0.1x (attenuation) |
| −6 dB | About 0.5x |
| 0 dB | 1x (unity; initial default) |
| +6 dB | About 2x |
| +20 dB | 10x (maximum amplification) |

RX gain acts before decoding and is reflected in the RX audio VU. TX gain multiplies the existing TX output percentage before playback and is reflected in the TX VU. Gain is software audio gain; it does not change the radio's RF-power setting or physical microphone/USB levels. Device-rate conversion, including a 44.1 kHz radio USB device, continues as before.

Start at 0 dB. Increase gain only as needed and watch peak markers. Full-scale audio is limited to −1…+1; excess gain causes clipping and can impair decoding. RX gain also amplifies noise and does not improve signal-to-noise ratio. Check the radio's own ALC and use modest RF power during an agreed test.

## Default and CP themes

Choose **Default** or **CP** in Station Settings on macOS, or Setup on Windows. CP means Cyberpunk: a dark purple/navy interface with cyan and magenta accents. Default restores the normal platform presentation. Themes apply immediately and are saved between launches. They do not restart the modem or change radio settings. Message categories keep their blue/orange/green identities with colors suited to the background.

<!-- page -->

# 22. Contacts, ADIF and LoTW

Open **Contact Log** in the macOS sidebar or Windows tab bar. Use **New Contact** to create a record of an actual completed contact. On macOS, the editor fits its fields and Save button without scrolling; saved contacts use the remaining space. A beacon, PING, Heard reply or decoded packet alone is not automatically logged as a QSO.

1. Review the contacted callsign and your station callsign. Radio-chat destinations can prefill a callsign; QST and channels do not. AX.25 SSIDs are removed from callsigns for logging. Portable callsigns with slash components are supported.
2. Enter the actual radio frequency in MHz. A recent CAT read can prefill it, but verify it represents the contact. The amateur band is derived from the frequency; invalid/unrecognized frequencies prevent saving.
3. Set the contact's UTC start and end. macOS date/time pickers use UTC; Windows uses YYYYMMDD and HHMMSS fields. End must not precede start, and a contact crossing midnight exports both dates correctly.
4. Optionally enter the other station's grid, your grid, reports sent/received and notes. Reports are operator-entered rather than invented from SNR. Use printable ASCII for reports/notes; grids are validated. Confirm station identity/location against your TQSL configuration.
5. Click **Save Contact**. On macOS, select a saved row to review/edit it; on Windows, select a row and click **Edit Selected**. Saving edits replaces that record. Save before leaving the creator; unsaved edits are not logged.
6. Click **Export ADIF…** and save a .adi file containing all saved contacts. Export creates a file locally; it neither transmits on the radio nor submits credentials/contact data to an online service.

## What the export contains

Records use ADIF 3.1.6 and standard fields: CALL, STATION_CALLSIGN, OPERATOR, QSO_DATE, TIME_ON, QSO_DATE_OFF, TIME_OFF, FREQ (MHz), BAND and MODE. Optional fields are GRIDSQUARE, MY_GRIDSQUARE, RST_SENT, RST_RCVD and COMMENT. Mode is **PKT**, the standard packet-radio category, rather than an unsupported modem73 waveform name. Length-delimited field values and EOR markers produce a conventional ADIF .adi file.

## Sign and submit using TQSL

Open the exported .adi file in ARRL's TQSL and use **Sign a log and upload it automatically to LoTW**. TQSL requires your callsign certificate and correct station location. Review its validation messages and correct the contact record if needed, then export again. LoTW receives signed submissions; an unsigned ADIF export is not a direct LoTW upload and is not proof of acceptance.

Contacts persist separately from chat: macOS saves them in its QSO73 preferences; Windows saves contacts.json beside QSO73.exe. Keep that file/settings.json when replacing a portable Windows folder. Personal contact data is excluded from distributed ZIPs. An unreadable saved log is preserved and editing is blocked, rather than silently overwriting it.

Sources: https://www.adif.org/316/ADIF_316.htm and https://lotw.arrl.org/lotw-help/submitting-qsos/
