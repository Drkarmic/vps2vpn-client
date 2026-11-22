"""Fails when a PE file in a release zip loads its imports from System32 only
(LOAD_LIBRARY_SEARCH_SYSTEM32) yet imports a DLL that ships only in the zip:
on a PC without that DLL in System32 it would not start.

Usage: python -I tool/check_load_flags.py <portable.zip>
"""

import struct
import sys
import zipfile

SEARCH_SYSTEM32 = 0x800


def _sections(data, pe):
    count = struct.unpack_from('<H', data, pe + 6)[0]
    optional = struct.unpack_from('<H', data, pe + 20)[0]
    start = pe + 24 + optional
    return [struct.unpack_from('<8xIIII', data, start + i * 40) for i in range(count)]


def _offset(sections, rva):
    for size, address, raw_size, raw in sections:
        if address <= rva < address + max(size, raw_size):
            return rva - address + raw
    raise ValueError(f'rva {rva:#x} is in no section')


def _cstring(data, offset):
    return data[offset:data.index(b'\0', offset)].decode('ascii')


def inspect(data):
    """Answers (DependentLoadFlags, imported DLL names) of a PE image."""
    pe = struct.unpack_from('<I', data, 0x3C)[0]
    if data[pe:pe + 4] != b'PE\0\0':
        raise ValueError('not a PE image')
    magic = struct.unpack_from('<H', data, pe + 24)[0]
    directories = pe + 24 + (112 if magic == 0x20B else 96)
    sections = _sections(data, pe)

    imports = []
    import_rva = struct.unpack_from('<I', data, directories + 8)[0]
    if import_rva:
        entry = _offset(sections, import_rva)
        while True:
            name_rva = struct.unpack_from('<I', data, entry + 12)[0]
            if name_rva == 0:
                break
            imports.append(_cstring(data, _offset(sections, name_rva)))
            entry += 20

    flags = 0
    config_rva = struct.unpack_from('<I', data, directories + 10 * 8)[0]
    if config_rva:
        config = _offset(sections, config_rva)
        size = struct.unpack_from('<I', data, config)[0]
        field = 0x4E if magic == 0x20B else 0x3A
        if size >= field + 2:
            flags = struct.unpack_from('<H', data, config + field)[0]
    return flags, imports


def problems(files):
    """files maps a zip member name to its bytes."""
    bundled = {name.rsplit('/', 1)[-1].lower() for name in files if name.lower().endswith('.dll')}
    found = []
    for name, data in sorted(files.items()):
        if not name.lower().endswith(('.exe', '.dll')):
            continue
        flags, imports = inspect(data)
        if not flags & SEARCH_SYSTEM32:
            continue
        for dll in imports:
            if dll.lower() in bundled:
                found.append(f'{name}: loads from System32 only but imports bundled {dll}')
    return found


def main(argv):
    if len(argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    with zipfile.ZipFile(argv[1]) as archive:
        files = {
            info.filename: archive.read(info)
            for info in archive.infolist()
            if info.filename.lower().endswith(('.exe', '.dll'))
        }
    found = problems(files)
    for line in found:
        print(line, file=sys.stderr)
    checked = sum(1 for name in files if name.lower().endswith(('.exe', '.dll')))
    print(f'checked {checked} PE files, {len(found)} problems')
    return 1 if found else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
