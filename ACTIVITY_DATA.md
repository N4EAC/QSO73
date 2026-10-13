# QSO73 modem activity data coverage

Compared with the status display in [modem73](https://github.com/RFnexus/modem73/blob/3a37c290a5330bd95f4f283feafc5ba5605bdc52/tnc_ui.hh), the bundled 2.4.2 engine, and its control API. QSO73 0.3.0 displays these data groups:

| Upstream status data | QSO73 display / source |
|---|---|
| Callsign, modem/mode, RX/TX/idle, time | Sidebar and activity header; frame timestamps/ages |
| Carrier, level, threshold | Input RMS dBFS, level meter, configured threshold |
| Last SNR, SNR history, BER | Latest decoded frame SNR, 32 decoded-frame samples, selected-decoder BER and average |
| Heard mode, callsign, SNR, age | Heard row and received-frame history |
| CSMA status and busy/sync | Config state, decoder DCD, level-based busy where applicable |
| Occupancy and history | Total occupancy (30-second EMA) and sampled history; other-station occupancy separately |
| Quiet, window, slot | Actual gate quiet/window timing when populated; engine defaults before first gate; window also shown in slots |
| TX deferral, quiet, contention, turn/yield, queue | Runtime gate phase, wait/need timings, rank/population and queue airtime estimate |
| Activity plot | 90 sampled input levels colored idle/RX-busy/TX; about 2 seconds per sample |
| RX, TX, errors/syncs, clients, queue | Delivered RX, encoded TX, failure ratio, individual decoder error counters, KISS client count and queue |
| Recent RX and TX | Eight newest records combined by timestamp; size, mode, age, RX SNR/BER, complete frame metadata in a detail sheet |
| Rig frequency, mode, power, SWR | CAT frequency/mode/bandwidth, CAT power setting converted to watts, fresh TX-only RF output/SWR/ALC, S-meter, temperature, tuner state where supported |
| Audio / PTT | Health, capture/playback routes and rates, PTT status |
| Additional available control fields | Every scalar field in get_status and get_config, sorted in diagnostic detail sheets; event log |

## Data semantics and limits

No radio audio, CAT commands or RF are generated to populate an offline screen. Missing fields from older external engines display a dash. Disconnected or unsupported radio meters display Unavailable. CAT reads rotate one meter per status poll to avoid excessive serial traffic. This build needs a hardware meter check when the radio is reconnected.

RX counts actual delivered frames, not sync candidates. TX counts frames encoded for transmission, not successful RF delivery or acknowledgment. Selected-decoder counters and BER are not aggregate statistics across every concurrently enabled receiver. The failure ratio uses preamble+CRC failures divided by syncs; it does not double-count errors by adding this aggregate to its component counters. Full components remain visible.

Status history sampling can miss sub-second activity. The activity display is not an RF spectrum, waterfall, raw waveform or constellation. Those terminal SCOPE diagnostics use in-process DSP taps and are not exposed through the upstream status/control API; they are separate from the STATUS screen compared here. Utility actions and configuration editing are also separate from the activity display.

The headless engine extension exposes gate telemetry and an eight-record encoded-TX history over get_status. It does not change waveform generation, PTT behavior or CSMA decisions.

QSO73 0.4.6 separates the power-control setting from transmit meter readings. Actual radio PTT is queried through rigctld, independently of modem PTT; live RF output, SWR and ALC are prioritized during TX and invalidated in RX or after six seconds without a fresh sample. The power setting uses Hamlib power2mW conversion with current frequency/mode, with a percentage fallback when unavailable. On the development FT-710, read-only CAT returned PTT off, RFPOWER 0.15, output meter 5 W and SWR 1; power2mW returned 15000 mW. Idle meter floors are no longer displayed as actual transmitted measurements.
