#!/usr/bin/env python3
"""Independently decode PNG chunk CRC/filter0 bytes and inspect diagnostic boundaries."""
import hashlib
import json
import struct
import sys
import zlib
from pathlib import Path

out = Path(sys.argv[1]); manifest = json.loads((out / 'manifest.json').read_text())
expected = {(640, 360), (480, 360), (360, 360), (360, 640), (900, 300)}
assert len(manifest['images']) == 5
failures = []
for item in manifest['images']:
    raw = (out / item['file']).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == item['sha256'] and raw[:8] == b'\x89PNG\r\n\x1a\n'
    offset, compressed, dims = 8, bytearray(), None
    while offset < len(raw):
        size = struct.unpack_from('>I', raw, offset)[0]; tag = raw[offset + 4:offset + 8]
        payload = raw[offset + 8:offset + 8 + size]
        crc = struct.unpack_from('>I', raw, offset + 8 + size)[0]
        assert zlib.crc32(tag + payload) & 0xffffffff == crc
        if tag == b'IHDR':
            width, height, depth, color, compression, filtering, interlace = struct.unpack('>IIBBBBB', payload)
            assert (depth, color, compression, filtering, interlace) == (8, 6, 0, 0, 0)
            dims = width, height
        if tag == b'IDAT': compressed.extend(payload)
        offset += 12 + size
        if tag == b'IEND': break
    assert offset == len(raw) and dims in expected
    expected.remove(dims)
    assert dims == (item['width'], item['height'])
    data = zlib.decompress(compressed); stride = width * 4 + 1
    assert len(data) == height * stride and all(data[y * stride] == 0 for y in range(height))
    def pixel(x, y):
        start = y * stride + 1 + x * 4
        return list(data[start:start + 4])
    assert all(data[y * stride + 1 + x * 4 + 3] == 255 for y in range(height) for x in range(width))
    nonwhite = sum(pixel(x, y) != [255]*4 for y in range(height) for x in range(width) if min(x, y, width-1-x, height-1-y) < 8)
    if nonwhite: failures.append({'file': item['file'], 'nonwhite_border_pixels': nonwhite})
    for corner, sample in item['cornerBlocks'].items():
        point = sample['center']
        expected_color = {'top_left':[255,0,0,255], 'top_right':[0,255,0,255], 'bottom_left':[0,0,255,255], 'bottom_right':[255,255,0,255]}[corner]
        assert pixel(point['x'], point['y']) == sample['rgba'] == expected_color
    assert pixel(width//2, height//2) == [200,200,200,255]
    print(item['file'], width, height, 'border:', 'fail' if nonwhite else 'pass')
assert not expected
print(json.dumps({'status': 'fail' if failures else 'pass', 'images': 5, 'failures': failures}))
sys.exit(bool(failures))
