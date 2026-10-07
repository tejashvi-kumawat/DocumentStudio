#!/usr/bin/env python3
"""Writes assets/fonts/library/metrics.json: advance widths of the printable
ASCII characters (1/1000 em) for every bundled font file, plus weight and
italic. Document Studio compares them with a PDF font's /Widths to
identify fonts whose names say nothing (F1, TT0, ABCDEF+...).

Usage: python3 tool/font_metrics.py   (needs fontTools)
"""
import json
import os

from fontTools.ttLib import TTFont

ROOT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'fonts', 'library')

def main():
    index = json.load(open(os.path.join(ROOT, 'index.json')))
    out = []
    for fam in index:
        for f in fam['files']:
            font = TTFont(os.path.join(ROOT, f['file']), lazy=True)
            upm = font['head'].unitsPerEm
            cmap = font.getBestCmap() or {}
            hmtx = font['hmtx'].metrics
            widths = []
            for code in range(32, 127):
                g = cmap.get(code)
                widths.append(round(hmtx[g][0] * 1000 / upm) if g in hmtx else -1)
            weight = font['OS/2'].usWeightClass if 'OS/2' in font else (700 if f.get('bold') else 400)
            out.append({
                'family': fam['family'],
                'file': f['file'],
                'bold': bool(f.get('bold')),
                'italic': bool(f.get('italic')),
                'weight': weight,
                'w': widths,
            })
    with open(os.path.join(ROOT, 'metrics.json'), 'w') as fh:
        json.dump(out, fh, separators=(',', ':'))
    print(f'{len(out)} font files')

if __name__ == '__main__':
    main()
