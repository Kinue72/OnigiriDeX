#!/usr/bin/env python3
"""Build the native DeX scheduler hooks for the supported Samsung firmware."""
import hashlib
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

STOCK_SHA = 'fdb8f2a6242c589f6c9c34f42fb410d877624f8ca4b40b39f8f93ecc27e2383f'
PATCHED_SHA = '199e03664aceb6d9a7548ba36b513b124f4c7fbdacac7f2fd058edc5eb57578c'


def patch(binary, clang):
    stock = binary.read_bytes()
    digest = hashlib.sha256(stock).hexdigest()
    if digest == PATCHED_SHA:
        return
    if digest != STOCK_SHA:
        raise SystemExit(f'Unsupported SurfaceFlinger: {digest}')
    source = Path(__file__).resolve().parent
    # shortcut: offsets match this firmware only; revalidate hooks when firmware changes.
    with tempfile.TemporaryDirectory(prefix='onigiri-dex-') as directory:
        build = Path(directory)
        for name in ('pacer.c', 'bridges.S'):
            subprocess.run([str(clang / 'clang'), '--target=aarch64-linux-android35', '-Oz', '-fPIC',
                '-ffreestanding', '-fno-stack-protector', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables',
                '-mbranch-protection=standard', '-c', str(source / name), '-o', str(build / (name + '.o'))], check=True)
        (build / 'pacer.ld').write_text('SECTIONS { . = 0x742328; .text : { *(.text*) *(.rodata*) } .bss 0x78a2a8 (NOLOAD) : { *(.bss*) } pacer_end = .; /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) } }\n')
        subprocess.run([str(clang / 'ld.lld'), '-static', '-e', 'onigiri_power_bridge', '-T', str(build / 'pacer.ld'),
            '--defsym=native_display_id=0x1ade40', '--defsym=native_property_bool=0x73eb48',
            '--defsym=native_activate=0x29e598', '--defsym=native_unregister=0x276f90',
            '--defsym=native_begin_frame=0x71a914', '--defsym=native_previous_present_fence=0x71a8b0',
            '--defsym=native_is_fence_pending=0x71adb0', '--defsym=native_add_targeter=0x278130',
            '--defsym=native_period=0x229bf0', '--defsym=native_get_snapshot=0x208640',
            '--defsym=native_display_stack=0x1aebb0', '--defsym=timeline_continue=0x2b50bc',
            '--defsym=power_continue=0x2b2cd0', str(build / 'pacer.c.o'), str(build / 'bridges.S.o'),
            '-o', str(build / 'pacer.elf')], check=True)
        subprocess.run([str(clang / 'llvm-objcopy'), '--only-section=.text', '-O', 'binary',
            str(build / 'pacer.elf'), str(build / 'pacer.bin')], check=True)
        symbols = {}
        for line in subprocess.check_output([str(clang / 'llvm-nm'), '-n', str(build / 'pacer.elf')], text=True).splitlines():
            address, _, name = line.split()
            symbols[name] = int(address, 16)
        code = (build / 'pacer.bin').read_bytes()
    if len(code) > 0xcd8 or any(stock[0x742328:0x743000]):
        raise SystemExit('SurfaceFlinger RX padding mismatch')
    patched = bytearray(stock)
    patched[0x742328:0x742328 + len(code)] = code
    program_header = 64 + 3 * 56
    if struct.unpack_from('<IIQQQQQQ', stock, program_header) != (1, 5, 0x188000, 0x188000, 0x188000, 0x5ba328, 0x5ba328, 0x1000):
        raise SystemExit('SurfaceFlinger RX segment mismatch')
    size = 0x742328 + len(code) - 0x188000
    struct.pack_into('<QQ', patched, program_header + 32, size, size)
    # Put the frame cache after stock BSS, leaving the RX padding read-only.
    data_header = 64 + 5 * 56
    if struct.unpack_from('<IIQQQQQQ', stock, data_header) != (1, 6, 0x780000, 0x780000, 0x780000, 0x3180, 0xa2a8, 0x1000):
        raise SystemExit('SurfaceFlinger RW segment mismatch')
    if not 0x78a2a8 < symbols['pacer_end'] <= 0x78b000:
        raise SystemExit('SurfaceFlinger BSS padding mismatch')
    struct.pack_into('<Q', patched, data_header + 40, symbols['pacer_end'] - 0x780000)
    for offset, expected, target, link in ((0x2b2cb0, '18010034', 'onigiri_power_bridge', False),
                                           (0x29dc7c, 'c564ff97', 'onigiri_unregister_bridge', True),
                                           (0x277c88, '238b1294', 'onigiri_frame_bridge', True),
                                           (0x277e14, 'c7000094', 'onigiri_composite_bridge', True),
                                           (0x2b50b8, 'ff4302d1', 'onigiri_transaction_ready', False)):
        delta = symbols[target] - offset
        if stock[offset:offset + 4].hex() != expected or delta % 4 or not -(1 << 27) <= delta < 1 << 27:
            raise SystemExit('SurfaceFlinger hook mismatch')
        struct.pack_into('<I', patched, offset, (0x94000000 if link else 0x14000000) | ((delta // 4) & 0x3ffffff))
    # This entry is called indirectly; replacing PACIASP with a bare branch violates BTI.
    if stock[0x2b50b4:0x2b50b8].hex() != '3f2303d5':
        raise SystemExit('SurfaceFlinger timeline landing pad mismatch')
    struct.pack_into('<I', patched, 0x2b50b4, 0xd503245f)  # BTI c; trampoline replays PACIASP and SUB SP.
    if len(patched) != len(stock) or hashlib.sha256(patched).hexdigest() != PATCHED_SHA:
        raise SystemExit('Unexpected native build; check the pinned compiler and hook sources')
    binary.write_bytes(patched)


if __name__ == '__main__':
    patch(Path(sys.argv[1]), Path(sys.argv[2]))
