# Generates the world map of the « Map » view of the P2P order book: features/p2p/assets/map/world_110m.bin.
# Its source is Natural Earth's 1:110m « Admin 0 – Countries », public domain ("Everything here is public domain",
# LICENSE.md of the repository below): the GeoJSON file of SOURCE_URL, at SOURCE_COMMIT, whose size and SHA-256 are
# SOURCE_BYTES and SOURCE_SHA256. The source is not committed: the script takes its path, reads it as data only, and
# refuses any file that is not that one, so that the asset can only be what this file says.
# What it keeps: the outer ring of every polygon of every country, in the order of the source. The only hole of the source,
# Lesotho inside South Africa, is also the outer ring of Lesotho, so dropping holes loses nothing that is drawn.
# Each point is rounded to the hundredth of a degree (about 1 km, finer than the 1:110m data), exactly, from the decimal
# text of the source, half to even. Repeated points and the closing point are dropped; a ring left with fewer than
# 3 points, or with an area under MIN_RING_AREA square degrees (slivers and specks, not the islands the 1:110m scale keeps),
# is dropped. Every ring is turned counter-clockwise (longitude east, latitude north), so that the app can fill all of
# them as one path, a country inside another included, without leaving a hole.
# Format, little-endian: the 8 bytes « TROCMAP1 »; the number of rings (uint16); the number of points of each ring
# (uint16, at least 3); then every point of every ring, in order, as its longitude then its latitude in hundredths of a
# degree (int16 each, within ±18000 and ±9000). Nothing follows. The app's reader (`WorldMap.parse` in
# features/p2p/lib/src/domain/world_map.dart) refuses anything else.
# The script is deterministic: the same source gives the same bytes, and --check tells whether the committed asset is what
# it generates. features/p2p/test/world_map_test.dart pins the asset's SHA-256, and runs --check when TROC_NATURAL_EARTH
# names the source file and python3 is there.
# Usage: python3 tools/troc_world_map.py <ne_110m_admin_0_countries.geojson> [repo-root]           writes the asset
#        python3 tools/troc_world_map.py --check <ne_110m_admin_0_countries.geojson> [repo-root]   writes nothing, exits 1 if it differs
import hashlib
import json
import os
import struct
import sys
from decimal import ROUND_HALF_EVEN, Decimal

SOURCE_URL = 'https://github.com/nvkelso/natural-earth-vector/blob/ca96624a56bd078437bca8184e78163e5039ad19/geojson/ne_110m_admin_0_countries.geojson'
SOURCE_COMMIT = 'ca96624a56bd078437bca8184e78163e5039ad19'
SOURCE_BYTES = 838726
SOURCE_SHA256 = '6866c877d39cba9c357620878839b336d569f8c662d3cfab4cb1dbe2d39c977f'

ASSET = os.path.join('features', 'p2p', 'assets', 'map', 'world_110m.bin')
MAGIC = b'TROCMAP1'
MIN_RING_AREA = Decimal('0.01')  # square degrees, about 11 km by 11 km at the equator
HUNDREDTH = Decimal('0.01')


def quantise(value):
    """A coordinate of the source, exact, in hundredths of a degree."""
    return int((value / HUNDREDTH).quantize(Decimal(1), rounding=ROUND_HALF_EVEN))


def twice_area(ring):
    """Twice the signed area of a closed ring given without its closing point, in square hundredths of a degree."""
    total = 0
    for i, (x0, y0) in enumerate(ring):
        x1, y1 = ring[(i + 1) % len(ring)]
        total += x0 * y1 - x1 * y0
    return total


def rings_of(source):
    """The rings kept, in the order of the source, each a list of (longitude, latitude) in hundredths of a degree."""
    kept, dropped = [], 0
    for feature in source['features']:
        geometry = feature['geometry']
        if geometry['type'] not in ('Polygon', 'MultiPolygon'):
            raise ValueError('unexpected geometry ' + geometry['type'])
        polygons = [geometry['coordinates']] if geometry['type'] == 'Polygon' else geometry['coordinates']
        for polygon in polygons:
            ring = []
            for lon, lat in (point[:2] for point in polygon[0]):
                point = (quantise(lon), quantise(lat))
                if not (-18000 <= point[0] <= 18000 and -9000 <= point[1] <= 9000):
                    raise ValueError('point out of bounds')
                if not ring or ring[-1] != point:
                    ring.append(point)
            while len(ring) > 1 and ring[-1] == ring[0]:
                ring.pop()
            area = twice_area(ring) if len(ring) >= 3 else 0
            if len(ring) < 3 or Decimal(abs(area)) / 2 < MIN_RING_AREA * 10000:
                dropped += 1
                continue
            if area < 0:
                ring.reverse()
            kept.append(ring)
    return kept, dropped


def encode(rings):
    if not 0 < len(rings) <= 0xFFFF or any(not 3 <= len(ring) <= 0xFFFF for ring in rings):
        raise ValueError('too many rings or points')
    out = bytearray(MAGIC)
    out += struct.pack('<H', len(rings))
    for ring in rings:
        out += struct.pack('<H', len(ring))
    for ring in rings:
        for lon, lat in ring:
            out += struct.pack('<hh', lon, lat)
    return bytes(out)


def main(argv):
    check = '--check' in argv
    args = [a for a in argv if a != '--check']
    if not args:
        sys.exit('usage: troc_world_map.py [--check] <ne_110m_admin_0_countries.geojson> [repo-root]')
    source_path = args[0]
    root = args[1] if len(args) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    with open(source_path, 'rb') as f:
        raw = f.read()
    if len(raw) != SOURCE_BYTES or hashlib.sha256(raw).hexdigest() != SOURCE_SHA256:
        sys.exit('not the pinned source: expected %d bytes with SHA-256 %s' % (SOURCE_BYTES, SOURCE_SHA256))
    rings, dropped = rings_of(json.loads(raw.decode('utf-8'), parse_float=Decimal))
    asset = encode(rings)
    target = os.path.join(root, ASSET)
    points = sum(len(ring) for ring in rings)
    summary = '%d rings, %d points, %d rings dropped, %d bytes, SHA-256 %s' % (
        len(rings), points, dropped, len(asset), hashlib.sha256(asset).hexdigest())
    if check:
        try:
            with open(target, 'rb') as f:
                same = f.read() == asset
        except FileNotFoundError:
            same = False
        print(('up to date: ' if same else 'DIFFERS: ') + summary)
        sys.exit(0 if same else 1)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, 'wb') as f:
        f.write(asset)
    print('wrote ' + ASSET + ': ' + summary)


if __name__ == '__main__':
    main(sys.argv[1:])
