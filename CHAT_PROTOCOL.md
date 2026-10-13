# QSO73 conversations · protocol v1

QSO73 0.4 adds its own channels and direct conversations. It does not implement
HamIRC or an IRC server. Plain Radio Chat, beacons and F-key macros retain their
existing AX.25 packet format and behavior.

## Using conversations

Enter `#hfchat` and click Open / Join to create or join a channel. Names contain
1–20 ASCII letters, digits, hyphens or underscores and are case insensitive.
Enter a callsign (optional SSID) to open a direct conversation. Use Conversation
to switch between Radio Chat, discovered channels and direct conversations.
Drafts are kept separately during the app session. Incoming direct conversations
appear automatically, with unread counts. Discovered channels must be joined
before reading or sending channel messages. Joining while offline is local;
when connected, Open / Join sends a membership announcement. Sending a channel
message also makes the sender visible to receivers. Leave announces departure
when connected and removes the local subscription.

Topic… broadcasts a topic, or clears it with an empty value. Any joined station
can set a topic; the latest received change wins locally. There is no server,
owner, access control or globally synchronized topic history. A station that
missed the change will not automatically receive the old topic; a member can
transmit it again.

Users… lists stations heard in that channel within ten minutes, plus the local
joined station. Click a callsign to open a direct conversation. These are heard
stations, not guaranteed live membership. No periodic presence traffic is sent unless optional channel announcements are enabled.

All channels use the same dial frequency, bandwidth and modem. Direct messages
are addressed conversations, not confidential messages. RF traffic is readable,
sender identities are not authenticated, and submission does not confirm delivery.
Channels and direct messages require QSO73 0.4+ at both stations. The F keys remain
Radio Chat macros; they do not automatically become channel messages.

## Wire format

KISS data carries an AX.25 UI packet, control 0x03 and PID 0xF0. Its UTF-8 body
starts with `~Q73:` followed by a JSON object:

```
{"v":1,"k":"msg","r":"#hfchat","t":"Hello","id":"<UUID>"}
```

Fields: v protocol version, k event (msg/join/leave/topic/announce), r channel or direct
recipient callsign, t message/topic text, id fresh UUID. Sender identity is taken
from the AX.25 source address. Channel events must use AX.25 destination QST.
Direct messages must have identical AX.25 destination and r recipient. Membership
and topic events require a channel. Join/leave have empty t; empty topic clears it.
Newlines and NUL are rejected. The complete body, including routing, must fit the
existing 200 UTF-8 byte limit. UI validates the actual encoded size; long messages
must be shortened. modem73 fragmentation handles small modem frame capacities.

Duplicate source/UUID pairs are ignored using a bounded 4,000-entry session cache.
Malformed envelopes are logged and ignored without disconnecting the modem.
Plain messages continue through the existing Radio Chat path unchanged.

Joined channel preferences persist. Messages, direct tabs, topics, user lists,
drafts and unread counters are session state. Radio frequency or modem changes
do not create independent networks; observed data can span the session.

## Validation

ChatRoomsTests exercises two simulated stations through KISS and AX.25 encoding:
channel subscriptions/discovery, direct recipients, topic changes, duplicates,
unread counters, expiring membership, leaves, invalid envelopes and legacy traffic.
The socket fixture also verifies native channel/direct sends and receives, topics, duplicate suppression and malformed-envelope handling through actual localhost TCP sockets. Existing modem and DSP tests continue to run. No over-the-air test has
been performed for this application protocol.

## Repeating channel announcements · QSO73 0.4.1

In a joined channel, enable **Announce until another station is heard** and choose
an interval from 1–60 minutes (default 10). This is separate from the station
callsign/grid/version beacon. The first automatic announcement follows one full
interval after enabling or connecting. It broadcasts the channel and current
topic to QST, with the callsign in the AX.25 source address. Long topics are
shortened to fit a single 200-byte application packet.

Announcements use the `announce` event, with `r` as the channel and `t` as the
topic. Receiving QSO73 0.4.1+ stations discover the channel and its initially
unknown topic without joining automatically. An announcement is an invitation,
not proof that a station joined another operator's channel.

A received join or channel message from a different callsign stops repetition
for that channel. Own echoes, direct messages, topics and other invitations do
not stop it. If a participant was heard in the preceding ten minutes, enabling
announcements immediately stops them. Silent joins cannot be detected. A stopped
announcement does not automatically resume when a participant leaves.

Automatic transmissions wait for idle modem status, audio readiness and an empty
TX queue. Station beacons and channel announcements also share a five-second
submission spacing. There is no catch-up burst after sleep. Disconnecting pauses
announcements; reconnecting waits a full interval. Leaving removes that channel's
announcement settings. Announcement settings are session-only and start off
when the application restarts.
