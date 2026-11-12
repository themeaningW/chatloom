#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Verify source iOS icons and, optionally, a staged Windows xcross bundle.

Usage: python scripts/ios/verify-app-icons.py [--bundle build/xcross-ios/chatloom.app]
This checks resources/metadata before signing; it does not prove SpringBoard's
icon cache or notification presentation on a physical iPhone.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import struct

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'


def verify(bundle=None):
    catalog = json.loads((CATALOG / 'Contents.json').read_text())
    unique = {}
    expected = {'iphone': set(), 'ipad': set()}
    for image in catalog['images']:
        pixels = round(float(image['size'].split('x')[0]) *
                       float(image['scale'].removesuffix('x')))
        unique[image['filename']] = pixels
        if image['idiom'] in expected:
            expected[image['idiom']].add(image['filename'])
    for name, pixels in unique.items():
        data = (CATALOG / name).read_bytes()
        assert data[:8] == b'\x89PNG\r\n\x1a\n', name
        assert struct.unpack('>II', data[16:24]) == (pixels, pixels), name
        assert data[25] == 2, f'{name} must be an opaque RGB PNG'

    project = (ROOT / 'ios/Runner.xcodeproj/project.pbxproj').read_text()
    resources = project.split('/* Begin PBXResourcesBuildPhase section */')[1]
    resources = resources.split('/* End PBXResourcesBuildPhase section */')[0]
    loose = expected['iphone'] | expected['ipad']
    for name in loose:
        assert f'/* {name} in Resources */,' in resources, name
        refs = re.findall(r'([A-F0-9]{24}) /\* ' + re.escape(name) +
                          r' \*/ = \{isa = PBXFileReference;', project)
        assert len(refs) == 1, f'Missing/duplicate file reference: {name}'

    source_info = plistlib.loads((ROOT / 'ios/Runner/Info.plist').read_bytes())
    for idiom, key in [('iphone', 'CFBundleIcons'), ('ipad', 'CFBundleIcons~ipad')]:
        declared = source_info[key]['CFBundlePrimaryIcon']['CFBundleIconFiles']
        assert set(declared) == expected[idiom], key

    result = {'catalogImages': len(unique), 'looseResources': len(loose),
              'opaqueRgb': True, 'sourceMetadataMatches': True,
              'physicalIconAndNotificationAcceptance': 'Pending'}
    if bundle is not None:
        bundle = Path(bundle).resolve(strict=True)
        info = plistlib.loads((bundle / 'Info.plist').read_bytes())
        for key in ['CFBundleIcons', 'CFBundleIcons~ipad']:
            assert info[key] == source_info[key], f'Bundle lost {key}'
        for name in loose:
            assert (bundle / name).read_bytes() == (CATALOG / name).read_bytes(), name
        result.update(bundle=str(bundle), build=str(info['CFBundleVersion']),
                      stagedMetadataMatches=True,
                      iconHashes={n: hashlib.sha256((bundle / n).read_bytes()).hexdigest()
                                  for n in sorted(loose)})
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path)
    print(json.dumps(verify(parser.parse_args().bundle), indent=2))
