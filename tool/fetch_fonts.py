#!/usr/bin/env python3
"""Downloads the bundled font library (OFL / Apache licensed Google Fonts,
Latin subset, TrueType) from Fontsource into assets/fonts/library/ and writes
index.json. Re-run to refresh. Usage: python3 tool/fetch_fonts.py"""
import json, os, sys, urllib.request

FAMILIES = [
  # Metric twins of common Office / system fonts (layout-safe substitutes).
  'carlito', 'caladea', 'gelasio', 'arimo', 'tinos', 'cousine',
  # Popular sans.
  'roboto', 'open-sans', 'lato', 'montserrat', 'poppins', 'inter', 'raleway',
  'nunito', 'source-sans-3', 'noto-sans', 'pt-sans', 'ubuntu', 'work-sans',
  'fira-sans', 'rubik', 'mulish', 'karla', 'barlow', 'cabin', 'josefin-sans',
  'ibm-plex-sans', 'titillium-web', 'hind', 'manrope', 'dm-sans', 'archivo',
  'heebo', 'libre-franklin', 'assistant', 'exo-2', 'quicksand', 'oswald',
  'noto-sans-display', 'roboto-condensed',
  # Serif.
  'noto-serif', 'pt-serif', 'merriweather', 'playfair-display', 'lora',
  'libre-baskerville', 'crimson-text', 'eb-garamond', 'cormorant-garamond',
  'source-serif-4', 'bitter', 'arvo', 'roboto-slab', 'ibm-plex-serif',
  'dm-serif-display', 'domine', 'spectral', 'cardo', 'old-standard-tt',
  # Mono.
  'roboto-mono', 'source-code-pro', 'inconsolata', 'jetbrains-mono',
  'ibm-plex-mono', 'fira-mono', 'space-mono',
  # Display / script.
  'abril-fatface', 'bebas-neue', 'anton', 'pacifico', 'caveat', 'lobster',
  'dancing-script', 'great-vibes', 'satisfy', 'permanent-marker',
]
OK_LICENSES = {'OFL-1.1', 'Apache-2.0', 'Apache License, Version 2.0', 'UFL-1.0'}
ROOT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'fonts', 'library')

def get(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'curl/8.5.0'})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()

def main():
    os.makedirs(ROOT, exist_ok=True)
    index = []
    for fid in FAMILIES:
        try:
            meta = json.loads(get(f'https://api.fontsource.org/v1/fonts/{fid}'))
        except Exception as e:
            print('skip', fid, e); continue
        lic = meta.get('license', '')
        if lic not in OK_LICENSES or 'latin' not in meta.get('subsets', []):
            print('skip (license/subset)', fid, lic); continue
        weights = meta.get('weights', [])
        styles = meta.get('styles', [])
        files = []
        for w in (400, 700):
            if w not in weights:
                continue
            for st in ('normal', 'italic'):
                if st not in styles:
                    continue
                name = f"{meta['family'].replace(' ', '')}-{'Bold' if w == 700 else 'Regular'}{'Italic' if st == 'italic' else ''}.ttf"
                name = name.replace('-RegularItalic', '-Italic')
                dest = os.path.join(ROOT, name)
                if not os.path.exists(dest):
                    try:
                        data = get(f'https://cdn.jsdelivr.net/fontsource/fonts/{fid}@latest/latin-{w}-{st}.ttf')
                    except Exception as e:
                        print('  miss', name, e); continue
                    if data[:4] not in (b'\x00\x01\x00\x00', b'true'):
                        print('  not TrueType', name); continue
                    open(dest, 'wb').write(data)
                files.append({'file': name, 'bold': w == 700, 'italic': st == 'italic'})
        if files:
            index.append({'family': meta['family'], 'category': meta.get('category', ''),
                          'license': lic, 'files': files})
            print('ok', meta['family'], len(files))
    json.dump(index, open(os.path.join(ROOT, 'index.json'), 'w'), indent=1)
    print(len(index), 'families')

main()
