"""Fixture for modem73's KISS/JSON APIs. No audio, RF, or external sockets."""
import socket, threading, subprocess, pathlib, json, struct, uuid

def listener():
    sock = socket.socket()
    sock.bind(('127.0.0.1', 0)); sock.listen(1); sock.settimeout(15)
    return sock

control_listener, kiss_listener = listener(), listener()
failures = []

def control_frame(obj):
    raw = json.dumps(obj, separators=(',', ':')).encode()
    return struct.pack('!I', len(raw)) + raw

def address(call, last):
    parts = call.split('-')
    return bytes(ord(x) << 1 for x in parts[0].ljust(6)) + bytes([0x60 | (int(parts[1]) << 1 if len(parts) > 1 else 0) | last])

def kiss_frame(text, destination='TEST1'):
    payload = address(destination, 0) + address('TEST2', 1) + b'\x03\xf0' + text.encode()
    return b'\xc0\x00' + payload.replace(b'\xdb', b'\xdb\xdd').replace(b'\xc0', b'\xdb\xdc') + b'\xc0'

def serve_control():
    try:
        with control_listener.accept()[0] as sock:
            sock.settimeout(15)
            buffered = b''; polls = 0; frequency = '14105000\n'
            while True:
                raw = sock.recv(65536)
                if not raw: break
                buffered += raw
                while len(buffered) >= 4:
                    n = struct.unpack('!I', buffered[:4])[0]
                    if len(buffered) < n + 4: break
                    obj = json.loads(buffered[4:4+n]); buffered = buffered[4+n:]
                    if obj['cmd'] == 'get_config':
                        reply = {'ok': True, 'callsign': 'TEST1', 'modulation': 'RDM-600', 'payload_size': 512, 'fragmentation_enabled': True, 'carrier_threshold_db': -30, 'slot_time_ms': 500, 'csma_quiet_ms': 0, 'csma_enabled': True, 'csma_sync_only': True}
                    elif obj['cmd'] == 'rx_frame_history':
                        reply = {'ok': True, 'frames': [{'seq': 1, 'time': 1700000000, 'size': 64, 'mode': 'RDM-600', 'callsign': 'TEST2', 'snr': -8, 'ber_pct': 0.6}]}
                    elif obj['cmd'] == 'get_status':
                        polls += 1
                        if polls >= 6: return
                        reply = {'ok': True, 'channel_state': 'idle', 'audio_connected': True, 'rigctl_connected': True,
                                 'rx_frame_count': 2, 'tx_frame_count': 1, 'last_snr': -8.0, 'rx_audio_level_db': -32.5, 'tx_queue': 3, 'rx_error_count': 4, 'occupancy_pct': 12, 'client_count': 1, 'last_ber': 0.006, 'dcd_active': True, 'ptt_on': False, 'occupancy_total_pct': 18, 'csma_phase': 3, 'csma_wait_ms': 120, 'csma_wait_need_ms': 600, 'csma_rank': 1, 'csma_rank_n': 3, 'csma_window_ms': 4000, 'csma_quiet_ms': 890, 'net_bps_estimate': 900, 'sync_count': 7, 'preamble_errors': 1, 'symbol_errors': 2, 'erased_symbols': 3, 'crc_errors': 1, 'recent_tx_frames': [{'seq': 1, 'time': 1700000001, 'size': 40, 'mode': 'RDM-600'}]}
                    elif obj['cmd'] == 'rigctl':
                        extended = obj['command'].startswith('+')
                        cmd = obj['command'].lstrip('+')
                        if cmd == 'f': response = frequency
                        elif cmd == 'm': response = 'USB\n2400\n'
                        elif cmd == 't': response = ('1\n' if polls == 3 else '0\n')
                        elif cmd == 'l RFPOWER': response = '0.15\n'
                        elif cmd.startswith('\\power2mW '):
                            _, fraction, frequency_value, mode = cmd.split()
                            assert float(fraction) == 0.15 and int(frequency_value) in (14105000,14106000) and mode == 'USB'
                            response = 'Power mW: 15000\n'
                        elif cmd in ['l ALC', 'l SWR', 'l RFPOWER_METER_WATTS']:
                            assert polls == 3, 'TX-only meter read while receiving'
                            response = {'l ALC': '0.08\n', 'l SWR': '1.7\n', 'l RFPOWER_METER_WATTS': '12.5\n'}[cmd]
                        elif cmd.startswith('l '): response = 'RPRT -11\n'
                        elif cmd == 'u TUNER': response = '0\n'
                        elif cmd == 'F 14106000': frequency = '14106000\n'; response = 'RPRT 0\n'
                        else: raise AssertionError(cmd)
                        if extended and 'RPRT' not in response: response = 'readback:\n' + response + 'RPRT 0\n'
                        # Interleaved event must not consume an in-flight request.
                        sock.sendall(control_frame({'event': 'rx_frame', 'snr': -8.0}))
                        reply = {'ok': True, 'response': response}
                    else: raise AssertionError(obj)
                    frame = control_frame(reply)
                    sock.sendall(frame[:2]); sock.sendall(frame[2:])
    except Exception as exc: failures.append(repr(exc))

def serve_kiss():
    try:
        with kiss_listener.accept()[0] as sock:
            sock.settimeout(15)
            expected = b'\xc0\x00' + address('TEST2', 0) + address('TEST1', 1) + b'\x03\xf0' + 'café 👋'.encode() + b'\xc0'
            received = b''
            while len(received) < len(expected):
                chunk = sock.recv(4096)
                if not chunk: raise AssertionError('Client closed before sending')
                received += chunk
            assert received == expected, received
            reply = kiss_frame('Hello 👋') + kiss_frame('for someone else', 'TEST3') + kiss_frame('CQ café', 'QST')
            for byte in reply[:20]: sock.sendall(bytes([byte]))
            sock.sendall(reply[20:])
            buffer = b''; conversations = []
            while len(conversations) < 2:
                buffer += sock.recv(4096)
                while b'\xc0' in buffer:
                    if not buffer.startswith(b'\xc0'):
                        buffer = buffer[buffer.index(b'\xc0'):]
                    end = buffer.find(b'\xc0', 1)
                    if end < 0: break
                    raw = buffer[1:end].replace(b'\xdb\xdc', b'\xc0').replace(b'\xdb\xdd', b'\xdb')
                    buffer = buffer[end+1:]
                    if not raw: continue
                    body = raw[17:].decode()
                    assert body.startswith('~Q73:'), body
                    event = json.loads(body[5:]); conversations.append(event)
                    target = 'QST' if event['r'].startswith('#') else 'TEST2'
                    assert raw[1:8] == address(target, 0), raw
            assert {event['t'] for event in conversations} == {'channel socket test', 'direct socket test'}
            def envelope(kind, room, text):
                return '~Q73:' + json.dumps({'v': 1, 'k': kind, 'r': room, 't': text, 'id': str(uuid.uuid4())}, separators=(',', ':'))
            channel = kiss_frame(envelope('msg', '#hf', 'channel reply'), 'QST')
            sock.sendall(channel + channel + kiss_frame(envelope('topic', '#hf', 'Socket test net'), 'QST') +
                         kiss_frame('~Q73:{bad JSON', 'QST') + kiss_frame(envelope('msg', 'TEST1', 'direct reply')))
            while sock.recv(4096): pass
    except Exception as exc: failures.append(repr(exc))

threads = [threading.Thread(target=f, daemon=True) for f in [serve_control, serve_kiss]]
for thread in threads: thread.start()
exe = pathlib.Path(__file__).resolve().parent.parent / 'build' / 'modem73-network-tests'
result = subprocess.run([str(exe), str(control_listener.getsockname()[1]), str(kiss_listener.getsockname()[1])], timeout=20)
for thread in threads: thread.join(timeout=2)
control_listener.close(); kiss_listener.close()
if failures: raise RuntimeError(failures)
raise SystemExit(result.returncode)
