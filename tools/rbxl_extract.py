"""Extract every script's Source out of a BINARY Roblox place file (.rbxl) into a source tree.

Why this exists: Studio's Save As dialog in this install offers only the binary `.rbxl`
format, not the XML `.rbxlx` -- so the place cannot simply be read as text. Pulling each
script through the Studio MCP instead costs roughly 180k tokens for this place, which does
not fit in one session. This parses the binary format directly and is free to re-run.

Format reference (rbx-dom / rbxl binary v0):

    header   "<roblox!" + 6-byte signature + u16 version + u32 classCount
             + u32 instanceCount + 8 reserved bytes                        = 32 bytes
    chunk    4-byte name + u32 compressedLen + u32 uncompressedLen + 4 reserved
             + payload (compressedLen == 0 means the payload is stored raw)
    INST     i32 classId, String className, u8 isService, i32 count,
             referents (interleaved i32), [u8 * count if isService]
    PROP     i32 classId, String propName, u8 typeId, then one value per instance,
             in the same order as that class's INST referents
    PRNT     u8 version, i32 count, childRefs (interleaved), parentRefs (interleaved)
    SSTR     u32 version, u32 count, then per entry 16-byte hash + String

Strings inside a chunk are u32 length + bytes. Referent arrays are interleaved by byte
position, zigzag-encoded and stored as deltas -- see read_referents.

Chunks in this place are zstd-compressed (older places used LZ4); both are handled.

Usage:  C:\\Python313\\python.exe tools/rbxl_extract.py <place.rbxl> <out_dir>
"""

import os
import struct
import sys

try:
    import zstandard
except ImportError:
    zstandard = None
try:
    import lz4.block
except ImportError:
    lz4 = None

# Roblox class name -> file suffix. Keeping Script and ModuleScript distinguishable matters:
# pushing a ModuleScript back into Studio as a Script would break the place silently.
SUFFIX = {
    "ModuleScript": ".lua",
    "Script": ".server.lua",
    "LocalScript": ".client.lua",
}

STRING_TYPE = 0x01
SHARED_STRING_TYPE = 0x1C


class Reader:
    def __init__(self, buf):
        self.buf = buf
        self.pos = 0

    def take(self, n):
        out = self.buf[self.pos:self.pos + n]
        self.pos += n
        return out

    def u8(self):
        v = self.buf[self.pos]
        self.pos += 1
        return v

    def i32(self):
        v = struct.unpack_from("<i", self.buf, self.pos)[0]
        self.pos += 4
        return v

    def u32(self):
        v = struct.unpack_from("<I", self.buf, self.pos)[0]
        self.pos += 4
        return v

    def string(self):
        return self.take(self.u32())


def read_referents(reader, count):
    """Interleaved, zigzag-encoded, delta-accumulated i32 array."""
    raw = reader.take(count * 4)
    out = []
    acc = 0
    for i in range(count):
        n = (raw[i] << 24) | (raw[count + i] << 16) | (raw[2 * count + i] << 8) | raw[3 * count + i]
        acc += (n >> 1) ^ -(n & 1)  # zigzag, then delta
        out.append(acc)
    return out


def decompress(payload, clen, ulen):
    if clen == 0:
        return payload
    if payload[:4] == b"\x28\xb5\x2f\xfd":
        if zstandard is None:
            sys.exit("zstd chunk found -- run: pip install zstandard")
        return zstandard.ZstdDecompressor().decompress(payload, max_output_size=ulen)
    if lz4 is None:
        sys.exit("LZ4 chunk found -- run: pip install lz4")
    return lz4.block.decompress(payload, uncompressed_size=ulen)


def parse(path):
    data = open(path, "rb").read()
    if data[:8] != b"<roblox!":
        sys.exit("not a binary .rbxl (an XML .rbxlx starts with '<roblox '), got %r" % data[:8])

    version, class_count, instance_count = struct.unpack_from("<HII", data, 14)

    classes = {}       # classId -> {"name": str, "refs": [referent]}
    props = {}         # (classId, propName) -> {referent: value}
    parents = {}       # referent -> parent referent
    shared = []        # SSTR table

    off = 32
    while off < len(data):
        name = data[off:off + 4]
        clen, ulen, _reserved = struct.unpack_from("<III", data, off + 4)
        off += 16
        size = clen if clen else ulen
        payload = data[off:off + size]
        off += size

        if name.startswith(b"END"):
            break

        r = Reader(decompress(payload, clen, ulen))

        if name == b"INST":
            class_id = r.i32()
            class_name = r.string().decode("utf-8")
            is_service = r.u8()
            count = r.i32()
            refs = read_referents(r, count)
            if is_service:
                r.take(count)
            classes[class_id] = {"name": class_name, "refs": refs}

        elif name == b"PROP":
            class_id = r.i32()
            prop_name = r.string().decode("utf-8")
            type_id = r.u8()
            # Only the two string-shaped properties are needed, and only those are safe to
            # read without decoding every other property type in the format.
            if prop_name not in ("Name", "Source"):
                continue
            refs = classes.get(class_id, {}).get("refs", [])
            values = {}
            if type_id == STRING_TYPE:
                for ref in refs:
                    values[ref] = r.string()
            elif type_id == SHARED_STRING_TYPE:
                for ref in refs:
                    values[ref] = ("__shared__", r.u32())
            else:
                continue
            props[(class_id, prop_name)] = values

        elif name == b"PRNT":
            r.u8()
            count = r.i32()
            children = read_referents(r, count)
            mothers = read_referents(r, count)
            for child, mother in zip(children, mothers):
                parents[child] = mother

        elif name == b"SSTR":
            r.u32()
            count = r.u32()
            for _ in range(count):
                r.take(16)  # md5 hash of the entry, unused here
                shared.append(r.string())

    return {
        "version": version,
        "class_count": class_count,
        "instance_count": instance_count,
        "classes": classes,
        "props": props,
        "parents": parents,
        "shared": shared,
    }


def resolve(value, shared):
    if isinstance(value, tuple) and value and value[0] == "__shared__":
        index = value[1]
        return shared[index] if index < len(shared) else b""
    return value


def build_index(place):
    """referent -> (className, name); plus a referent -> full dotted path map."""
    names = {}
    class_of = {}
    for class_id, info in place["classes"].items():
        by_name = place["props"].get((class_id, "Name"), {})
        for ref in info["refs"]:
            class_of[ref] = info["name"]
            raw = resolve(by_name.get(ref, b""), place["shared"])
            names[ref] = raw.decode("utf-8", "replace") or info["name"]

    parents = place["parents"]

    def path_of(ref):
        parts = []
        seen = set()
        while ref != -1 and ref in names and ref not in seen:
            seen.add(ref)
            parts.append(names[ref])
            ref = parents.get(ref, -1)
        return list(reversed(parts))

    return names, class_of, path_of


def safe(part):
    for bad in '<>:"/\\|?*':
        part = part.replace(bad, "_")
    return part.strip().rstrip(".") or "_"


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    place_path, out_dir = sys.argv[1], sys.argv[2]

    place = parse(place_path)
    names, class_of, path_of = build_index(place)

    print("format version %d, %d classes, %d instances"
          % (place["version"], place["class_count"], place["instance_count"]))

    written = 0
    total_bytes = 0
    manifest = []

    for class_id, info in place["classes"].items():
        suffix = SUFFIX.get(info["name"])
        if suffix is None:
            continue
        sources = place["props"].get((class_id, "Source"))
        if not sources:
            print("  ! %s has no Source property chunk" % info["name"])
            continue
        for ref in info["refs"]:
            source = resolve(sources.get(ref, b""), place["shared"])
            parts = path_of(ref)
            if not parts:
                continue
            rel = os.path.join(*[safe(p) for p in parts[:-1]] + [safe(parts[-1]) + suffix])
            dest = os.path.join(out_dir, rel)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            # newline="" keeps whatever line endings the place stores; Luau does not care and
            # this way a re-extract is byte-stable instead of churning the whole tree.
            with open(dest, "wb") as fh:
                fh.write(source)
            written += 1
            total_bytes += len(source)
            manifest.append((rel.replace("\\", "/"), len(source)))

    manifest.sort()
    print("wrote %d scripts, %d bytes" % (written, total_bytes))
    for rel, size in manifest:
        print("  %8d  %s" % (size, rel))


if __name__ == "__main__":
    main()
