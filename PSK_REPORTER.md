# PSK Reporter integration

Both clients provide saved opt-in Internet reporting, off by default. Only successfully decoded frame metadata with `callsign_source=ax25`, a valid other-station callsign, actual finite SNR/time, working audio/CAT and current session/fresh timestamps is eligible. CAT frequency and mode must be at most 30 seconds old. The report frequency is USB dial + 1500 Hz, LSB dial - 1500 Hz, or FM dial; unknown modes are excluded. macOS external engines must advertise the 1500 Hz center.

The receiver uses the local callsign/grid; AX.25 SSIDs are removed from PSK callsigns. Mode is ADIF PKT. No message text or guessed sender locator is submitted.

IPFIX v10 uses enterprise 30351, receiver options template 0x9992 (callsign, grid, software) and sender template 0x9995 (callsign, five-byte RF Hz, signed one-byte SNR, PKT, automatic source=1, UTC seconds). All sets have four-byte padding; templates accompany every datagram. The observation ID is session-stable and sequence advances by submitted reception count. Persistent UDP source port sends to `report.pskreporter.info:4739`.

Batch timer: initial 300–330 seconds, subsequent/retry 315 seconds. Sender/frequency dedup: five minutes. Queue limit: 56 receptions; unsent data expires after 15 minutes; datagrams are under 1400 bytes. Networking is independent of radio/CAT work. Disable invalidates pending completions and cancels unsent data. UDP writes have no remote acknowledgment.

Validation: the native macOS service submits a complete datagram to a loopback UDP listener, then disables cleanly. Tests exercise Swift/C++ encoders and queues without live uploads; `Tests/check_psk_ipfix.py` independently decodes both fixtures and verifies they match. A test-flagged fixture was sent only to the official analyzer port 14739; its result page returned HTTP 403, leaving server acceptance unverified.

References: https://www.pskreporter.info/pskdev.html and https://www.adif.org/316/ADIF_316.htm
