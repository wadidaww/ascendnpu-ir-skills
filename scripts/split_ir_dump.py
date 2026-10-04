#!/usr/bin/env python3
"""Split an MLIR pass IR dump (from --mlir-print-ir-before-all/-after-all or
--debug) into one file per pass boundary.

MLIR prints boundaries like:

    // -----// IR Dump Before SomePass (some-pass) //----- //

This reads such a log (file or stdin) and writes one numbered .mlir file per
section into an output directory, plus an index.txt listing them. It lets you
inspect "the IR before each pass" (AscendNPU-IR debugging step 7).

Usage:
    split_ir_dump.py -i compile.log -o ir_dumps/
    bishengir-compile ... --mlir-print-ir-after-all 2>&1 | split_ir_dump.py -o ir_dumps/
"""
import argparse
import os
import re
import sys

# Matches both "IR Dump Before/After <Pass>" marker styles MLIR emits.
MARKER = re.compile(r'//\s*-+//\s*IR Dump (Before|After) (.+?)\s*//\s*-+\s*//')


def sanitize(name: str) -> str:
    name = re.sub(r'\s+', '_', name.strip())
    name = re.sub(r'[^A-Za-z0-9._-]', '', name)
    return name[:80] or "section"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('-i', '--input', default='-',
                    help="Input log file (default: stdin).")
    ap.add_argument('-o', '--outdir', required=True,
                    help="Directory to write the per-pass .mlir files into.")
    ap.add_argument('--prefix', default='',
                    help="Optional filename prefix for each section.")
    args = ap.parse_args()

    src = sys.stdin if args.input == '-' else open(args.input, 'r', errors='replace')
    os.makedirs(args.outdir, exist_ok=True)

    sections = []          # (phase, pass_name, [lines])
    current = None
    preamble = []

    for line in src:
        m = MARKER.search(line)
        if m:
            if current is not None:
                sections.append(current)
            current = [m.group(1), m.group(2), []]
        elif current is None:
            preamble.append(line)
        else:
            current[2].append(line)
    if current is not None:
        sections.append(current)
    if src is not sys.stdin:
        src.close()

    index_path = os.path.join(args.outdir, 'index.txt')
    with open(index_path, 'w') as idx:
        if preamble and ''.join(preamble).strip():
            pre = os.path.join(args.outdir, f'{args.prefix}0000_preamble.txt')
            with open(pre, 'w') as f:
                f.writelines(preamble)
            idx.write(f'0000  (preamble)                     {os.path.basename(pre)}\n')

        if not sections:
            print("split_ir_dump: no 'IR Dump Before/After' markers found "
                  "(did you pass --mlir-print-ir-after-all / -before-all?)",
                  file=sys.stderr)
            return 1

        for n, (phase, name, lines) in enumerate(sections, start=1):
            fname = f'{args.prefix}{n:04d}_{phase}_{sanitize(name)}.mlir'
            with open(os.path.join(args.outdir, fname), 'w') as f:
                f.writelines(lines)
            idx.write(f'{n:04d}  {phase:<6} {name:<40} {fname}\n')

    print(f"split_ir_dump: wrote {len(sections)} sections to {args.outdir} "
          f"(index: {index_path})", file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
