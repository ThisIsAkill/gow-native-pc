"""VU1 microcode straight from the disc: micro-memory images for the native VU1 build without playing.

usage: python -I tools/disc/vu1_from_disc.py --game gow1 --gen <vu1n_gen.py> <iso or extracted folder> <out dir>
       [--max-images N] [--compare <recorded micro-memory dir>]

--compare: how many of the blocks recorded while playing (data/<game>/vu1_capture, its disc_*.bin left out) the disc scan
found: at the same micro-memory address (what the build can use as is) and anywhere (same words at another address: the
game loads that program elsewhere at run time).

The game uploads VU1 microcode with VIF MPG commands (code 0x4A: NUM 64-bit instructions to micro memory address
IMMEDIATE * 8) that sit in its files as prebuilt DMA/VIF packets. This scans the boot ELF and every file of the game's TOC
for them, applies the uploads of each file in order to a 16 KB micro-memory image and keeps a snapshot each time an
upload holds a program end (E bit). The snapshots are cut down to the ones that add VU1 blocks not seen yet (block = the
runtime's key: entry pc + words, see vu1n_gen.py), so the build compiles each distinct block once, and written as
<out>/disc_<hash>.bin, the same format as the recorded micro memories (data/<game>/vu1_capture).

A block built from a snapshot whose neighbouring code differs from what the game really has resident only costs
compile time: the runtime looks blocks up by their exact words, so such a block never runs. Blocks the scan cannot see
(microcode built at run time, entries through a register) still come from the recording and the background compiler.
Heuristic, prototype: an MPG header is accepted when its data is 64-bit aligned, fits the 16 KB micro memory and decodes as
VU instructions (see plausible()). Output is game data: it stays in data/ and is never published.
"""
import argparse
import hashlib
import importlib.util
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'pipeline'))
import discfs  # noqa: E402

CODE_SIZE = 16384
VIF_MPG = 0x4A


def load_gen(path):
    spec = importlib.util.spec_from_file_location('vu1n_gen', path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def plausible(gen, code):
    """Most pairs decode as VU instructions: known upper op and, without the I bit, a lower op the generator knows."""
    pairs = len(code) // 8
    if pairs < 2:
        return False
    unknown = real = 0
    for i in range(pairs):
        lower, upper = struct.unpack_from('<II', code, i * 8)
        if lower == 0 and upper == 0:      # padding between programs: neutral
            continue
        if (upper >> 25) & 3:          # bits 25-26 are always zero in upper instructions
            unknown += 1
            continue
        kind = gen.classify(upper)[0]
        if kind == 'other':
            unknown += 1
            continue
        if not (upper >> 31):
            info = gen.lower_info(lower)
            if info['calls_out'] and (lower >> 25) not in (0x40,):
                unknown += 1
                continue
        if kind != 'nop' or lower not in (0, 0x8000033C):
            real += 1
    return real > 0 and unknown * 20 <= real        # at most 5 % odd pairs


def uploads(gen, data):
    """(header offset, end offset, micro memory address, code) of the plausible MPG uploads in one file, in file order."""
    out = []
    p = data.find(bytes([VIF_MPG]), 3)
    while p != -1:
        w = p - 3                                    # the code byte is the word's top byte (little endian)
        if w % 4 == 0 and w + 4 <= len(data):
            word, = struct.unpack_from('<I', data, w)
            if (word >> 24) & 0x7F == VIF_MPG:
                num = (word >> 16) & 0xFF or 256
                addr = (word & 0xFFFF) * 8
                start, end = w + 4, w + 4 + num * 8
                if start % 8 == 0 and addr + num * 8 <= CODE_SIZE and end <= len(data):
                    code = data[start:end]
                    if plausible(gen, code):
                        out.append((w, end, addr, code))
                        p = data.find(bytes([VIF_MPG]), end + 3)
                        continue
        p = data.find(bytes([VIF_MPG]), p + 1)
    return out


def scan(gen, data):
    """Snapshots (16 KB images) of the MPG uploads in one file: uploads that follow each other in the VIF stream (only
    VIF NOPs between them) are one program load; after each load that holds a program end (E bit) the image is kept."""
    image = bytearray(CODE_SIZE)
    snaps = []
    ups = uploads(gen, data)
    has_end = False
    for k, (w, end, addr, code) in enumerate(ups):
        image[addr:addr + len(code)] = code
        has_end = has_end or any((struct.unpack_from('<I', code, i * 8 + 4)[0] >> 30) & 1 for i in range(len(code) // 8))
        nxt = ups[k + 1][0] if k + 1 < len(ups) else None
        joined = nxt is not None and nxt - end <= 8 and data[end:nxt] == bytes(nxt - end)
        if not joined:
            if has_end:
                snaps.append(bytes(image))
            has_end = False
    return snaps


def block_keys(gen, image, words_only=None):
    """the runtime's block keys (pc + words) of an image; words_only (a set) also receives the keys of the words alone"""
    keys = set()
    for pc in gen.heads_of(image, set()):
        pairs = gen.extent(image, pc)
        if pairs:
            words = [x for pr in pairs for x in pr]
            keys.add(gen.fnv_block(pc, words))
            if words_only is not None:
                words_only.add(gen.fnv_block(0, words))
    return keys


def compare(gen, disc_keys, disc_words, recorded_dir):
    rec_keys, rec_words = {}, {}
    files = [f for f in sorted(os.listdir(recorded_dir)) if f.endswith('.bin') and not f.startswith('disc_')]
    for k, f in enumerate(files):
        img = open(os.path.join(recorded_dir, f), 'rb').read()
        if len(img) != CODE_SIZE:
            continue
        for pc in gen.heads_of(img, set()):
            pairs = gen.extent(img, pc)
            if pairs:
                words = [x for pr in pairs for x in pr]
                rec_keys[gen.fnv_block(pc, words)] = gen.fnv_block(0, words)
        if k % 500 == 0:
            print(f'@@status comparing with the recording: {k}/{len(files)} micro memories', flush=True)
    same_pc = sum(1 for key in rec_keys if key in disc_keys)
    anywhere = sum(1 for w in rec_keys.values() if w in disc_words)
    n = max(1, len(rec_keys))
    print(f'[vu1-disc] recorded: {len(files)} micro memories, {len(rec_keys)} distinct blocks; found on the disc at the '
          f'same address: {same_pc} ({100 * same_pc / n:.1f} %), same code at any address: {anywhere} ({100 * anywhere / n:.1f} %)')


def disc_files(disc, prof):
    """(name, bytes) of the boot ELF and of every TOC entry"""
    elf = prof['executable']['name']
    if disc.has(elf):
        yield elf, disc.read(elf)
    toc_name = prof['disc']['toc']
    if disc.has(toc_name):
        toc = discfs.parse_toc(disc.read(toc_name))
        seen = set()
        for _, name, _, _, _ in toc:
            if name in seen:
                continue
            seen.add(name)
            try:
                yield name, disc.pak_entry(toc, name)
            except KeyError:
                pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--game', default='gow1')
    ap.add_argument('--gen', required=True, help='vu1n_gen.py of the runtime')
    ap.add_argument('--max-images', type=int, default=0)
    ap.add_argument('--compare', default='')
    ap.add_argument('disc')
    ap.add_argument('out')
    a = ap.parse_args()
    import profile as game_profile  # tools/pipeline/profile.py
    prof = game_profile.load(a.game)
    gen = load_gen(a.gen)
    disc = discfs.open_disc(a.disc)
    os.makedirs(a.out, exist_ok=True)
    seen_images, keys, words = set(), set(), set()
    last = None
    files = uploads = kept = 0
    for name, data in disc_files(disc, prof):
        files += 1
        snaps = scan(gen, data)
        uploads += len(snaps)
        for img in snaps:
            h = hashlib.sha1(img).hexdigest()[:16]
            if h in seen_images:
                continue
            seen_images.add(h)
            new = block_keys(gen, img, words) - keys
            if not new:
                continue
            keys |= new
            with open(os.path.join(a.out, f'disc_{h}.bin'), 'wb') as f:
                f.write(img)
            kept += 1
            if a.max_images and kept >= a.max_images:
                break
        if (kept, len(keys)) != last or files % 100 == 0:   # one line when something changed (not one per file)
            last = (kept, len(keys))
            print(f'@@status VU1 microcode: {files} files read, {kept} images, {len(keys)} blocks', flush=True)
    print(f'[vu1-disc] {files} files, {uploads} program uploads, {len(seen_images)} distinct images, '
          f'{kept} kept, {len(keys)} distinct blocks -> {a.out}')
    if a.compare:
        compare(gen, keys, words, a.compare)


if __name__ == '__main__':
    main()
