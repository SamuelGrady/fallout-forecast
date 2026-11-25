#!/usr/bin/env python3
"""Fallout Forecast Open Protocol — Full-tier reference client & conformance checker.

Stdlib-only (Python 3.10+). Supports:
  - Transports: WebSocket (ws, default port 7780) and raw TCP (tcp, default port 7781)
  - Encodings:  json (text frames with tagged Variant JSON) and bin (0x03/0x04 binary
                frames carrying Godot 4.7.2 encode_var Variant payloads)
  - Modes:
      check       Run automated conformance checks (handshake -> lobby -> run -> walk -> stream)
      reject      Verify bad Net.PROTOCOL is rejected via Net._reject
      play        Stay connected, walk a path, and log decoded RPCs until interrupted

Example:
  python tools/open_protocol/full_client.py --transport ws --enc json --port 17780 --mode check
  python tools/open_protocol/full_client.py --transport tcp --enc bin --port 17781 --mode check
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import math
import os
import select
import socket
import struct
import sys
import time
from dataclasses import dataclass
from typing import Any

OPEN_PROTOCOL_VERSION = 1
FULL_BIN_RPC = 0x03
FULL_BIN_RAW = 0x04

TRANSFER_UNRELIABLE = 0
TRANSFER_UNRELIABLE_ORDERED = 1
TRANSFER_RELIABLE = 2

# Godot 4.7.2 Variant::Type enum values
TYPE_NIL = 0
TYPE_BOOL = 1
TYPE_INT = 2
TYPE_FLOAT = 3
TYPE_STRING = 4
TYPE_VECTOR2 = 5
TYPE_VECTOR2I = 6
TYPE_RECT2 = 7
TYPE_RECT2I = 8
TYPE_VECTOR3 = 9
TYPE_VECTOR3I = 10
TYPE_TRANSFORM2D = 11
TYPE_VECTOR4 = 12
TYPE_VECTOR4I = 13
TYPE_PLANE = 14
TYPE_QUATERNION = 15
TYPE_AABB = 16
TYPE_BASIS = 17
TYPE_TRANSFORM3D = 18
TYPE_PROJECTION = 19
TYPE_COLOR = 20
TYPE_STRING_NAME = 21
TYPE_NODE_PATH = 22
TYPE_RID = 23
TYPE_OBJECT = 24
TYPE_CALLABLE = 25
TYPE_SIGNAL = 26
TYPE_DICTIONARY = 27
TYPE_ARRAY = 28
TYPE_PACKED_BYTE_ARRAY = 29
TYPE_PACKED_INT32_ARRAY = 30
TYPE_PACKED_INT64_ARRAY = 31
TYPE_PACKED_FLOAT32_ARRAY = 32
TYPE_PACKED_FLOAT64_ARRAY = 33
TYPE_PACKED_STRING_ARRAY = 34
TYPE_PACKED_VECTOR2_ARRAY = 35
TYPE_PACKED_VECTOR3_ARRAY = 36
TYPE_PACKED_COLOR_ARRAY = 37
TYPE_PACKED_VECTOR4_ARRAY = 38

HEADER_FLAG_64 = 1 << 16


# ---------------------------------------------------------------------------
# Tagged Variant wrappers (used by both JSON and binary encoders/decoders)
# ---------------------------------------------------------------------------

def v_vec2(x: float, y: float) -> dict[str, Any]:
    return {"_t": "v2", "v": [float(x), float(y)]}


def v_vec3(x: float, y: float, z: float) -> dict[str, Any]:
    return {"_t": "v3", "v": [float(x), float(y), float(z)]}


def v_color(r: float, g: float, b: float, a: float = 1.0) -> dict[str, Any]:
    return {"_t": "color", "v": [float(r), float(g), float(b), float(a)]}


def v_node_path(path: str) -> dict[str, Any]:
    return {"_t": "np", "v": str(path)}


def v_string_name(name: str) -> dict[str, Any]:
    return {"_t": "sn", "v": str(name)}


def v_dict(pairs: list[tuple[Any, Any]]) -> dict[str, Any]:
    return {"_t": "dict", "v": [[k, v] for k, v in pairs]}


def decode_roster_arg(arg: Any) -> dict[int, dict[str, Any]]:
    """Normalize Net._push_roster's first argument from either JSON or bin form."""
    out: dict[int, dict[str, Any]] = {}
    if isinstance(arg, dict) and arg.get("_t") == "dict" and isinstance(arg.get("v"), list):
        for pair in arg["v"]:
            if isinstance(pair, list) and len(pair) == 2:
                out[int(pair[0])] = pair[1]
    elif isinstance(arg, dict):
        for k, v in arg.items():
            try:
                out[int(k)] = v
            except (TypeError, ValueError):
                pass
    return out


# ---------------------------------------------------------------------------
# Godot 4.7.2 encode_var / decode_var binary codec (core/io/marshalls.cpp)
# ---------------------------------------------------------------------------

def _pad4(n: int) -> int:
    rem = n % 4
    return (4 - rem) if rem else 0


def _enc_str(s: str) -> bytes:
    raw = s.encode("utf-8")
    pad = _pad4(len(raw))
    return struct.pack("<I", len(raw)) + raw + (b"\x00" * pad)


def _dec_str(buf: bytes, ofs: int) -> tuple[str, int]:
    if ofs + 4 > len(buf):
        raise ValueError("Truncated string length")
    slen = struct.unpack_from("<I", buf, ofs)[0]
    ofs += 4
    pad = _pad4(slen)
    if ofs + slen + pad > len(buf):
        raise ValueError("Truncated string body")
    s = buf[ofs : ofs + slen].decode("utf-8")
    return s, ofs + slen + pad


def _skip_container_type(buf: bytes, ofs: int, kind: int) -> int:
    if kind == 0:
        return ofs
    if kind == 1:
        if ofs + 4 > len(buf):
            raise ValueError("Truncated container builtin type")
        return ofs + 4
    if kind in (2, 3):
        _, ofs = _dec_str(buf, ofs)
        return ofs
    raise ValueError(f"Unknown container type kind {kind}")


def encode_godot_var(val: Any) -> bytes:
    """Encode a Python value (or Open Protocol tagged dict) to Godot encode_var bytes."""
    if val is None:
        return struct.pack("<I", TYPE_NIL)
    if isinstance(val, bool):
        return struct.pack("<II", TYPE_BOOL, 1 if val else 0)
    if isinstance(val, int):
        if -2147483648 <= val <= 2147483647:
            return struct.pack("<Ii", TYPE_INT, val)
        return struct.pack("<Iq", TYPE_INT | HEADER_FLAG_64, val)
    if isinstance(val, float):
        # Match marshalls.cpp: use float32 if exact, else float64.
        try:
            f32 = struct.unpack("<f", struct.pack("<f", val))[0]
            exact32 = (f32 == val) or (math.isnan(val) and math.isnan(f32))
        except OverflowError:
            exact32 = False
        if exact32:
            return struct.pack("<If", TYPE_FLOAT, val)
        return struct.pack("<Id", TYPE_FLOAT | HEADER_FLAG_64, val)
    if isinstance(val, str):
        return struct.pack("<I", TYPE_STRING) + _enc_str(val)
    if isinstance(val, list):
        body = [struct.pack("<II", TYPE_ARRAY, len(val))]
        for item in val:
            body.append(encode_godot_var(item))
        return b"".join(body)
    if isinstance(val, dict):
        if "_t" in val and "v" in val and isinstance(val["_t"], str):
            return _encode_tagged_var(val["_t"], val["v"])
        body = [struct.pack("<II", TYPE_DICTIONARY, len(val))]
        for k, v in val.items():
            body.append(encode_godot_var(k))
            body.append(encode_godot_var(v))
        return b"".join(body)
    raise TypeError(f"Unsupported Variant value: {type(val).__name__}")


def _encode_tagged_var(tag: str, v: Any) -> bytes:
    if tag in ("i", "i64"):
        return encode_godot_var(int(v))
    if tag == "f":
        if v == "NaN":
            return encode_godot_var(float("nan"))
        if v == "Inf":
            return encode_godot_var(float("inf"))
        if v == "-Inf":
            return encode_godot_var(float("-inf"))
        return encode_godot_var(float(v))
    if tag == "v2":
        return struct.pack("<Iff", TYPE_VECTOR2, float(v[0]), float(v[1]))
    if tag == "v2i":
        return struct.pack("<Iii", TYPE_VECTOR2I, int(v[0]), int(v[1]))
    if tag == "rect2":
        return struct.pack("<Iffff", TYPE_RECT2, *(float(x) for x in v))
    if tag == "rect2i":
        return struct.pack("<Iiiii", TYPE_RECT2I, *(int(x) for x in v))
    if tag == "v3":
        return struct.pack("<Ifff", TYPE_VECTOR3, float(v[0]), float(v[1]), float(v[2]))
    if tag == "v3i":
        return struct.pack("<Iiii", TYPE_VECTOR3I, int(v[0]), int(v[1]), int(v[2]))
    if tag == "xform2d":
        vals = [float(v[0][0]), float(v[0][1]), float(v[1][0]), float(v[1][1]), float(v[2][0]), float(v[2][1])]
        return struct.pack("<I6f", TYPE_TRANSFORM2D, *vals)
    if tag == "v4":
        return struct.pack("<I4f", TYPE_VECTOR4, *(float(x) for x in v))
    if tag == "v4i":
        return struct.pack("<I4i", TYPE_VECTOR4I, *(int(x) for x in v))
    if tag == "plane":
        return struct.pack("<I4f", TYPE_PLANE, *(float(x) for x in v))
    if tag == "quat":
        return struct.pack("<I4f", TYPE_QUATERNION, *(float(x) for x in v))
    if tag == "aabb":
        return struct.pack("<I6f", TYPE_AABB, *(float(x) for x in v[0]), *(float(x) for x in v[1]))
    if tag == "basis":
        # Godot stores Basis in row-major order (rows[0..2] where rows[r][c] = basis[c][r])
        bx, by, bz = v[0], v[1], v[2]
        rows = [
            float(bx[0]), float(by[0]), float(bz[0]),
            float(bx[1]), float(by[1]), float(bz[1]),
            float(bx[2]), float(by[2]), float(bz[2]),
        ]
        return struct.pack("<I9f", TYPE_BASIS, *rows)
    if tag == "xform3d":
        bx, by, bz, o = v[0], v[1], v[2], v[3]
        vals = [
            float(bx[0]), float(by[0]), float(bz[0]),
            float(bx[1]), float(by[1]), float(bz[1]),
            float(bx[2]), float(by[2]), float(bz[2]),
            float(o[0]), float(o[1]), float(o[2]),
        ]
        return struct.pack("<I12f", TYPE_TRANSFORM3D, *vals)
    if tag == "color":
        a = float(v[3]) if len(v) >= 4 else 1.0
        return struct.pack("<I4f", TYPE_COLOR, float(v[0]), float(v[1]), float(v[2]), a)
    if tag == "sn":
        return struct.pack("<I", TYPE_STRING_NAME) + _enc_str(str(v))
    if tag == "np":
        s = str(v)
        absolute = s.startswith("/")
        body_str = s[1:] if absolute else s
        if ":" in body_str:
            path_part, sub_part = body_str.split(":", 1)
            subnames = [p for p in sub_part.split(":") if p]
        else:
            path_part, subnames = body_str, []
        names = [p for p in path_part.split("/") if p]
        parts = [struct.pack("<IIII", TYPE_NODE_PATH, len(names) | 0x80000000, len(subnames), 1 if absolute else 0)]
        for part in names + subnames:
            parts.append(_enc_str(part))
        return b"".join(parts)
    if tag == "dict":
        parts = [struct.pack("<II", TYPE_DICTIONARY, len(v))]
        for k, val in v:
            parts.append(encode_godot_var(k))
            parts.append(encode_godot_var(val))
        return b"".join(parts)
    if tag == "bytes":
        raw = base64.b64decode(v) if isinstance(v, str) else bytes(v)
        return struct.pack("<II", TYPE_PACKED_BYTE_ARRAY, len(raw)) + raw + (b"\x00" * _pad4(len(raw)))
    if tag == "pi32":
        return struct.pack(f"<II{len(v)}i", TYPE_PACKED_INT32_ARRAY, len(v), *(int(x) for x in v))
    if tag == "pi64":
        return struct.pack(f"<II{len(v)}q", TYPE_PACKED_INT64_ARRAY, len(v), *(int(x) for x in v))
    if tag == "pf32":
        return struct.pack(f"<II{len(v)}f", TYPE_PACKED_FLOAT32_ARRAY, len(v), *(float(x) for x in v))
    if tag == "pf64":
        return struct.pack(f"<II{len(v)}d", TYPE_PACKED_FLOAT64_ARRAY, len(v), *(float(x) for x in v))
    if tag == "pstr":
        return b"".join([struct.pack("<II", TYPE_PACKED_STRING_ARRAY, len(v))] + [_enc_str(str(s)) for s in v])
    if tag == "pv2":
        flat = [float(c) for p in v for c in p]
        return struct.pack(f"<II{len(flat)}f", TYPE_PACKED_VECTOR2_ARRAY, len(v), *flat)
    if tag == "pv3":
        flat = [float(c) for p in v for c in p]
        return struct.pack(f"<II{len(flat)}f", TYPE_PACKED_VECTOR3_ARRAY, len(v), *flat)
    if tag == "pcol":
        flat = [float(c) for p in v for c in p]
        return struct.pack(f"<II{len(flat)}f", TYPE_PACKED_COLOR_ARRAY, len(v), *flat)
    if tag == "pv4":
        flat = [float(c) for p in v for c in p]
        return struct.pack(f"<II{len(flat)}f", TYPE_PACKED_VECTOR4_ARRAY, len(v), *flat)
    raise ValueError(f"Unknown Variant tag: {tag}")


def decode_godot_var(buf: bytes, ofs: int) -> tuple[Any, int]:
    """Decode one Godot 4.7.2 encode_var value from buf[ofs:], returning (value, next_ofs)."""
    if ofs + 4 > len(buf):
        raise ValueError("Truncated Variant header")
    header = struct.unpack_from("<I", buf, ofs)[0]
    ofs += 4
    vtype = header & 0xFF
    is64 = (header & HEADER_FLAG_64) != 0

    if vtype == TYPE_NIL:
        return None, ofs
    if vtype == TYPE_BOOL:
        val = struct.unpack_from("<I", buf, ofs)[0] != 0
        return val, ofs + 4
    if vtype == TYPE_INT:
        if is64:
            return struct.unpack_from("<q", buf, ofs)[0], ofs + 8
        return struct.unpack_from("<i", buf, ofs)[0], ofs + 4
    if vtype == TYPE_FLOAT:
        if is64:
            return struct.unpack_from("<d", buf, ofs)[0], ofs + 8
        return struct.unpack_from("<f", buf, ofs)[0], ofs + 4
    if vtype == TYPE_STRING:
        return _dec_str(buf, ofs)
    if vtype == TYPE_VECTOR2:
        fmt = "<dd" if is64 else "<ff"
        sz = 16 if is64 else 8
        x, y = struct.unpack_from(fmt, buf, ofs)
        return {"_t": "v2", "v": [x, y]}, ofs + sz
    if vtype == TYPE_VECTOR2I:
        x, y = struct.unpack_from("<ii", buf, ofs)
        return {"_t": "v2i", "v": [x, y]}, ofs + 8
    if vtype == TYPE_RECT2:
        fmt = "<4d" if is64 else "<4f"
        sz = 32 if is64 else 16
        return {"_t": "rect2", "v": list(struct.unpack_from(fmt, buf, ofs))}, ofs + sz
    if vtype == TYPE_RECT2I:
        return {"_t": "rect2i", "v": list(struct.unpack_from("<4i", buf, ofs))}, ofs + 16
    if vtype == TYPE_VECTOR3:
        fmt = "<3d" if is64 else "<3f"
        sz = 24 if is64 else 12
        return {"_t": "v3", "v": list(struct.unpack_from(fmt, buf, ofs))}, ofs + sz
    if vtype == TYPE_VECTOR3I:
        return {"_t": "v3i", "v": list(struct.unpack_from("<3i", buf, ofs))}, ofs + 12
    if vtype == TYPE_TRANSFORM2D:
        fmt = "<6d" if is64 else "<6f"
        sz = 48 if is64 else 24
        v = struct.unpack_from(fmt, buf, ofs)
        return {"_t": "xform2d", "v": [[v[0], v[1]], [v[2], v[3]], [v[4], v[5]]]}, ofs + sz
    if vtype == TYPE_VECTOR4:
        fmt = "<4d" if is64 else "<4f"
        sz = 32 if is64 else 16
        return {"_t": "v4", "v": list(struct.unpack_from(fmt, buf, ofs))}, ofs + sz
    if vtype == TYPE_VECTOR4I:
        return {"_t": "v4i", "v": list(struct.unpack_from("<4i", buf, ofs))}, ofs + 16
    if vtype == TYPE_PLANE:
        fmt = "<4d" if is64 else "<4f"
        sz = 32 if is64 else 16
        return {"_t": "plane", "v": list(struct.unpack_from(fmt, buf, ofs))}, ofs + sz
    if vtype == TYPE_QUATERNION:
        fmt = "<4d" if is64 else "<4f"
        sz = 32 if is64 else 16
        return {"_t": "quat", "v": list(struct.unpack_from(fmt, buf, ofs))}, ofs + sz
    if vtype == TYPE_AABB:
        fmt = "<6d" if is64 else "<6f"
        sz = 48 if is64 else 24
        v = struct.unpack_from(fmt, buf, ofs)
        return {"_t": "aabb", "v": [[v[0], v[1], v[2]], [v[3], v[4], v[5]]]}, ofs + sz
    if vtype == TYPE_BASIS:
        fmt = "<9d" if is64 else "<9f"
        sz = 72 if is64 else 36
        r = struct.unpack_from(fmt, buf, ofs)
        # Convert row-major to basis column vectors [x, y, z]
        return {"_t": "basis", "v": [[r[0], r[3], r[6]], [r[1], r[4], r[7]], [r[2], r[5], r[8]]]}, ofs + sz
    if vtype == TYPE_TRANSFORM3D:
        fmt = "<12d" if is64 else "<12f"
        sz = 96 if is64 else 48
        r = struct.unpack_from(fmt, buf, ofs)
        return {"_t": "xform3d", "v": [
            [r[0], r[3], r[6]],
            [r[1], r[4], r[7]],
            [r[2], r[5], r[8]],
            [r[9], r[10], r[11]],
        ]}, ofs + sz
    if vtype == TYPE_PROJECTION:
        fmt = "<16d" if is64 else "<16f"
        sz = 128 if is64 else 64
        r = struct.unpack_from(fmt, buf, ofs)
        return {"_t": "proj", "v": [list(r[0:4]), list(r[4:8]), list(r[8:12]), list(r[12:16])]}, ofs + sz
    if vtype == TYPE_COLOR:
        return {"_t": "color", "v": list(struct.unpack_from("<4f", buf, ofs))}, ofs + 16
    if vtype == TYPE_STRING_NAME:
        s, ofs = _dec_str(buf, ofs)
        return {"_t": "sn", "v": s}, ofs
    if vtype == TYPE_NODE_PATH:
        nc_raw, sc, flags = struct.unpack_from("<III", buf, ofs)
        ofs += 12
        nc = nc_raw & 0x7FFFFFFF
        if flags & 2:
            sc += 1
        names, subnames = [], []
        for _ in range(nc):
            s, ofs = _dec_str(buf, ofs)
            names.append(s)
        for _ in range(sc):
            s, ofs = _dec_str(buf, ofs)
            subnames.append(s)
        path = ("/" if (flags & 1) else "") + "/".join(names)
        if subnames:
            path += ":" + ":".join(subnames)
        return {"_t": "np", "v": path}, ofs
    if vtype == TYPE_DICTIONARY:
        key_kind = (header >> 16) & 0x03
        val_kind = (header >> 18) & 0x03
        ofs = _skip_container_type(buf, ofs, key_kind)
        ofs = _skip_container_type(buf, ofs, val_kind)
        count = struct.unpack_from("<I", buf, ofs)[0] & 0x7FFFFFFF
        ofs += 4
        pairs = []
        plain = True
        for _ in range(count):
            k, ofs = decode_godot_var(buf, ofs)
            v, ofs = decode_godot_var(buf, ofs)
            if not isinstance(k, str) or k == "_t":
                plain = False
            pairs.append([k, v])
        if plain:
            return {k: v for k, v in pairs}, ofs
        return {"_t": "dict", "v": pairs}, ofs
    if vtype == TYPE_ARRAY:
        elem_kind = (header >> 16) & 0x03
        ofs = _skip_container_type(buf, ofs, elem_kind)
        count = struct.unpack_from("<I", buf, ofs)[0] & 0x7FFFFFFF
        ofs += 4
        arr = []
        for _ in range(count):
            item, ofs = decode_godot_var(buf, ofs)
            arr.append(item)
        return arr, ofs
    if vtype == TYPE_PACKED_BYTE_ARRAY:
        count = struct.unpack_from("<I", buf, ofs)[0]
        ofs += 4
        raw = buf[ofs : ofs + count]
        return {"_t": "bytes", "v": base64.b64encode(raw).decode("ascii")}, ofs + count + _pad4(count)
    if vtype == TYPE_PACKED_INT32_ARRAY:
        count = struct.unpack_from("<I", buf, ofs)[0]
        ofs += 4
        vals = list(struct.unpack_from(f"<{count}i", buf, ofs)) if count else []
        return {"_t": "pi32", "v": vals}, ofs + count * 4
    if vtype == TYPE_PACKED_INT64_ARRAY:
        count = struct.unpack_from("<I", buf, ofs)[0]
        ofs += 4
        vals = list(struct.unpack_from(f"<{count}q", buf, ofs)) if count else []
        return {"_t": "pi64", "v": vals}, ofs + count * 8
    if vtype == TYPE_PACKED_FLOAT32_ARRAY:
        count = struct.unpack_from("<I", buf, ofs)[0]
        ofs += 4
        vals = list(struct.unpack_from(f"<{count}f", buf, ofs)) if count else []
        return {"_t": "pf32", "v": vals}, ofs + count * 4
    if vtype == TYPE_PACKED_FLOAT64_ARRAY:
        count = struct.unpack_from("<I", buf, ofs)[0]
        ofs += 4
        vals = list(struct.unpack_from(f"<{count}d", buf, ofs)) if count else []
        return {"_t": "pf64", "v": vals}, ofs + count * 8
    if vtype == TYPE_PACKED_STRING_ARRAY:
        count = struct.unpack_from("<I", buf, ofs)[0]
        ofs += 4
        vals = []
        for _ in range(count):
            s, ofs = _dec_str(buf, ofs)
            vals.append(s)
        return {"_t": "pstr", "v": vals}, ofs
    if vtype == TYPE_PACKED_VECTOR2_ARRAY:
        count = struct.unpack_from("<I", buf, ofs)[0]
        ofs += 4
        fmt = f"<{count * 2}{'d' if is64 else 'f'}"
        flat = struct.unpack_from(fmt, buf, ofs) if count else ()
        return {"_t": "pv2", "v": [[flat[i], flat[i + 1]] for i in range(0, len(flat), 2)]}, ofs + count * (16 if is64 else 8)
    if vtype == TYPE_PACKED_VECTOR3_ARRAY:
        count = struct.unpack_from("<I", buf, ofs)[0]
        ofs += 4
        fmt = f"<{count * 3}{'d' if is64 else 'f'}"
        flat = struct.unpack_from(fmt, buf, ofs) if count else ()
        return {"_t": "pv3", "v": [[flat[i], flat[i + 1], flat[i + 2]] for i in range(0, len(flat), 3)]}, ofs + count * (24 if is64 else 12)
    if vtype == TYPE_PACKED_COLOR_ARRAY:
        count = struct.unpack_from("<I", buf, ofs)[0]
        ofs += 4
        flat = struct.unpack_from(f"<{count * 4}f", buf, ofs) if count else ()
        return {"_t": "pcol", "v": [[flat[i], flat[i + 1], flat[i + 2], flat[i + 3]] for i in range(0, len(flat), 4)]}, ofs + count * 16
    if vtype == TYPE_PACKED_VECTOR4_ARRAY:
        count = struct.unpack_from("<I", buf, ofs)[0]
        ofs += 4
        fmt = f"<{count * 4}{'d' if is64 else 'f'}"
        flat = struct.unpack_from(fmt, buf, ofs) if count else ()
        return {"_t": "pv4", "v": [[flat[i], flat[i + 1], flat[i + 2], flat[i + 3]] for i in range(0, len(flat), 4)]}, ofs + count * (32 if is64 else 16)
    raise ValueError(f"Unsupported Variant type {vtype} (header=0x{header:08x})")


def encode_full_bin_rpc(node: str, method: str, args: list[Any], ch: int = 0, mode: int = TRANSFER_RELIABLE) -> bytes:
    node_b = node.encode("utf-8")
    method_b = method.encode("utf-8")
    parts = [
        struct.pack("<BBBH", FULL_BIN_RPC, mode & 0x03, ch & 0xFF, len(node_b)),
        node_b,
        struct.pack("<B", len(method_b)),
        method_b,
        struct.pack("<B", len(args)),
    ]
    for arg in args:
        parts.append(encode_godot_var(arg))
    return b"".join(parts)


def decode_full_bin(data: bytes) -> dict[str, Any]:
    if not data:
        raise ValueError("Empty binary frame")
    tag = data[0]
    if tag == FULL_BIN_RPC:
        if len(data) < 7:
            raise ValueError("Binary RPC frame too short")
        mode = data[1] & 0x03
        ch = data[2]
        node_len = struct.unpack_from("<H", data, 3)[0]
        ofs = 5
        node = data[ofs : ofs + node_len].decode("utf-8")
        ofs += node_len
        method_len = data[ofs]
        ofs += 1
        method = data[ofs : ofs + method_len].decode("utf-8")
        ofs += method_len
        argc = data[ofs]
        ofs += 1
        args = []
        for _ in range(argc):
            val, ofs = decode_godot_var(data, ofs)
            args.append(val)
        return {"t": "rpc", "node": node, "method": method, "args": args, "ch": ch, "rel": mode == TRANSFER_RELIABLE, "mode": mode}
    if tag == FULL_BIN_RAW:
        return {"t": "raw", "mode": data[1] & 0x03, "ch": data[2], "data": data[3:]}
    raise ValueError(f"Unknown binary tag 0x{tag:02x}")


# ---------------------------------------------------------------------------
# Transports: stdlib WebSocket (RFC 6455) and length-prefixed raw TCP
# ---------------------------------------------------------------------------

class BaseTransport:
    def send_text(self, text: str) -> None:
        raise NotImplementedError

    def send_binary(self, payload: bytes) -> None:
        raise NotImplementedError

    def recv(self, timeout: float = 0.05) -> tuple[bool, bytes] | None:
        """Returns (is_text, payload) or None on timeout. Raises EOFError on close."""
        raise NotImplementedError

    def close(self) -> None:
        raise NotImplementedError


class TcpLengthTransport(BaseTransport):
    """Raw TCP with 4-byte little-endian length prefix (game/open_protocol_wire.gd)."""

    def __init__(self, host: str, port: int, timeout: float = 5.0) -> None:
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        self.sock.setblocking(False)
        self._buf = bytearray()

    def send_text(self, text: str) -> None:
        raw = text.encode("utf-8")
        self._send_all(struct.pack("<I", len(raw)) + raw)

    def send_binary(self, payload: bytes) -> None:
        self._send_all(struct.pack("<I", len(payload)) + payload)

    def _send_all(self, data: bytes) -> None:
        view = memoryview(data)
        sent = 0
        while sent < len(data):
            _, w, _ = select.select([], [self.sock], [], 5.0)
            if not w:
                raise TimeoutError("TCP write timeout")
            n = self.sock.send(view[sent:])
            if n <= 0:
                raise EOFError("TCP closed during write")
            sent += n

    def recv(self, timeout: float = 0.05) -> tuple[bool, bytes] | None:
        frame = self._pop_frame()
        if frame is not None:
            return frame
        deadline = time.monotonic() + timeout
        while True:
            rem = max(0.0, deadline - time.monotonic())
            r, _, _ = select.select([self.sock], [], [], rem)
            if not r:
                return None
            chunk = self.sock.recv(65536)
            if not chunk:
                raise EOFError("TCP peer closed connection")
            self._buf.extend(chunk)
            frame = self._pop_frame()
            if frame is not None:
                return frame

    def _pop_frame(self) -> tuple[bool, bytes] | None:
        if len(self._buf) < 4:
            return None
        length = struct.unpack_from("<I", self._buf, 0)[0]
        if len(self._buf) < 4 + length:
            return None
        payload = bytes(self._buf[4 : 4 + length])
        del self._buf[: 4 + length]
        is_text = len(payload) > 0 and payload[0] >= 0x09
        return is_text, payload

    def close(self) -> None:
        try:
            self.sock.close()
        except OSError:
            pass


class WebSocketTransport(BaseTransport):
    """Minimal RFC 6455 client over stdlib socket."""

    def __init__(self, host: str, port: int, path: str = "/", timeout: float = 5.0) -> None:
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        key = base64.b64encode(os.urandom(16)).decode("ascii")
        req = (
            f"GET {path} HTTP/1.1\r\n"
            f"Host: {host}:{port}\r\n"
            f"Upgrade: websocket\r\n"
            f"Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            f"Sec-WebSocket-Version: 13\r\n\r\n"
        ).encode("ascii")
        self.sock.sendall(req)
        resp = bytearray()
        while b"\r\n\r\n" not in resp:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise EOFError("WebSocket handshake closed early")
            resp.extend(chunk)
        header_end = resp.index(b"\r\n\r\n") + 4
        header_text = resp[:header_end].decode("latin1")
        if "101" not in header_text.splitlines()[0]:
            raise ConnectionError(f"WebSocket upgrade rejected: {header_text.splitlines()[0]}")
        expected = base64.b64encode(
            hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")).digest()
        ).decode("ascii")
        if expected not in header_text:
            raise ConnectionError("Invalid Sec-WebSocket-Accept")
        self._buf = bytearray(resp[header_end:])
        self.sock.setblocking(False)

    def _send_frame(self, opcode: int, payload: bytes) -> None:
        mask = os.urandom(4)
        length = len(payload)
        header = bytearray([0x80 | opcode])
        if length < 126:
            header.append(0x80 | length)
        elif length < 65536:
            header.append(0x80 | 126)
            header.extend(struct.pack("!H", length))
        else:
            header.append(0x80 | 127)
            header.extend(struct.pack("!Q", length))
        header.extend(mask)
        masked = bytes(b ^ mask[i & 3] for i, b in enumerate(payload))
        data = bytes(header) + masked
        view = memoryview(data)
        sent = 0
        while sent < len(data):
            _, w, _ = select.select([], [self.sock], [], 5.0)
            if not w:
                raise TimeoutError("WS write timeout")
            n = self.sock.send(view[sent:])
            if n <= 0:
                raise EOFError("WS closed during write")
            sent += n

    def send_text(self, text: str) -> None:
        self._send_frame(0x1, text.encode("utf-8"))

    def send_binary(self, payload: bytes) -> None:
        self._send_frame(0x2, payload)

    def recv(self, timeout: float = 0.05) -> tuple[bool, bytes] | None:
        deadline = time.monotonic() + timeout
        while True:
            frame = self._pop_frame()
            if frame is not None:
                opcode, payload = frame
                if opcode == 0x8:
                    raise EOFError("WebSocket peer sent close frame")
                if opcode == 0x9:
                    self._send_frame(0xA, payload)
                    continue
                if opcode == 0xA:
                    continue
                if opcode == 0x1:
                    return True, payload
                if opcode == 0x2:
                    return False, payload
                continue
            rem = max(0.0, deadline - time.monotonic())
            r, _, _ = select.select([self.sock], [], [], rem)
            if not r:
                return None
            chunk = self.sock.recv(65536)
            if not chunk:
                raise EOFError("WebSocket closed")
            self._buf.extend(chunk)

    def _pop_frame(self) -> tuple[int, bytes] | None:
        if len(self._buf) < 2:
            return None
        b0, b1 = self._buf[0], self._buf[1]
        opcode = b0 & 0x0F
        masked = (b1 & 0x80) != 0
        length = b1 & 0x7F
        ofs = 2
        if length == 126:
            if len(self._buf) < ofs + 2:
                return None
            length = struct.unpack_from("!H", self._buf, ofs)[0]
            ofs += 2
        elif length == 127:
            if len(self._buf) < ofs + 8:
                return None
            length = struct.unpack_from("!Q", self._buf, ofs)[0]
            ofs += 8
        mask = b""
        if masked:
            if len(self._buf) < ofs + 4:
                return None
            mask = bytes(self._buf[ofs : ofs + 4])
            ofs += 4
        if len(self._buf) < ofs + length:
            return None
        payload = bytes(self._buf[ofs : ofs + length])
        del self._buf[: ofs + length]
        if masked:
            payload = bytes(b ^ mask[i & 3] for i, b in enumerate(payload))
        return opcode, payload

    def close(self) -> None:
        try:
            self._send_frame(0x8, b"")
        except OSError:
            pass
        try:
            self.sock.close()
        except OSError:
            pass


# ---------------------------------------------------------------------------
# Full-tier Client
# ---------------------------------------------------------------------------

@dataclass
class RecordedFrame:
    direction: str
    encoding: str
    decoded: dict[str, Any]
    raw_hex: str | None = None


class FullTierClient:
    def __init__(self, transport: str, host: str, port: int, enc: str = "json", join_code: str = "") -> None:
        self.transport_name = transport
        self.host = host
        self.port = port
        self.enc = enc
        self.join_code = join_code
        self.transport: BaseTransport | None = None
        self.peer_id: int = 0
        self.game_protocol: int = 0
        self.maps: list[dict[str, Any]] = []
        self.roster: dict[int, dict[str, Any]] = {}
        self.run_active: bool = False
        self.run_map_id: str = ""
        self.run_confirmed: bool = False
        self.run_id: int = 0
        self.starter_accepted: bool = False
        self.transcript: list[RecordedFrame] = []
        self.rpc_counts: dict[str, int] = {}
        self.errors: list[str] = []
        self.reject_reason: str = ""
        self.enemy_batches: int = 0
        self.enemies_seen: set[int] = set()
        self.weather_phases: list[tuple[int, int, float]] = []
        self.player_updates: dict[str, int] = {}

    def connect(self, timeout: float = 5.0) -> dict[str, Any]:
        if self.transport_name == "ws":
            self.transport = WebSocketTransport(self.host, self.port, timeout=timeout)
        elif self.transport_name == "tcp":
            self.transport = TcpLengthTransport(self.host, self.port, timeout=timeout)
        else:
            raise ValueError(f"Unknown transport: {self.transport_name}")

        hello: dict[str, Any] = {"t": "hello", "v": OPEN_PROTOCOL_VERSION, "tier": "full", "enc": self.enc}
        if self.join_code:
            hello["code"] = self.join_code
        self.send_control(hello)
        welcome = self.wait_for(lambda m: m.get("t") in ("welcome", "error"), timeout=timeout)
        if welcome is None:
            raise TimeoutError("Timed out waiting for welcome")
        if welcome.get("t") == "error":
            raise RuntimeError(f"Server rejected hello: {welcome.get('msg')}")
        self.peer_id = int(welcome["you"])
        self.game_protocol = int(welcome["game_protocol"])
        self.maps = list(welcome.get("maps", []))
        return welcome

    def send_control(self, msg: dict[str, Any]) -> None:
        assert self.transport is not None
        text = json.dumps(msg, separators=(",", ":"))
        self.transport.send_text(text)
        self.transcript.append(RecordedFrame("c->s", "json", msg))

    def send_rpc(self, node: str, method: str, args: list[Any], ch: int = 0, mode: int = TRANSFER_RELIABLE) -> None:
        assert self.transport is not None
        if self.enc == "bin":
            raw = encode_full_bin_rpc(node, method, args, ch=ch, mode=mode)
            self.transport.send_binary(raw)
            self.transcript.append(
                RecordedFrame(
                    "c->s",
                    "bin",
                    {"t": "rpc", "node": node, "method": method, "args": args, "ch": ch, "rel": mode == TRANSFER_RELIABLE},
                    raw.hex(),
                )
            )
        else:
            msg = {"t": "rpc", "node": node, "method": method, "args": args, "ch": ch, "rel": mode == TRANSFER_RELIABLE}
            text = json.dumps(msg, separators=(",", ":"))
            self.transport.send_text(text)
            self.transcript.append(RecordedFrame("c->s", "json", msg))

    def send_game_hello(self, name: str, color: int = 0, skin: int = 0, colors: list[int] | None = None,
                        protocol: int | None = None) -> None:
        payload = json.dumps({"name": name, "color": color, "skin": skin, "colors": colors or []}, separators=(",", ":"))
        proto = self.game_protocol if protocol is None else protocol
        self.send_rpc("Net", "_hello", [payload, proto])

    def send_ready(self, ready: bool) -> None:
        self.send_rpc("Net", "_request_ready", [ready])

    def send_vote(self, map_id: str) -> None:
        self.send_rpc("Net", "_request_map_vote", [map_id])

    def send_chat(self, text: str) -> None:
        self.send_rpc("Net", "_request_chat", [text])

    def send_report_in_run(self, in_run: bool) -> None:
        self.send_rpc("Net", "_report_in_run", [in_run])

    def send_exposure(self, sheltered: bool, in_puddle: bool) -> None:
        self.send_rpc(f"Main/Players/P_{self.peer_id}", "_report_exposure", [sheltered, in_puddle])

    def send_transform(self, pos: tuple[float, float, float], yaw: float, pitch: float,
                       vel: tuple[float, float, float]) -> None:
        self.send_rpc(
            f"Main/Players/P_{self.peer_id}",
            "_push_transform",
            [v_vec3(*pos), float(yaw), float(pitch), v_vec3(*vel)],
            ch=0,
            mode=TRANSFER_UNRELIABLE_ORDERED,
        )

    def send_starter(self, index: int = 0) -> None:
        if self.run_id > 0:
            self.send_rpc("Main/RunLoot", "_request_starter", [self.run_id, index])

    def send_calm_ready(self) -> None:
        self.send_rpc("GameManager", "_request_ready", [])

    def poll_one(self, timeout: float = 0.05) -> dict[str, Any] | None:
        assert self.transport is not None
        pkt = self.transport.recv(timeout=timeout)
        if pkt is None:
            return None
        is_text, data = pkt
        if is_text:
            msg = json.loads(data.decode("utf-8"))
            self.transcript.append(RecordedFrame("s->c", "json", msg))
        else:
            msg = decode_full_bin(data)
            self.transcript.append(RecordedFrame("s->c", "bin", msg, data.hex()))
        self._dispatch(msg)
        return msg

    def wait_for(self, predicate, timeout: float = 5.0) -> dict[str, Any] | None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            rem = min(0.05, max(0.0, deadline - time.monotonic()))
            msg = self.poll_one(timeout=rem)
            if msg is not None and predicate(msg):
                return msg
        return None

    def _dispatch(self, msg: dict[str, Any]) -> None:
        t = msg.get("t")
        if t == "error":
            self.errors.append(str(msg.get("msg", "")))
            return
        if t != "rpc":
            return
        node = str(msg.get("node", ""))
        method = str(msg.get("method", ""))
        args = msg.get("args", [])
        key = f"{node}.{method}"
        self.rpc_counts[key] = self.rpc_counts.get(key, 0) + 1

        if node == "Net":
            if method == "_rtt_ping" and len(args) >= 1:
                self.send_rpc("Net", "_rtt_pong", [int(args[0])], ch=0, mode=TRANSFER_UNRELIABLE)
            elif method == "_push_roster" and len(args) >= 1:
                self.roster = decode_roster_arg(args[0])
            elif method == "_start_run" and len(args) >= 1:
                self.run_active = True
                self.run_map_id = str(args[0])
            elif method == "_confirm_run_ready":
                self.run_confirmed = True
            elif method == "_reject" and len(args) >= 1:
                self.reject_reason = str(args[0])
        elif node == "WeatherManager" and method == "_receive_phase" and len(args) >= 3:
            self.weather_phases.append((int(args[0]), int(args[1]), float(args[2])))
        elif node == "Main/RunLoot":
            if method == "_snapshot" and len(args) >= 1:
                self.run_id = int(args[0])
            elif method == "_starter_accepted":
                self.starter_accepted = True
        elif node == "Main/Enemies":
            if method == "_spawn_enemy" and len(args) >= 1:
                self.enemies_seen.add(int(args[0]))
            elif method == "_sync_enemies" and len(args) >= 3:
                self.enemy_batches += 1
                ids = args[0]["v"] if isinstance(args[0], dict) else args[0]
                for eid in ids:
                    self.enemies_seen.add(int(eid))
        elif node.startswith("Main/Players/P_"):
            if method in ("_apply_vitals", "_relay_transform"):
                self.player_updates[key] = self.player_updates.get(key, 0) + 1

    def leave_and_close(self) -> None:
        if self.transport is not None:
            try:
                self.send_control({"t": "leave"})
                time.sleep(0.05)
            except OSError:
                pass
            self.transport.close()
            self.transport = None


# ---------------------------------------------------------------------------
# Conformance suite
# ---------------------------------------------------------------------------

def run_conformance(args: argparse.Namespace) -> int:
    results: list[tuple[str, bool, str]] = []

    def record(name: str, ok: bool, detail: str = "") -> None:
        results.append((name, ok, detail))
        status = "PASS" if ok else "FAIL"
        print(f"[{status}] {name}" + (f" — {detail}" if detail else ""))

    client = FullTierClient(args.transport, args.host, args.port, enc=args.enc, join_code=args.code)
    try:
        # 1. Open Protocol hello -> welcome
        welcome = client.connect(timeout=6.0)
        ok_w = (
            welcome.get("t") == "welcome"
            and welcome.get("tier") == "full"
            and welcome.get("enc") == args.enc
            and client.peer_id >= 2
            and client.game_protocol > 0
        )
        record("open_protocol_welcome", ok_w, f"you={client.peer_id} proto={client.game_protocol} enc={welcome.get('enc')}")

        # 2. Control ping -> pong
        client.send_control({"t": "ping", "ms": 12345})
        pong = client.wait_for(lambda m: m.get("t") == "pong", timeout=3.0)
        record("control_ping_pong", pong is not None and pong.get("ms") == 12345, f"pong={pong}")

        # 3. Game handshake: Net._hello -> Net._push_roster
        client.send_game_hello(args.name, color=args.color, skin=args.skin)
        roster_msg = client.wait_for(
            lambda m: m.get("t") == "rpc" and m.get("node") == "Net" and m.get("method") == "_push_roster"
            and client.peer_id in client.roster,
            timeout=5.0,
        )
        record(
            "game_hello_roster",
            roster_msg is not None and client.peer_id in client.roster,
            f"roster_peers={sorted(client.roster.keys())}",
        )

        # Optional: wait until expected peer count is in lobby (e.g. alongside a real Godot client)
        if args.expect_peers > 1:
            deadline = time.monotonic() + args.peer_wait
            while len(client.roster) < args.expect_peers and time.monotonic() < deadline:
                client.poll_one(timeout=0.05)
            record(
                "lobby_coexists_with_peers",
                len(client.roster) >= args.expect_peers,
                f"seen={len(client.roster)} expected>={args.expect_peers} roster={client.roster}",
            )

        # 4. Lobby vote + chat + ready
        if args.vote:
            client.send_vote(args.vote)
        if args.chat:
            client.send_chat(args.chat)
        client.send_ready(True)
        got_start = client.wait_for(lambda _: client.run_active, timeout=args.start_timeout)
        record("lobby_ready_and_start_run", got_start is not None or client.run_active, f"map={client.run_map_id}")

        # 5. Report in run -> _confirm_run_ready + run state snapshots
        client.send_report_in_run(True)
        got_confirm = client.wait_for(lambda _: client.run_confirmed, timeout=15.0)
        record("run_report_and_confirm", got_confirm is not None or client.run_confirmed, f"run_id={client.run_id}")

        # Wait briefly for RunLoot._snapshot so we know run_id
        if client.run_id == 0:
            client.wait_for(lambda _: client.run_id > 0, timeout=5.0)
        record("run_loot_snapshot", client.run_id > 0, f"run_id={client.run_id}")

        # 6. Pick starter kit & skip Calm wait so enemies spawn quickly
        if client.run_id > 0:
            client.send_starter(0)
            client.wait_for(lambda _: client.starter_accepted, timeout=3.0)
            record("starter_kit_accepted", client.starter_accepted)
        client.send_exposure(False, False)
        if args.skip_calm:
            client.send_calm_ready()

        # 7. Active gameplay: walk a path at 20 Hz and decode server stream
        walk_start = time.monotonic()
        next_step = walk_start
        step = 0
        sent_transforms = 0
        while time.monotonic() - walk_start < args.walk_seconds:
            now = time.monotonic()
            if now >= next_step:
                next_step += 0.05
                angle = step * 0.15
                pos = (math.cos(angle) * 3.0, 0.2, math.sin(angle) * 3.0)
                vel = (-math.sin(angle) * 2.0, 0.0, math.cos(angle) * 2.0)
                yaw = angle
                client.send_transform(pos, yaw, 0.0, vel)
                sent_transforms += 1
                step += 1
            try:
                client.poll_one(timeout=0.02)
            except EOFError:
                break

        record("sent_player_transforms", sent_transforms >= 20, f"sent={sent_transforms}")
        record("decoded_weather_phases", len(client.weather_phases) >= 1, f"phases={client.weather_phases}")
        own_vitals_key = f"Main/Players/P_{client.peer_id}._apply_vitals"
        record(
            "decoded_player_vitals",
            client.player_updates.get(own_vitals_key, 0) >= 1,
            f"updates={client.player_updates}",
        )
        if args.require_enemies:
            record(
                "decoded_enemy_stream",
                client.enemy_batches >= 1 and len(client.enemies_seen) >= 1,
                f"batches={client.enemy_batches} unique_enemies={len(client.enemies_seen)}",
            )
        record("no_protocol_errors", len(client.errors) == 0, f"errors={client.errors}")

        if args.dump_transcript:
            dump = [
                {"dir": f.direction, "enc": f.encoding, "msg": f.decoded, "hex": f.raw_hex}
                for f in client.transcript
            ]
            with open(args.dump_transcript, "w", encoding="utf-8") as fh:
                json.dump(dump, fh, indent=2)
            print(f"[INFO] Wrote {len(dump)} frames to {args.dump_transcript}")
    except Exception as exc:
        record("unexpected_exception", False, f"{type(exc).__name__}: {exc}")
    finally:
        client.leave_and_close()

    passed = sum(1 for _, ok, _ in results if ok)
    total = len(results)
    print(f"SUMMARY ({args.transport}/{args.enc}): {passed}/{total} checks passed; distinct RPCs decoded: {len(client.rpc_counts)}")
    return 0 if passed == total else 1


def run_reject_test(args: argparse.Namespace) -> int:
    client = FullTierClient(args.transport, args.host, args.port, enc=args.enc, join_code=args.code)
    try:
        client.connect(timeout=5.0)
        client.send_game_hello("OLD_CLIENT", protocol=client.game_protocol + 99)
        client.wait_for(lambda _: bool(client.reject_reason), timeout=4.0)
        ok = "UPDATE REQUIRED" in client.reject_reason
        print(f"[{'PASS' if ok else 'FAIL'}] protocol_mismatch_reject — reason={client.reject_reason!r}")
        return 0 if ok else 1
    finally:
        client.leave_and_close()


def run_play(args: argparse.Namespace) -> int:
    client = FullTierClient(args.transport, args.host, args.port, enc=args.enc, join_code=args.code)
    try:
        welcome = client.connect(timeout=6.0)
        print(f"Connected as peer {client.peer_id} (protocol v{client.game_protocol}, {args.transport}/{args.enc})")
        client.send_game_hello(args.name, color=args.color, skin=args.skin)
        client.wait_for(lambda _: client.peer_id in client.roster, timeout=5.0)
        if args.vote:
            client.send_vote(args.vote)
        client.send_ready(True)
        reported_in_run = False
        step = 0
        next_step = time.monotonic()
        while True:
            if client.run_active and not reported_in_run:
                print(f"Run starting on {client.run_map_id}; reporting in_run=true")
                client.send_report_in_run(True)
                reported_in_run = True
            if client.run_confirmed and time.monotonic() >= next_step:
                next_step = time.monotonic() + 0.05
                angle = step * 0.1
                client.send_transform((math.cos(angle) * 2.0, 0.2, math.sin(angle) * 2.0), angle, 0.0, (0.0, 0.0, 0.0))
                step += 1
            msg = client.poll_one(timeout=0.02)
            if msg and msg.get("t") == "rpc" and msg.get("method") not in ("_sync_enemies", "_apply_vitals", "_relay_transform", "_rtt_ping"):
                print(f"<- {msg.get('node')}.{msg.get('method')}({msg.get('args')})")
    except KeyboardInterrupt:
        return 0
    finally:
        client.leave_and_close()


def main() -> int:
    parser = argparse.ArgumentParser(description="Fallout Forecast Open Protocol Full-tier client & conformance checker")
    parser.add_argument("--transport", choices=["ws", "tcp"], default="ws")
    parser.add_argument("--enc", choices=["json", "bin"], default="json")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=0, help="Default: 7780 for ws, 7781 for tcp")
    parser.add_argument("--code", default="", help="Optional server join code")
    parser.add_argument("--name", default="FULL_TEST")
    parser.add_argument("--color", type=int, default=1)
    parser.add_argument("--skin", type=int, default=0)
    parser.add_argument("--vote", default="pinecrest")
    parser.add_argument("--chat", default="full tier online")
    parser.add_argument("--mode", choices=["check", "reject", "play"], default="check")
    parser.add_argument("--expect-peers", type=int, default=1)
    parser.add_argument("--peer-wait", type=float, default=10.0)
    parser.add_argument("--start-timeout", type=float, default=15.0)
    parser.add_argument("--walk-seconds", type=float, default=16.0)
    parser.add_argument("--skip-calm", action="store_true", default=True)
    parser.add_argument("--no-skip-calm", dest="skip_calm", action="store_false")
    parser.add_argument("--require-enemies", action="store_true", default=False)
    parser.add_argument("--dump-transcript", default="")
    args = parser.parse_args()
    if args.port == 0:
        args.port = 7780 if args.transport == "ws" else 7781
    if args.mode == "reject":
        return run_reject_test(args)
    if args.mode == "play":
        return run_play(args)
    return run_conformance(args)


if __name__ == "__main__":
    sys.exit(main())
