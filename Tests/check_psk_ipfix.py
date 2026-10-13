"""Independent IPFIX parser for both client fixtures; never sends Internet data."""
import struct
import sys
from pathlib import Path

files = [Path(p).read_bytes() for p in sys.argv[1:]]
assert len(files) == 2 and files[0] == files[1], 'Platform encoders differ'
data = files[0]
version, length, exported, sequence, domain = struct.unpack('!HHIII', data[:16])
assert (version, length, exported, sequence, domain) == (10, len(data), 1700000020, 9, 42)
templates, records = {}, {}
offset = 16
while offset < length:
    set_id, size = struct.unpack_from('!HH', data, offset)
    assert size >= 4 and size % 4 == 0 and offset + size <= length
    payload = data[offset + 4:offset + size]
    if set_id in (2, 3):
        tid, count = struct.unpack_from('!HH', payload)
        pos = 4
        if set_id == 3:
            assert struct.unpack_from('!H', payload, pos)[0] == 1
            pos += 2
        fields = []
        for _ in range(count):
            ident, size_field = struct.unpack_from('!HH', payload, pos)
            pos += 4
            enterprise = 0
            if ident & 0x8000:
                enterprise = struct.unpack_from('!I', payload, pos)[0]
                pos += 4
            fields.append((enterprise, ident & 0x7fff, size_field))
        assert all(x == 0 for x in payload[pos:])
        templates[tid] = fields
    else:
        fields = templates[set_id]
        pos = 0
        rows = []
        while pos < len(payload) and any(payload[pos:]):
            row = {}
            for enterprise, ident, size_field in fields:
                if size_field == 65535:
                    size_field = payload[pos]
                    pos += 1
                    assert size_field < 255
                    value = payload[pos:pos + size_field].decode('utf8')
                elif ident == 6 and enterprise == 30351:
                    value = int.from_bytes(payload[pos:pos + size_field], 'big', signed=True)
                else:
                    value = int.from_bytes(payload[pos:pos + size_field], 'big')
                pos += size_field
                row[ident] = value
            rows.append(row)
        assert all(x == 0 for x in payload[pos:])
        records[set_id] = rows
    offset += size
assert templates[0x9995] == [(30351, 1, 65535), (30351, 5, 5), (30351, 6, 1), (30351, 10, 65535), (30351, 11, 1), (0, 150, 4)]
assert records[0x9992] == [{2: 'N4EAC', 4: 'FM18FW', 8: 'QSO73 test'}]
assert records[0x9995] == [
    {1: 'K1ABC', 5: 7106500, 6: -13, 10: 'PKT', 11: 1, 150: 1700000010},
    {1: 'K1ABC', 5: 5400000000, 6: -13, 10: 'PKT', 11: 1, 150: 1700000010},
]
assert len(data) < 1400
print('PASS: identical macOS/Windows IPFIX; independent templates, padding, timestamp, signed SNR, 5-byte frequency and receiver decoding')
