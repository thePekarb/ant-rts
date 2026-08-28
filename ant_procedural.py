# -*- coding: utf-8 -*-
"""
=========================================================================
 ПРОЦЕДУРНЫЙ ГЕНЕРАТОР МУРАВЬЯ (game-ready, low-poly) ДЛЯ BLENDER 3.6-5.x
=========================================================================
"""

import bpy
import bmesh
import math
import random
import os
import numpy as np
from math import sin, cos, pi, radians, fmod
from mathutils import Vector, Matrix, Quaternion

# =========================================================================
#  КОНФИГУРАЦИЯ
# =========================================================================

CFG = {
    "name": "Ant",
    "seed": 7,

    # ---- бюджет геометрии -------------------------------------------------
    "tri_budget": (6000, 8000),   # жёсткие границы (треугольники)
    "tri_target": 7000,           # к чему стремимся внутри границ
    "autotune": True,             # подбор плотности сетки под бюджет
    "res": 1.0,                   # стартовая/фиксированная плотность

    # ---- размер -----------------------------------------------------------
    "target_length": 1.0,

    # ---- детали -----------------------------------------------------------
    "hairs": True,                # щетинки-спайки (по 3 трис)
    "hair_count": 46,
    "asymmetry": 0.012,           # доля случайного разброса точек лап
    "sharp_angle": 38.0,          # угол острых рёбер, градусы
    "triangulate": False,         # оставляем квады, движок сам триангулирует

    # ---- анимация ---------------------------------------------------------
    "make_rig": True,
    "make_anim": True,
    "idle_frames": 80,
    "walk_frames": 16,            # ~0.53 c при 30 FPS
    "run_frames": 10,             # ~0.33 c при 30 FPS
    "attack_frames": 36,
    "anim_step": 2,               # шаг простановки ключей
    "walk_in_place": True,        # True: ходьба/бег на месте

    "clear_previous": True,
}

Z = Vector((0.0, 0.0, 1.0))

MAT_CHITIN = 0
MAT_EYE = 1

# =========================================================================
#  АНАТОМИЯ В МИЛЛИМЕТРАХ
# =========================================================================

HEAD_PROFILE = [
    (2.30, 0.30, 0.32, 1.90),
    (2.56, 0.62, 0.60, 1.90),
    (2.86, 0.80, 0.74, 1.92),
    (3.24, 0.86, 0.79, 1.93),
    (3.60, 0.83, 0.76, 1.92),
    (3.95, 0.71, 0.66, 1.86),
    (4.20, 0.53, 0.50, 1.78),
    (4.40, 0.34, 0.34, 1.68),
]
HEAD_TIP = Vector((4.52, 0.0, 1.62))
HEAD_BACK = Vector((2.18, 0.0, 1.89))

THORAX_PROFILE = [
    (0.50, 0.26, 0.28, 1.62),
    (0.72, 0.44, 0.47, 1.66),
    (0.96, 0.53, 0.59, 1.72),
    (1.24, 0.50, 0.56, 1.76),
    (1.44, 0.46, 0.50, 1.74),
    (1.70, 0.55, 0.63, 1.80),
    (2.00, 0.58, 0.61, 1.78),
    (2.20, 0.48, 0.48, 1.80),
    (2.33, 0.31, 0.30, 1.86),
]
THORAX_BACK = Vector((0.40, 0.0, 1.60))
THORAX_FRONT = Vector((2.42, 0.0, 1.88))

PETIOLE_PROFILE = [
    (0.55, 0.20, 0.22, 1.62),
    (0.44, 0.27, 0.35, 1.66),
    (0.30, 0.23, 0.30, 1.71),
    (0.15, 0.24, 0.26, 1.81),
]

GASTER_PROFILE = [
    (0.18, 0.30, 0.32, 1.88),
    (-0.10, 0.63, 0.67, 1.92),
    (-0.46, 0.86, 0.92, 1.95),
    (-0.86, 0.98, 1.05, 1.97),
    (-1.30, 1.00, 1.06, 1.97),
    (-1.75, 0.94, 0.99, 1.95),
    (-2.15, 0.80, 0.84, 1.92),
    (-2.50, 0.60, 0.62, 1.88),
    (-2.80, 0.38, 0.40, 1.84),
]
GASTER_TIP = Vector((-3.05, 0.0, 1.80))
GASTER_SEAMS = {2: 0.955, 4: 0.962, 6: 0.955}

LEGS = [
    dict(id="1",
         base=Vector((2.05, 0.40, 1.40)),
         coxa=Vector((2.35, 0.80, 1.14)),
         knee=Vector((2.95, 1.50, 2.75)),
         ankle=Vector((3.55, 1.95, 0.45)),
         foot=Vector((4.10, 2.25, 0.02))),
    dict(id="2",
         base=Vector((1.45, 0.45, 1.38)),
         coxa=Vector((1.45, 0.90, 1.10)),
         knee=Vector((1.55, 1.85, 2.85)),
         ankle=Vector((1.65, 2.55, 0.45)),
         foot=Vector((1.55, 3.00, 0.02))),
    dict(id="3",
         base=Vector((0.85, 0.42, 1.38)),
         coxa=Vector((0.70, 0.85, 1.10)),
         knee=Vector((0.15, 1.60, 2.95)),
         ankle=Vector((-0.95, 2.20, 0.50)),
         foot=Vector((-1.75, 2.55, 0.02))),
]

ANT_SCAPE = [Vector((4.05, 0.34, 2.18)), Vector((4.70, 0.60, 2.62)),
             Vector((5.35, 0.86, 2.88))]
ANT_FUNIC = [Vector((5.35, 0.86, 2.88)), Vector((6.10, 1.15, 2.80)),
             Vector((6.75, 1.38, 2.62)), Vector((7.25, 1.55, 2.40))]

MANDIBLE = [Vector((4.34, 0.38, 1.58)), Vector((4.86, 0.46, 1.52)),
            Vector((5.24, 0.29, 1.48)), Vector((5.46, 0.09, 1.46))]

BODY_GROUPS = {"head", "thorax", "petiole", "gaster"}

# =========================================================================
#  МЕЛКАЯ МАТЕМАТИКА
# =========================================================================

def smoothstep(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)

def frame_matrix(origin, direction):
    d = direction.copy()
    if d.length < 1e-9:
        d = Vector((0.0, 1.0, 0.0))
    q = d.normalized().to_track_quat('Y', 'Z')
    return Matrix.Translation(origin) @ q.to_matrix().to_4x4()

def tangents(points):
    n = len(points)
    out = []
    for i in range(n):
        if i == 0:
            t = points[1] - points[0]
        elif i == n - 1:
            t = points[-1] - points[-2]
        else:
            t = points[i + 1] - points[i - 1]
        out.append(t.normalized())
    return out

def resample(points, count):
    if count <= 2 or len(points) < 2:
        return list(points)
    segs = [(points[i], points[i + 1]) for i in range(len(points) - 1)]
    lens = [(b - a).length for a, b in segs]
    total = sum(lens)
    out = []
    for k in range(count):
        target = total * k / (count - 1)
        acc = 0.0
        for (a, b), L in zip(segs, lens):
            if acc + L >= target - 1e-12 or (a, b) == segs[-1]:
                t = 0.0 if L < 1e-12 else (target - acc) / L
                out.append(a.lerp(b, min(max(t, 0.0), 1.0)))
                break
            acc += L
    return out

# =========================================================================
#  BMESH-БИЛДЕР
# =========================================================================

class Builder:
    def __init__(self, seed=0):
        self.bm = bmesh.new()
        self.gl = self.bm.verts.layers.int.new("grp")
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.group_names = []
        self._gid = {}
        self.rng = random.Random(seed)

    def gid(self, name):
        if name not in self._gid:
            self._gid[name] = len(self.group_names)
            self.group_names.append(name)
        return self._gid[name]

    def ring(self, mat, rx, rz, seg, gid, phase=0.0):
        vs = []
        for i in range(seg):
            a = 2.0 * pi * i / seg + phase
            v = self.bm.verts.new(mat @ Vector((cos(a) * rx, 0.0, sin(a) * rz)))
            v[self.gl] = gid
            vs.append(v)
        return vs

    def bridge(self, a, b, mat_idx=MAT_CHITIN):
        n = len(a)
        for i in range(n):
            j = (i + 1) % n
            try:
                f = self.bm.faces.new((a[i], a[j], b[j], b[i]))
            except ValueError:
                continue
            f.material_index = mat_idx
            f.smooth = True

    def fan(self, ring, tip, gid, mat_idx=MAT_CHITIN):
        apex = self.bm.verts.new(tip)
        apex[self.gl] = gid
        n = len(ring)
        for i in range(n):
            j = (i + 1) % n
            try:
                f = self.bm.faces.new((ring[i], ring[j], apex))
            except ValueError:
                continue
            f.material_index = mat_idx
            f.smooth = True
        return apex

    def cap(self, ring, mat_idx=MAT_CHITIN, smooth=False):
        try:
            f = self.bm.faces.new(ring)
        except ValueError:
            return None
        f.material_index = mat_idx
        f.smooth = smooth
        return f

    def lathe(self, group, profile, seg, tip_front=None, tip_back=None,
              mat_idx=MAT_CHITIN, seams=None, mirror_y=False, jitter=0.0):
        gid = self.gid(group)
        pts = [Vector((p[0], 0.0, p[3])) for p in profile]
        tans = tangents(pts)
        rings = []
        for i, (p, t) in enumerate(zip(profile, tans)):
            ry, rz = p[1], p[2]
            if seams and i in seams:
                k = seams[i]
                ry, rz = ry * k, rz * k
            if jitter:
                ry *= 1.0 + self.rng.uniform(-jitter, jitter)
                rz *= 1.0 + self.rng.uniform(-jitter, jitter)
            m = frame_matrix(pts[i], t)
            rings.append(self.ring(m, ry, rz, seg, gid))
        for a, b in zip(rings, rings[1:]):
            self.bridge(a, b, mat_idx)
        if tip_front is not None:
            self.fan(rings[-1], tip_front, gid, mat_idx)
        else:
            self.cap(list(reversed(rings[-1])), mat_idx)
        if tip_back is not None:
            self.fan(rings[0], tip_back, gid, mat_idx)
        else:
            self.cap(rings[0], mat_idx)
        return rings

    def tube(self, group, points, radii, seg, mat_idx=MAT_CHITIN,
             tip=None, cap_start=True, bumps=0.0):
        gid = self.gid(group)
        tans = tangents(points)
        rings = []
        for i, (p, t) in enumerate(zip(points, tans)):
            r = radii[i]
            rx, rz = (r, r) if isinstance(r, (int, float)) else r
            if bumps:
                k = 1.0 + bumps * (1.0 if i % 2 else -1.0)
                rx, rz = rx * k, rz * k
            rings.append(self.ring(frame_matrix(p, t), rx, rz, seg, gid))
        for a, b in zip(rings, rings[1:]):
            self.bridge(a, b, mat_idx)
        if tip is not None:
            self.fan(rings[-1], tip, gid, mat_idx)
        else:
            self.cap(list(reversed(rings[-1])), mat_idx)
        if cap_start:
            self.cap(rings[0], mat_idx)
        return rings

    def spike(self, group, base, direction, length, radius, seg=3,
              mat_idx=MAT_CHITIN):
        gid = self.gid(group)
        d = direction.normalized()
        m = frame_matrix(base, d)
        ring = self.ring(m, radius, radius, seg, gid)
        self.fan(ring, base + d * length, gid, mat_idx)
        return ring

    def uv_box_map(self, scale=0.12):
        for f in self.bm.faces:
            n = f.normal
            ax = max(range(3), key=lambda i: abs(n[i]))
            for l in f.loops:
                co = l.vert.co
                if ax == 0:
                    u, v = co.y, co.z
                elif ax == 1:
                    u, v = co.x, co.z
                else:
                    u, v = co.x, co.y
                l[self.uv].uv = (0.5 + u * scale, 0.5 + v * scale)

    def mark_sharp(self, angle_deg):
        thr = radians(angle_deg)
        for e in self.bm.edges:
            if len(e.link_faces) == 2 and e.calc_face_angle() > thr:
                e.smooth = False

    def tri_count(self):
        return sum(len(f.verts) - 2 for f in self.bm.faces)

def densify_profile(profile, count):
    n = len(profile)
    if count <= n:
        return list(profile)
    xs = [p[0] for p in profile]
    total = abs(xs[-1] - xs[0])
    if total < 1e-9:
        return list(profile)
    out = []
    for k in range(count):
        t = k / (count - 1)
        target = xs[0] + (xs[-1] - xs[0]) * t
        for i in range(n - 1):
            a, b = profile[i], profile[i + 1]
            if (target - a[0]) * (target - b[0]) <= 0 or i == n - 2:
                span = b[0] - a[0]
                u = 0.0 if abs(span) < 1e-12 else (target - a[0]) / span
                u = min(max(u, 0.0), 1.0)
                out.append(tuple(a[j] + (b[j] - a[j]) * u for j in range(4)))
                break
    return out

def remap_seams(seams, old_len, new_len):
    if not seams or new_len <= old_len:
        return dict(seams)
    out = {}
    for idx, k in seams.items():
        ni = int(round(idx * (new_len - 1) / (old_len - 1)))
        out[min(max(ni, 0), new_len - 1)] = k
    return out

def _build_eye(B, center, side, rings=5, seg=12):
    gid = B.gid("head")
    normal = Vector((0.18, side * 1.0, 0.10)).normalized()
    m = frame_matrix(center, normal)
    prev = None
    for i in range(rings):
        t = (i + 1) / rings
        r = 0.30 * sin(t * pi * 0.5)
        depth = 0.14 * (1.0 - cos(t * pi * 0.5))
        ring = []
        for k in range(seg):
            a = 2 * pi * k / seg
            local = Vector((cos(a) * r * 1.25, -depth + 0.14, sin(a) * r))
            v = B.bm.verts.new(m @ local)
            v[B.gl] = gid
            ring.append(v)
        if prev is None:
            centre = B.bm.verts.new(m @ Vector((0.0, 0.14, 0.0)))
            centre[B.gl] = gid
            B.fan(ring, (m @ Vector((0.0, 0.155, 0.0))), gid, MAT_EYE)
            B.bm.verts.remove(centre)
        else:
            B.bridge(prev, ring, MAT_EYE)
        prev = ring

def _radii(keys, n):
    if n <= len(keys):
        return list(keys[:n])
    out = []
    for i in range(n):
        t = i / (n - 1) * (len(keys) - 1)
        lo = min(int(t), len(keys) - 2)
        u = t - lo
        a, b = keys[lo], keys[lo + 1]
        out.append((a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u))
    return out

def _build_leg(B, leg, side, seg, jit, rng, rings=4):
    sfx = "%s%s" % (leg["id"], "R" if side > 0 else "L")

    def P(v):
        w = Vector((v.x, v.y * side, v.z))
        if jit:
            w += Vector((rng.uniform(-jit, jit), rng.uniform(-jit, jit),
                         rng.uniform(-jit, jit)))
        return w

    base, coxa = P(leg["base"]), P(leg["coxa"])
    knee, ankle, foot = P(leg["knee"]), P(leg["ankle"]), P(leg["foot"])

    B.tube("coxa_%s" % sfx, resample([base, coxa], 2),
           [(0.20, 0.20), (0.16, 0.17)], seg)

    fem = resample([coxa, knee], rings)
    B.tube("femur_%s" % sfx, fem,
           _radii([(0.155, 0.16), (0.145, 0.15), (0.125, 0.13),
                   (0.105, 0.11)], rings), seg)

    tib = resample([knee, ankle], rings)
    B.tube("tibia_%s" % sfx, tib,
           _radii([(0.105, 0.11), (0.09, 0.095), (0.075, 0.08),
                   (0.06, 0.062)], rings), seg)
    B.spike("tibia_%s" % sfx, tib[-1], (ankle - knee).normalized()
            .cross(Vector((0.0, 0.0, 1.0))) * side + Vector((0, 0, -0.2)),
            0.14, 0.035, seg=3)

    tn = max(3, rings - 1)
    tar = resample([ankle, foot], tn)
    B.tube("tarsus_%s" % sfx, tar,
           _radii([(0.06, 0.062), (0.048, 0.05), (0.036, 0.038)], tn), seg,
           tip=None)

    d = (foot - ankle).normalized()
    lat = d.cross(Z).normalized()
    for s in (1, -1):
        B.spike("tarsus_%s" % sfx, tar[-1] + lat * 0.02 * s,
                d * 0.7 + lat * 0.45 * s - Z * 0.55, 0.13, 0.03, seg=3)

def _build_hairs(B, count, rng):
    zones = [
        ("gaster", GASTER_PROFILE, int(count * 0.5)),
        ("thorax", THORAX_PROFILE, int(count * 0.25)),
        ("head", HEAD_PROFILE, count - int(count * 0.5) - int(count * 0.25)),
    ]
    for group, prof, n in zones:
        for _ in range(max(0, n)):
            i = rng.randrange(len(prof) - 1)
            t = rng.random()
            x = prof[i][0] * (1 - t) + prof[i + 1][0] * t
            ry = prof[i][1] * (1 - t) + prof[i + 1][1] * t
            rz = prof[i][2] * (1 - t) + prof[i + 1][2] * t
            zc = prof[i][3] * (1 - t) + prof[i + 1][3] * t
            a = rng.uniform(0, 2 * pi)
            a = abs(sin(a)) * pi - pi * 0.5
            nrm = Vector((0.0, cos(a) * rz, sin(a) * ry))
            if nrm.length < 1e-6:
                continue
            nrm.normalize()
            pos = Vector((x, cos(a) * ry, zc + sin(a) * rz))
            d = (nrm + Vector((rng.uniform(0.25, 0.6), 0.0, 0.15))).normalized()
            B.spike(group, pos + nrm * 0.01, d,
                    rng.uniform(0.16, 0.30), 0.018, seg=3)

def build_ant(res=1.0, cfg=CFG):
    def R(base, lo=3):
        return max(lo, int(round(base * res)))

    B = Builder(seed=cfg["seed"])
    rng = B.rng
    jit = cfg["asymmetry"]

    seg_head = R(20, 8)
    seg_thorax = R(16, 8)
    seg_gaster = R(20, 8)
    seg_petiole = R(12, 6)
    seg_leg = R(8, 5)
    seg_ant = R(7, 4)
    seg_mand = R(7, 4)

    lres = max(0.7, res ** 0.5)

    def L(base, lo=3):
        return max(lo, int(round(base * lres)))

    head_prof = densify_profile(HEAD_PROFILE, L(len(HEAD_PROFILE)))
    thorax_prof = densify_profile(THORAX_PROFILE, L(len(THORAX_PROFILE)))
    gaster_prof = densify_profile(GASTER_PROFILE, L(len(GASTER_PROFILE)))
    gaster_seams = remap_seams(GASTER_SEAMS, len(GASTER_PROFILE), len(gaster_prof))

    B.lathe("head", head_prof, seg_head,
            tip_front=HEAD_TIP, tip_back=HEAD_BACK, jitter=jit * 0.3)

    for side in (1, -1):
        _build_eye(B, Vector((3.42, side * 0.80, 2.06)), side,
                   rings=R(5, 3), seg=R(12, 6))

    for side in (1, -1):
        pts = [Vector((p.x, p.y * side, p.z)) for p in MANDIBLE]
        radii = [(0.15, 0.13), (0.12, 0.115), (0.085, 0.09), (0.05, 0.055)]
        B.tube("mandible_%s" % ("R" if side > 0 else "L"),
               resample(pts, 4), radii, seg_mand,
               tip=Vector((5.62, 0.02 * side, 1.45)))
        for k, t in enumerate((0.45, 0.72)):
            i = 1 + k
            base = pts[i] + Vector((0.0, -0.09 * side, -0.02))
            B.spike("mandible_%s" % ("R" if side > 0 else "L"),
                    base, Vector((0.35, -0.55 * side, -0.25)),
                    0.16, 0.05, seg=3)

    for side in (1, -1):
        sc = [Vector((p.x, p.y * side, p.z)) for p in ANT_SCAPE]
        fu = [Vector((p.x, p.y * side, p.z)) for p in ANT_FUNIC]
        sfx = "R" if side > 0 else "L"
        B.tube("scape_%s" % sfx, resample(sc, 3),
               [(0.085, 0.085), (0.075, 0.075), (0.07, 0.07)], seg_ant)
        fu_pts = resample(fu, 4)
        B.tube("funiculus_%s" % sfx, fu_pts,
               [(0.07, 0.07), (0.062, 0.062), (0.055, 0.055), (0.042, 0.042)],
               seg_ant, tip=fu_pts[-1] + Vector((0.34, 0.10 * side, -0.14)))

    B.lathe("thorax", thorax_prof, seg_thorax,
            tip_front=THORAX_FRONT, tip_back=THORAX_BACK, jitter=jit * 0.3)
    for side in (1, -1):
        B.spike("thorax", Vector((0.72, 0.30 * side, 1.95)),
                Vector((-0.55, 0.35 * side, 0.75)), 0.30, 0.075, seg=4)

    B.lathe("petiole", PETIOLE_PROFILE, seg_petiole)

    B.lathe("gaster", gaster_prof, seg_gaster,
            tip_front=None, tip_back=GASTER_TIP,
            seams=gaster_seams, jitter=jit * 0.25)

    leg_rings = L(4, 3)
    for leg in LEGS:
        for side in (1, -1):
            _build_leg(B, leg, side, seg_leg, jit, rng, rings=leg_rings)

    if cfg["hairs"]:
        _build_hairs(B, cfg["hair_count"], rng)

    return B

# =========================================================================
#  МАТЕРИАЛЫ И ТЕКСТУРЫ
# =========================================================================

def get_or_create_chitin_texture(name="ANT_Chitin_Color", size=512):
    """Генерирует органическую бесшовную текстуру хитина (game-ready)."""
    img = bpy.data.images.get(name)
    if img is not None:
        return img
    img = bpy.data.images.new(name, width=size, height=size)

    # Координатная сетка
    x = np.linspace(0, 1, size, endpoint=False)
    y = np.linspace(0, 1, size, endpoint=False)
    gx, gy = np.meshgrid(x, y)

    # Многочастотный шум с ячеистой структурой хитина
    n1 = np.sin(gx * 16.0 * np.pi) * np.cos(gy * 16.0 * np.pi)
    n2 = np.sin(gx * 32.0 * np.pi + n1 * 1.2) * np.cos(gy * 32.0 * np.pi + n1 * 1.2)
    n3 = np.cos((gx + gy) * 24.0 * np.pi)
    n4 = np.sin((gx - gy) * 40.0 * np.pi + n2 * 0.8)

    val = 0.5 + 0.26 * n1 + 0.14 * n2 + 0.06 * n3 + 0.04 * n4
    val = np.clip(val, 0.0, 1.0)

    # Хитин: богатый тёмно-каштановый / янтарно-коричневый градиент
    # Базовый цвет: тёмно-красно-коричневый -> тёплый терракотовый
    r = 0.075 + (0.240 - 0.075) * val
    g = 0.028 + (0.098 - 0.028) * val
    b = 0.012 + (0.042 - 0.012) * val
    a = np.ones_like(r)

    rgba = np.dstack((r, g, b, a)).astype(np.float32).flatten()
    img.pixels.foreach_set(rgba)
    img.pack()
    img.update()
    return img

def make_chitin_material(name="ANT_Chitin"):
    """Хитин: glTF-совместимый PBR материал с текстурой и правильным Base Color."""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (720, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (420, 0)

    # Создаём и подключаем Image Texture (для экспорта в GLB / Godot)
    tex_img = get_or_create_chitin_texture()
    tex_node = nt.nodes.new("ShaderNodeTexImage")
    tex_node.location = (100, 0)
    tex_node.image = tex_img

    nt.links.new(tex_node.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    # Базовые PBR-параметры (также работают как фоллбэк в glTF)
    bsdf.inputs["Base Color"].default_value = (0.16, 0.065, 0.028, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.32
    for key, val in (("Metallic", 0.15), ("Coat Weight", 0.6),
                     ("Specular IOR Level", 0.55), ("IOR", 1.55),
                     ("Anisotropic", 0.35)):
        if key in bsdf.inputs:
            bsdf.inputs[key].default_value = val
    return mat

def make_eye_material(name="ANT_Eye"):
    """Фасеточный глаз: тёмный и глянцевый PBR материал."""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (520, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (240, 0)

    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    bsdf.inputs["Base Color"].default_value = (0.018, 0.012, 0.010, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.15
    for key, val in (("Metallic", 0.25), ("Coat Weight", 0.9),
                     ("Specular IOR Level", 0.7)):
        if key in bsdf.inputs:
            bsdf.inputs[key].default_value = val
    return mat

# =========================================================================
#  ПЕРЕВОД BMESH -> ОБЪЕКТ
# =========================================================================

def bmesh_to_object(B, name, cfg=CFG):
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    mesh.materials.append(make_chitin_material())
    mesh.materials.append(make_eye_material())

    B.uv_box_map(scale=0.11)

    bmesh.ops.remove_doubles(B.bm, verts=list(B.bm.verts), dist=1e-5)
    B.bm.normal_update()
    bmesh.ops.recalc_face_normals(B.bm, faces=list(B.bm.faces))
    if cfg["triangulate"]:
        bmesh.ops.triangulate(B.bm, faces=list(B.bm.faces))
    B.mark_sharp(cfg["sharp_angle"])

    gl = B.gl
    assign = {}
    for i, v in enumerate(B.bm.verts):
        assign.setdefault(v[gl], []).append(i)

    B.bm.to_mesh(mesh)
    B.bm.free()

    for gidx, name_ in enumerate(B.group_names):
        vg = obj.vertex_groups.new(name=name_)
        idxs = assign.get(gidx, [])
        if idxs:
            vg.add(idxs, 1.0, 'REPLACE')

    for p in mesh.polygons:
        p.use_smooth = True
    if hasattr(mesh, "use_auto_smooth"):
        mesh.use_auto_smooth = True
        mesh.auto_smooth_angle = radians(cfg["sharp_angle"])

    scale = cfg["target_length"] / 7.6
    obj.scale = (scale, scale, scale)
    bpy.context.view_layer.update()
    return obj

def normalize_transform(obj, cfg=CFG):
    prev = bpy.context.view_layer.objects.active
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    zmin = min((obj.matrix_world @ v.co).z for v in obj.data.vertices)
    for v in obj.data.vertices:
        v.co.z -= zmin
    obj.data.update()
    obj.select_set(False)
    bpy.context.view_layer.objects.active = prev

# =========================================================================
#  АРМАТУРА + СКИННИНГ
# =========================================================================

def build_armature(mesh_obj, cfg=CFG, jit_rng=None):
    scale = cfg["target_length"] / 7.6
    rng = jit_rng or random.Random(cfg["seed"])

    arm_data = bpy.data.armatures.new("%s_Armature" % cfg["name"])
    arm = bpy.data.objects.new("%s_Rig" % cfg["name"], arm_data)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')

    zoff = min((mesh_obj.matrix_world @ v.co).z for v in mesh_obj.data.vertices)

    def S(v):
        return Vector((v[0] * scale, v[1] * scale, v[2] * scale - zoff))

    made = {}

    def bone(name, head, tail, parent=None, connected=False, groups=()):
        b = arm_data.edit_bones.new(name)
        b.head = S(head)
        b.tail = S(tail)
        if parent:
            b.parent = made[parent]
            b.use_connect = connected
        made[name] = b
        b["vgroups"] = ",".join(groups) if groups else ""
        return b

    bone("root", (0.0, 0.0, 0.0), (1.2, 0.0, 0.0))
    bone("thorax", (1.05, 0.0, 1.70), (2.35, 0.0, 1.86), "root",
         groups=("thorax",))
    bone("head", (2.35, 0.0, 1.88), (4.35, 0.0, 1.70), "thorax", True,
         groups=("head",))
    bone("mandible_R", (4.34, 0.34, 1.58), (5.46, 0.09, 1.46), "head",
         groups=("mandible_R",))
    bone("mandible_L", (4.34, -0.34, 1.58), (5.46, -0.09, 1.46), "head",
         groups=("mandible_L",))
    for side, sfx in ((1, "R"), (-1, "L")):
        bone("scape_%s" % sfx, (4.05, side * 0.34, 2.18),
             (5.35, side * 0.86, 2.88), "head", groups=("scape_%s" % sfx,))
        bone("funiculus_%s" % sfx, (5.35, side * 0.86, 2.88),
             (7.25, side * 1.55, 2.40), "scape_%s" % sfx, True,
             groups=("funiculus_%s" % sfx,))
    bone("petiole", (0.95, 0.0, 1.66), (0.20, 0.0, 1.82), "thorax",
         groups=("petiole",))
    bone("gaster", (0.20, 0.0, 1.86), (-2.60, 0.0, 1.90), "petiole", True,
         groups=("gaster",))

    for leg in LEGS:
        for side, sfx_side in ((1, "R"), (-1, "L")):
            sfx = "%s%s" % (leg["id"], sfx_side)

            def M(v):
                return (v.x, v.y * side, v.z)

            bone("coxa_%s" % sfx, M(leg["base"]), M(leg["coxa"]), "thorax",
                 groups=("coxa_%s" % sfx,))
            bone("femur_%s" % sfx, M(leg["coxa"]), M(leg["knee"]),
                 "coxa_%s" % sfx, True, groups=("femur_%s" % sfx,))
            bone("tibia_%s" % sfx, M(leg["knee"]), M(leg["ankle"]),
                 "femur_%s" % sfx, True, groups=("tibia_%s" % sfx,))
            bone("tarsus_%s" % sfx, M(leg["ankle"]), M(leg["foot"]),
                 "tibia_%s" % sfx, True, groups=("tarsus_%s" % sfx,))

    bone_groups = {n: b["vgroups"] for n, b in made.items()}
    bpy.ops.object.mode_set(mode='OBJECT')
    for n, g in bone_groups.items():
        arm_data.bones[n]["vgroups"] = g

    mesh_obj.parent = arm
    mod = mesh_obj.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm
    mod.use_vertex_groups = True

    rename = {}
    for bname in arm_data.bones.keys():
        raw = arm_data.bones[bname].get("vgroups", "")
        for g in [x for x in raw.split(",") if x]:
            rename[g] = bname
    for vg in mesh_obj.vertex_groups:
        if vg.name in rename and rename[vg.name] != vg.name:
            vg.name = rename[vg.name]

    covered = {vg.name for vg in mesh_obj.vertex_groups}
    if "thorax" not in covered:
        mesh_obj.vertex_groups.new(name="thorax")

    arm.select_set(False)
    return arm

def orient_bone_axes(arm):
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    for b in arm.data.edit_bones:
        if b.name.startswith(("femur", "tibia", "tarsus", "coxa")):
            b.align_roll(Vector((0.0, 0.0, 1.0)))
    bpy.ops.object.mode_set(mode='OBJECT')

# =========================================================================
#  АНИМАЦИЯ
# =========================================================================

TRIPOD_PHASE = {
    "1R": 0.0, "2L": 0.0, "3R": 0.0,
    "1L": 0.5, "2R": 0.5, "3L": 0.5,
}

def _pose_reset(arm):
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = Quaternion((1, 0, 0, 0))
        pb.location = (0, 0, 0)
        pb.scale = (1, 1, 1)

def _key(pb, frame, rot=True, loc=False):
    if rot:
        pb.keyframe_insert("rotation_quaternion", frame=frame)
    if loc:
        pb.keyframe_insert("location", frame=frame)

def _set_rot(pb, x=0.0, y=0.0, z=0.0):
    q = (Quaternion(Vector((1, 0, 0)), radians(x)) @
         Quaternion(Vector((0, 1, 0)), radians(y)) @
         Quaternion(Vector((0, 0, 1)), radians(z)))
    pb.rotation_quaternion = q

def _assign_action(arm, act):
    ad = arm.animation_data_create()
    try:
        ad.action = None
    except Exception:
        pass

    slot = None
    if hasattr(act, "slots") and hasattr(ad, "action_slot"):
        try:
            if len(act.slots) == 0:
                slot = act.slots.new(arm.id_type, arm.name)
            else:
                slot = act.slots[0]
        except Exception:
            slot = None

    ad.action = act
    if slot is not None:
        try:
            ad.action_slot = slot
        except Exception:
            pass

    bpy.context.view_layer.update()
    return act

def _new_action(arm, name, cyclic=True):
    old = bpy.data.actions.get(name)
    if old is not None:
        try:
            bpy.data.actions.remove(old)
        except Exception:
            pass

    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    if hasattr(act, "use_cyclic"):
        act.use_cyclic = cyclic
    _assign_action(arm, act)
    return act

def _action_range(act, start, end, cyclic=False):
    try:
        act.use_frame_range = True
        act.frame_start = float(start)
        act.frame_end = float(end)
    except Exception:
        pass
    if hasattr(act, "use_cyclic"):
        act.use_cyclic = bool(cyclic)

def _key_neutral_channels(arm, frame=1):
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = Quaternion((1, 0, 0, 0))
        pb.location = (0.0, 0.0, 0.0)
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        pb.keyframe_insert("location", frame=frame)

def action_fcurves(act):
    if hasattr(act, "fcurves"):
        return list(act.fcurves)
    out = []
    for layer in getattr(act, "layers", []):
        for strip in getattr(layer, "strips", []):
            for cb in getattr(strip, "channelbags", []):
                out.extend(cb.fcurves)
    return out

def _make_cyclic(act):
    for fc in action_fcurves(act):
        if not any(m.type == 'CYCLES' for m in fc.modifiers):
            fc.modifiers.new('CYCLES')
        for kp in fc.keyframe_points:
            kp.interpolation = 'BEZIER'
            kp.easing = 'AUTO'

def _make_locomotion_cyclic(act):
    for fc in action_fcurves(act):
        if not any(m.type == 'CYCLES' for m in fc.modifiers):
            fc.modifiers.new('CYCLES')
        for kp in fc.keyframe_points:
            kp.interpolation = 'LINEAR'

def make_idle_action(arm, cfg=CFG):
    n = cfg["idle_frames"]
    step = cfg["anim_step"]
    _pose_reset(arm)
    act = _new_action(arm, "ANT_Idle")
    _key_neutral_channels(arm, frame=1)

    pb = arm.pose.bones
    for f in range(1, n + 1, step):
        t = (f - 1) / n
        w = 2 * pi * t

        _set_rot(pb["gaster"], y=1.6 * sin(w) - 0.6, z=1.1 * sin(w * 0.5))
        _key(pb["gaster"], f)

        _set_rot(pb["petiole"], y=0.8 * sin(w))
        _key(pb["petiole"], f)

        _set_rot(pb["thorax"], y=0.5 * sin(w + 0.6))
        pb["thorax"].location = (0.0, 0.0, 0.004 * sin(w))
        _key(pb["thorax"], f, loc=True)

        _set_rot(pb["head"], y=1.2 * sin(w * 0.5), z=4.5 * sin(w * 0.25))
        _key(pb["head"], f)

        for side, sgn in (("R", 1.0), ("L", -1.0)):
            ph = 0.0 if side == "R" else 1.9
            _set_rot(pb["scape_%s" % side],
                     x=6.0 * sin(w * 2.0 + ph) * sgn,
                     z=9.0 * sin(w * 1.5 + ph))
            _key(pb["scape_%s" % side], f)
            _set_rot(pb["funiculus_%s" % side],
                     x=10.0 * sin(w * 2.5 + ph + 0.8) * sgn,
                     z=13.0 * sin(w * 2.0 + ph + 0.5))
            _key(pb["funiculus_%s" % side], f)

        jaw = max(0.0, sin(w * 3.0)) ** 6 * 7.0
        _set_rot(pb["mandible_R"], z=-jaw)
        _set_rot(pb["mandible_L"], z=jaw)
        _key(pb["mandible_R"], f)
        _key(pb["mandible_L"], f)

        for leg in LEGS:
            for sfx_side in ("R", "L"):
                sfx = "%s%s" % (leg["id"], sfx_side)
                ph = TRIPOD_PHASE[sfx] * 2 * pi + int(leg["id"]) * 0.7
                _set_rot(pb["coxa_%s" % sfx], z=0.8 * sin(w + ph))
                _set_rot(pb["femur_%s" % sfx], z=1.3 * sin(w + ph))
                _set_rot(pb["tibia_%s" % sfx], z=-1.1 * sin(w + ph))
                _key(pb["coxa_%s" % sfx], f)
                _key(pb["femur_%s" % sfx], f)
                _key(pb["tibia_%s" % sfx], f)

    _make_cyclic(act)
    _action_range(act, 1, n, cyclic=True)
    return act

def _leg_cycle(phase, leg_id):
    p = fmod(phase, 1.0)
    if p < 0.0:
        p += 1.0

    amp = {1: 17.0, 2: 19.0, 3: 21.0}[leg_id]
    lift = {1: 22.0, 2: 24.0, 3: 20.0}[leg_id]
    swing_part = 0.38

    if p < swing_part:
        u = p / swing_part
        s = smoothstep(u)
        h = sin(pi * u)
        swing = -amp + 2.0 * amp * s
        femur = -lift * h
        tibia = lift * 0.90 * h
        tarsus = -9.0 * h
    else:
        u = (p - swing_part) / (1.0 - swing_part)
        h = sin(pi * u)
        swing = amp - 2.0 * amp * u
        femur = 1.8 * h
        tibia = -1.2 * h
        tarsus = 2.0 * h

    return swing, femur, tibia, tarsus

def _run_leg_cycle(phase, leg_id):
    p = fmod(phase, 1.0)
    if p < 0.0:
        p += 1.0

    amp = {1: 25.0, 2: 28.0, 3: 31.0}[leg_id]
    lift = {1: 30.0, 2: 34.0, 3: 29.0}[leg_id]
    swing_part = 0.34

    if p < swing_part:
        u = p / swing_part
        s = smoothstep(u)
        h = sin(pi * u)
        swing = -amp + 2.0 * amp * s
        femur = -lift * h
        tibia = lift * 0.94 * h
        tarsus = -12.0 * h
    else:
        u = (p - swing_part) / (1.0 - swing_part)
        h = sin(pi * u)
        swing = amp - 2.0 * amp * u
        femur = 2.5 * h
        tibia = -1.8 * h
        tarsus = 3.0 * h

    return swing, femur, tibia, tarsus

def make_walk_action(arm, cfg=CFG):
    n = max(16, int(cfg["walk_frames"]))
    _pose_reset(arm)
    act = _new_action(arm, "ANT_Walk")
    _key_neutral_channels(arm, frame=1)
    pb = arm.pose.bones

    for f in range(1, n + 2):
        t = (f - 1) / n
        w = 2.0 * pi * t

        pb["root"].location = (0.0, 0.0, 0.0)
        _key(pb["root"], f, rot=False, loc=True)

        for leg in LEGS:
            lid = int(leg["id"])
            swing_scale = {1: 0.90, 2: 1.00, 3: 1.08}[lid]
            lift_scale = {1: 0.90, 2: 1.00, 3: 0.88}[lid]

            for side_name, side_sign in (("R", 1.0), ("L", -1.0)):
                sfx = "%s%s" % (leg["id"], side_name)
                ph = t + TRIPOD_PHASE[sfx] + 0.16
                swing, femur, tibia, tarsus = _leg_cycle(ph, lid)

                _set_rot(pb["coxa_%s" % sfx],
                         x=1.4 * side_sign * sin(2.0 * pi * ph),
                         z=swing * swing_scale)
                _set_rot(pb["femur_%s" % sfx],
                         y=swing * 0.18,
                         z=femur * lift_scale)
                _set_rot(pb["tibia_%s" % sfx], z=tibia * lift_scale)
                _set_rot(pb["tarsus_%s" % sfx], z=tarsus)
                for part in ("coxa", "femur", "tibia", "tarsus"):
                    _key(pb["%s_%s" % (part, sfx)], f)

        contact = 0.5 - 0.5 * cos(2.0 * w)
        pb["thorax"].location = (0.0, 0.0, -0.0025 + 0.0065 * contact)
        _set_rot(pb["thorax"],
                 x=0.9 * sin(w),
                 y=0.7 * sin(2.0 * w + 0.35),
                 z=1.5 * sin(w + 0.12))
        _key(pb["thorax"], f, loc=True)

        _set_rot(pb["petiole"], y=0.9 * sin(2.0 * w - 0.55))
        _key(pb["petiole"], f)
        _set_rot(pb["gaster"],
                 y=1.8 * sin(2.0 * w - 0.85),
                 z=2.6 * sin(w - 0.95))
        _key(pb["gaster"], f)

        _set_rot(pb["head"],
                 y=-0.7 * sin(2.0 * w + 0.1),
                 z=-1.15 * sin(w + 0.15))
        _key(pb["head"], f)

        for side, sgn in (("R", 1.0), ("L", -1.0)):
            aph = 0.0 if side == "R" else 1.35
            _set_rot(pb["scape_%s" % side],
                     x=(4.0 + 3.0 * sin(w + aph)) * sgn,
                     z=4.5 * sin(w * 1.15 + aph))
            _key(pb["scape_%s" % side], f)
            _set_rot(pb["funiculus_%s" % side],
                     x=(7.0 + 5.0 * sin(w * 1.30 + aph + 0.5)) * sgn,
                     z=7.0 * sin(w * 1.45 + aph + 0.25))
            _key(pb["funiculus_%s" % side], f)

        _set_rot(pb["mandible_R"], z=-2.0)
        _set_rot(pb["mandible_L"], z=2.0)
        _key(pb["mandible_R"], f)
        _key(pb["mandible_L"], f)

    _make_locomotion_cyclic(act)
    _action_range(act, 1, n + 1, cyclic=True)
    return act

def make_run_action(arm, cfg=CFG):
    n = max(10, int(cfg["run_frames"]))
    _pose_reset(arm)
    act = _new_action(arm, "ANT_Run")
    _key_neutral_channels(arm, frame=1)
    pb = arm.pose.bones

    for f in range(1, n + 2):
        t = (f - 1) / n
        w = 2.0 * pi * t

        pb["root"].location = (0.0, 0.0, 0.0)
        _key(pb["root"], f, rot=False, loc=True)

        for leg in LEGS:
            lid = int(leg["id"])
            for side_name, side_sign in (("R", 1.0), ("L", -1.0)):
                sfx = "%s%s" % (leg["id"], side_name)
                ph = t + TRIPOD_PHASE[sfx] + 0.12
                swing, femur, tibia, tarsus = _run_leg_cycle(ph, lid)

                _set_rot(pb["coxa_%s" % sfx],
                         x=3.6 * side_sign * sin(2.0 * pi * ph),
                         z=swing)
                _set_rot(pb["femur_%s" % sfx],
                         y=swing * 0.30,
                         z=femur)
                _set_rot(pb["tibia_%s" % sfx], z=tibia)
                _set_rot(pb["tarsus_%s" % sfx], z=tarsus)
                for part in ("coxa", "femur", "tibia", "tarsus"):
                    _key(pb["%s_%s" % (part, sfx)], f)

        bounce = 0.5 - 0.5 * cos(2.0 * w)
        pb["thorax"].location = (0.0, 0.0, -0.009 + 0.014 * bounce)
        _set_rot(pb["thorax"],
                 x=2.4 * sin(w),
                 y=2.0 * sin(2.0 * w + 0.25),
                 z=3.8 * sin(w + 0.08))
        _key(pb["thorax"], f, loc=True)

        _set_rot(pb["petiole"], y=2.2 * sin(2.0 * w - 0.7))
        _key(pb["petiole"], f)
        _set_rot(pb["gaster"],
                 y=4.6 * sin(2.0 * w - 1.0),
                 z=6.0 * sin(w - 1.1))
        _key(pb["gaster"], f)

        _set_rot(pb["head"],
                 y=-2.2 - 1.4 * sin(2.0 * w),
                 z=-1.8 * sin(w))
        _key(pb["head"], f)

        for side, sgn in (("R", 1.0), ("L", -1.0)):
            aph = 0.0 if side == "R" else 1.10
            _set_rot(pb["scape_%s" % side],
                     x=(10.0 + 3.5 * sin(2.0 * w + aph)) * sgn,
                     z=-7.5 + 3.0 * sin(2.0 * w + aph))
            _key(pb["scape_%s" % side], f)
            _set_rot(pb["funiculus_%s" % side],
                     x=(15.0 + 5.0 * sin(2.0 * w + aph + 0.35)) * sgn,
                     z=-12.0 + 4.0 * sin(2.0 * w + aph + 0.2))
            _key(pb["funiculus_%s" % side], f)

        _set_rot(pb["mandible_R"], z=-4.0)
        _set_rot(pb["mandible_L"], z=4.0)
        _key(pb["mandible_R"], f)
        _key(pb["mandible_L"], f)

    _make_locomotion_cyclic(act)
    _action_range(act, 1, n + 1, cyclic=True)
    return act

def make_attack_action(arm, cfg=CFG):
    n = max(24, int(cfg["attack_frames"]))
    _pose_reset(arm)
    act = _new_action(arm, "ANT_Attack", cyclic=False)
    _key_neutral_channels(arm, frame=1)
    pb = arm.pose.bones

    for f in range(1, n + 1):
        t = (f - 1) / (n - 1)

        if t < 0.22:
            u = smoothstep(t / 0.22)
            threat = u
            strike = 0.0
            bite = 0.0
            recover = 0.0
        elif t < 0.46:
            u = smoothstep((t - 0.22) / 0.24)
            threat = 1.0
            strike = u
            bite = 0.0
            recover = 0.0
        elif t < 0.58:
            u = smoothstep((t - 0.46) / 0.12)
            threat = 1.0
            strike = 1.0
            bite = u
            recover = 0.0
        elif t < 0.70:
            u = smoothstep((t - 0.58) / 0.12)
            threat = 1.0
            strike = 1.0 - 0.08 * u
            bite = 1.0
            recover = 0.0
        else:
            u = smoothstep((t - 0.70) / 0.30)
            threat = 1.0 - u
            strike = 0.92 * (1.0 - u)
            bite = 1.0 - u
            recover = u

        pb["root"].location = (0.0, 0.0, 0.0)
        _key(pb["root"], f, rot=False, loc=True)

        forward = cfg["target_length"] * (0.020 * strike - 0.004 * threat)
        pb["thorax"].location = (forward, 0.0, 0.010 * threat - 0.014 * strike)
        _set_rot(pb["thorax"],
                 x=0.8 * sin(pi * t),
                 y=-5.0 * threat + 11.0 * strike,
                 z=0.0)
        _key(pb["thorax"], f, loc=True)

        _set_rot(pb["head"],
                 y=-7.0 * threat + 18.0 * strike + 7.0 * bite,
                 z=1.2 * sin(pi * t))
        _key(pb["head"], f)
        _set_rot(pb["petiole"], y=3.5 * strike)
        _key(pb["petiole"], f)
        _set_rot(pb["gaster"],
                 y=-8.0 * strike - 3.0 * threat,
                 z=-1.5 * sin(pi * t))
        _key(pb["gaster"], f)

        for leg in LEGS:
            lid = int(leg["id"])
            for side_name, side_sign in (("R", 1.0), ("L", -1.0)):
                sfx = "%s%s" % (leg["id"], side_name)
                if lid == 1:
                    coxa = -10.0 * threat - 18.0 * strike
                    femur = -8.0 * threat - 16.0 * strike
                    tibia = 10.0 * threat + 18.0 * strike
                    tarsus = -6.0 * strike
                    outward = 2.0 * side_sign * threat
                elif lid == 2:
                    coxa = 7.0 * threat + 4.0 * strike
                    femur = 5.0 * threat
                    tibia = -5.0 * threat
                    tarsus = 2.0 * threat
                    outward = 3.5 * side_sign * threat
                else:
                    coxa = 12.0 * threat + 5.0 * strike
                    femur = 7.0 * threat
                    tibia = -7.5 * threat
                    tarsus = 4.0 * threat
                    outward = 4.5 * side_sign * threat

                _set_rot(pb["coxa_%s" % sfx], x=outward, z=coxa)
                _set_rot(pb["femur_%s" % sfx], z=femur)
                _set_rot(pb["tibia_%s" % sfx], z=tibia)
                _set_rot(pb["tarsus_%s" % sfx], z=tarsus)
                for part in ("coxa", "femur", "tibia", "tarsus"):
                    _key(pb["%s_%s" % (part, sfx)], f)

        for side, sgn in (("R", 1.0), ("L", -1.0)):
            _set_rot(pb["scape_%s" % side],
                     x=(8.0 * threat + 12.0 * strike) * sgn,
                     z=8.0 * threat - 15.0 * strike)
            _key(pb["scape_%s" % side], f)
            _set_rot(pb["funiculus_%s" % side],
                     x=(12.0 * threat + 18.0 * strike) * sgn,
                     z=12.0 * threat - 22.0 * strike)
            _key(pb["funiculus_%s" % side], f)

        jaw_open = 3.0 + 26.0 * threat + 5.0 * strike
        jaw = jaw_open * (1.0 - 0.92 * bite)
        _set_rot(pb["mandible_R"], z=-jaw)
        _set_rot(pb["mandible_L"], z=jaw)
        _key(pb["mandible_R"], f)
        _key(pb["mandible_L"], f)

    for fc in action_fcurves(act):
        for kp in fc.keyframe_points:
            kp.interpolation = 'BEZIER'
            kp.easing = 'AUTO'
    _action_range(act, 1, n, cyclic=False)
    return act

def setup_nla(arm, actions):
    ad = arm.animation_data_create()
    try:
        ad.action = None
    except Exception:
        pass

    for track in list(ad.nla_tracks):
        ad.nla_tracks.remove(track)

    scene = bpy.context.scene
    for marker in list(scene.timeline_markers):
        if marker.name.startswith("ANT_"):
            scene.timeline_markers.remove(marker)

    cursor = 1
    preview_ranges = []

    for act in actions:
        try:
            astart = float(act.frame_start) if act.use_frame_range else float(act.frame_range[0])
            aend = float(act.frame_end) if act.use_frame_range else float(act.frame_range[1])
        except Exception:
            astart, aend = tuple(float(x) for x in act.frame_range)

        if aend <= astart:
            astart, aend = 1.0, 2.0

        duration = aend - astart
        strip_start = float(cursor)
        strip_end = strip_start + duration

        tr = ad.nla_tracks.new()
        tr.name = act.name
        tr.mute = False
        tr.is_solo = False

        strip = tr.strips.new(act.name, int(strip_start), act)

        if hasattr(strip, "action_slot") and hasattr(act, "slots"):
            try:
                if len(act.slots):
                    strip.action_slot = act.slots[0]
            except Exception:
                pass

        try:
            strip.action_frame_start = astart
            strip.action_frame_end = aend
        except Exception:
            pass

        strip.frame_start = strip_start
        strip.frame_end = strip_end
        strip.repeat = 1.0
        strip.scale = 1.0
        strip.blend_type = 'REPLACE'
        strip.extrapolation = 'NOTHING'
        strip.mute = False

        scene.timeline_markers.new(act.name, frame=int(strip_start))
        preview_ranges.append((act.name, int(strip_start), int(round(strip_end))))
        cursor = int(round(strip_end)) + 1

    try:
        ad.action = None
    except Exception:
        pass

    scene.frame_start = 1
    scene.frame_end = max(1, cursor - 1)
    scene.frame_set(1)
    bpy.context.view_layer.update()

    print("[ant anim] Blender preview sequence:")
    for name, s, e in preview_ranges:
        print("[ant anim]   %-10s %4d .. %4d" % (name, s, e))
    print("[ant anim] Export GLB with Animation Mode = Actions (NOT NLA Tracks).")

    return preview_ranges

def autotune_res(cfg=CFG):
    lo_t, hi_t = cfg["tri_budget"]
    target = cfg["tri_target"]

    best, best_err, best_tris = cfg["res"], None, None
    lo, hi = 0.45, 2.2
    for _ in range(14):
        mid = (lo + hi) * 0.5
        B = build_ant(mid, cfg)
        tris = B.tri_count()
        B.bm.free()
        err = abs(tris - target)
        if best_err is None or (lo_t <= tris <= hi_t and err < best_err):
            best, best_err, best_tris = mid, err, tris
        if tris > target:
            hi = mid
        else:
            lo = mid
    return best, best_tris

def clear_previous(cfg=CFG):
    names = (cfg["name"], "%s_Rig" % cfg["name"], "%s_Armature" % cfg["name"])
    for obj in list(bpy.data.objects):
        if obj.name.startswith(names):
            bpy.data.objects.remove(obj, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.armatures):
        for blk in list(coll):
            if blk.name.startswith(names) and blk.users == 0:
                coll.remove(blk)
    owned_actions = ("ANT_Idle", "ANT_Walk", "ANT_Run", "ANT_Attack")
    for act in list(bpy.data.actions):
        base = act.name.split(".")[0]
        if base in owned_actions:
            bpy.data.actions.remove(act)

def generate(cfg=CFG):
    random.seed(cfg["seed"])
    if cfg["clear_previous"]:
        clear_previous(cfg)

    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')

    res = cfg["res"]
    if cfg["autotune"]:
        res, pre = autotune_res(cfg)
        print("[ant] autotune: res=%.3f -> ~%s tris" % (res, pre))

    B = build_ant(res, cfg)
    tris_raw = B.tri_count()
    obj = bmesh_to_object(B, cfg["name"], cfg)
    normalize_transform(obj, cfg)

    arm = None
    if cfg["make_rig"]:
        arm = build_armature(obj, cfg)
        orient_bone_axes(arm)
        if cfg["make_anim"]:
            idle = make_idle_action(arm, cfg)
            walk = make_walk_action(arm, cfg)
            run = make_run_action(arm, cfg)
            attack = make_attack_action(arm, cfg)

            for _act in (idle, walk, run, attack):
                _fcs = action_fcurves(_act)
                _keys = sum(len(fc.keyframe_points) for fc in _fcs)
                try:
                    _rng = tuple(round(x, 2) for x in _act.frame_range)
                except Exception:
                    _rng = (0, 0)
                print("[ant anim] %-10s curves=%3d keys=%5d range=%s"
                      % (_act.name, len(_fcs), _keys, _rng))

            setup_nla(arm, [idle, walk, run, attack])
            _pose_reset(arm)
            bpy.context.scene.frame_set(1)

    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    lo, hi = cfg["tri_budget"]
    status = "OK" if lo <= tris <= hi else "ВНЕ БЮДЖЕТА"
    print("=" * 62)
    print(" муравей собран: %s" % obj.name)
    print(" верт.: %d   полигонов: %d   треугольников: %d  [%s]"
          % (len(obj.data.vertices), len(obj.data.polygons), tris, status))
    print(" бюджет: %d..%d   разрешение: %.3f   (сырой счёт %d)"
          % (lo, hi, res, tris_raw))
    if arm:
        print(" костей: %d   экшены: %s"
              % (len(arm.data.bones),
                 ", ".join(a.name for a in bpy.data.actions
                           if a.name.startswith("ANT_"))))
    print(" размер: %.3f x %.3f x %.3f юнитов"
          % tuple(obj.dimensions))
    print("=" * 62)

    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    return obj, arm

def export_to_godot(output_path="assets/models/ant.glb", cfg=CFG):
    abs_out = os.path.abspath(output_path)
    os.makedirs(os.path.dirname(abs_out), exist_ok=True)
    
    # Ensure animation_data action is None so actions are exported separately
    for arm_obj in bpy.data.objects:
        if arm_obj.type == 'ARMATURE' and arm_obj.animation_data:
            arm_obj.animation_data.action = None

    # Select only Ant and Ant_Rig for export
    bpy.ops.object.select_all(action='DESELECT')
    ant_obj = bpy.data.objects.get(cfg["name"])
    rig_obj = bpy.data.objects.get("%s_Rig" % cfg["name"])
    if ant_obj:
        ant_obj.select_set(True)
    if rig_obj:
        rig_obj.select_set(True)
        bpy.context.view_layer.objects.active = rig_obj

    bpy.ops.export_scene.gltf(
        filepath=abs_out,
        export_format='GLB',
        use_selection=True,
        export_animation_mode='ACTIONS',
        export_animations=True,
        export_anim_slide_to_zero=True,
        export_materials='EXPORT',
        export_image_format='AUTO',
        export_yup=True,
        export_skins=True,
        export_apply=False,
        export_def_bones=False,
    )
    print(f"[ant] Экспорт завершён с текстурой и материалами: {abs_out}")

if __name__ == "__main__":
    obj, arm = generate(CFG)
    import sys
    if "--export" in sys.argv:
        idx = sys.argv.index("--export")
        out_file = sys.argv[idx + 1] if idx + 1 < len(sys.argv) else "assets/models/ant.glb"
        export_to_godot(out_file, CFG)
