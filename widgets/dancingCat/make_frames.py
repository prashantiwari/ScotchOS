#!/usr/bin/env python3
"""Renders the dancing cat to frames.js: a real 3D model (signed distance fields, ray marched, lit), one
string of ASCII per frame. The widget only plays the strings back, so the 3D work happens once, here.

    python3 make_frames.py              # writes frames.js next to this file, then `scotchos restart`
    python3 make_frames.py --preview 7  # prints frame 7 instead of writing anything
"""
import argparse
import json
from pathlib import Path

import numpy as np

COLS, ROWS = 62, 26     # fills the 340 px card at a 9 px font (5.4 x 11 px per character)
CELL_ASPECT = 5.4 / 11  # width / height of one character, or the cat comes out stretched
BEATS = 16
FRAMES_PER_BEAT = 6     # the widget's timer assumes this too (FRAMES_PER_BEAT in CatWidget.qml)
RAMP = ".,:;~=+*oO#%@"  # dark to bright. No quotes or backslashes, so frames.js needs no escaping
LIGHT = np.array([-0.45, 0.75, 0.65])
LIGHT = LIGHT / np.linalg.norm(LIGHT)
CAM = np.array([0.0, 1.45, 6.0])
LOOK_AT = np.array([0.0, 1.12, 0.0])
VIEW_HEIGHT = 2.75      # world units covered by the rows, at the cat's distance

# Surface brightness of each part: fur, light fur (muzzle, belly, paws), eyes, nose.
FUR, LIGHT_FUR, EYE, NOSE = 0, 1, 2, 3


def smoothstep(a, b, x):
    x = min(1.0, max(0.0, (x - a) / (b - a)))
    return x * x * (3 - 2 * x)


def vec(*v):
    return np.array(v, dtype=float)


# ---- Distance functions: p is (N, 3); negative inside ----
def ellipsoid(p, center, radii):
    q = (p - center) / radii
    k0 = np.linalg.norm(q, axis=1)
    k1 = np.linalg.norm(q / radii, axis=1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-6)


def round_cone(p, a, b, ra, rb):
    """A capsule whose radius goes from ra at a to rb at b."""
    ab = b - a
    h = np.clip(((p - a) @ ab) / max(ab @ ab, 1e-9), 0.0, 1.0)
    return np.linalg.norm(p - a - h[:, None] * ab, axis=1) - (ra + (rb - ra) * h)


def smooth_min(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


def rot_y(p, angle):
    c, s = np.cos(angle), np.sin(angle)
    out = p.copy()
    out[:, 0] = c * p[:, 0] + s * p[:, 2]
    out[:, 2] = -s * p[:, 0] + c * p[:, 2]
    return out


def rot_z(p, angle):
    c, s = np.cos(angle), np.sin(angle)
    out = p.copy()
    out[:, 0] = c * p[:, 0] + s * p[:, 1]
    out[:, 1] = -s * p[:, 0] + c * p[:, 1]
    return out


def elbow(a, b, length, bend):
    """Two-bone joint between a and b for two bones of `length`, pushed out along `bend`."""
    d = np.linalg.norm(b - a)
    out = np.sqrt(max(length * length - d * d / 4, 0.0))
    return (a + b) / 2 + bend / np.linalg.norm(bend) * out


# ---- The dance: everything is a function of the beat, and the 16 beats loop ----
def pose(beat):
    swing = np.sin(np.pi * beat)                # side to side, once per two beats
    hop = abs(np.sin(np.pi * beat))             # up on every beat
    pirouette = smoothstep(12, 12.5, beat) * (1 - smoothstep(15.5, 16, beat))
    point = smoothstep(7.5, 8, beat) * (1 - smoothstep(11.5, 12, beat))
    wave = 1 - max(point, pirouette)

    # Yaw: swings to show the sides, then one whole turn in the last four beats.
    spin = smoothstep(12, 16, beat) * 2 * np.pi
    yaw = 0.6 * np.sin(np.pi * beat / 4) * (1 - pirouette) + spin

    hip = vec(0.16 * swing, 0.74 + 0.10 * hop, 0)
    chest = hip + vec(-0.12 * swing, 0.56, 0.02)
    head = chest + vec(-0.10 * swing, 0.50, 0.06)
    tilt = 0.28 * swing

    # Paw targets, relative to the shoulders.
    sl, sr = chest + vec(-0.27, 0.10, 0), chest + vec(0.27, 0.10, 0)
    # Both up, waving against the hips.
    wl, wr = sl + vec(-0.52 + 0.16 * swing, 0.50, 0.1), sr + vec(0.52 + 0.16 * swing, 0.50, 0.1)
    # Disco: one paw to the sky, the other on the hip, swapping every 2 beats.
    side = np.tanh(4 * np.sin(np.pi * beat / 2))
    up, down = vec(0.50, 0.58, 0.1), vec(0.20, -0.38, 0.22)
    pl = sl + (vec(-up[0], up[1], up[2]) * (side + 1) / 2 + vec(-down[0], down[1], down[2]) * (1 - side) / 2)
    pr = sr + (up * (1 - side) / 2 + down * (side + 1) / 2)
    # Arms straight out while turning.
    tl, tr = sl + vec(-0.70, 0.14, 0), sr + vec(0.70, 0.14, 0)
    paw_l = wl * wave + pl * point + tl * pirouette
    paw_r = wr * wave + pr * point + tr * pirouette

    # Feet step: the weight goes to one leg and the other lifts.
    lift_l, lift_r = 0.14 * max(0.0, swing), 0.14 * max(0.0, -swing)
    foot_l, foot_r = vec(-0.28, 0.10 + lift_l, 0.06), vec(0.28, 0.10 + lift_r, 0.06)
    hip_l, hip_r = hip + vec(-0.17, -0.06, 0), hip + vec(0.17, -0.06, 0)

    return dict(
        yaw=yaw, hip=hip, chest=chest, head=head, tilt=tilt, sl=sl, sr=sr, paw_l=paw_l, paw_r=paw_r,
        foot_l=foot_l, foot_r=foot_r, hip_l=hip_l, hip_r=hip_r, beat=beat, hop=hop,
        el=elbow(sl, paw_l, 0.40, vec(-1, -0.5, -0.2)), er=elbow(sr, paw_r, 0.40, vec(1, -0.5, -0.2)),
        kl=elbow(hip_l, foot_l, 0.38, vec(-0.35, 0, 1)), kr=elbow(hip_r, foot_r, 0.38, vec(0.35, 0, 1)),
    )


# ---- The cat: returns the distance and which surface is nearest ----
def cat(world, P):
    p = rot_y(world, P["yaw"])

    d = round_cone(p, P["hip"], P["chest"], 0.36, 0.27)                 # torso
    belly = ellipsoid(p, (P["hip"] + P["chest"]) / 2 + vec(0, -0.03, 0.17), vec(0.24, 0.36, 0.20))

    for a, m, b, ra, rm, rb in ((P["sl"], P["el"], P["paw_l"], 0.11, 0.09, 0.08),
                                (P["sr"], P["er"], P["paw_r"], 0.11, 0.09, 0.08),
                                (P["hip_l"], P["kl"], P["foot_l"], 0.16, 0.12, 0.09),
                                (P["hip_r"], P["kr"], P["foot_r"], 0.16, 0.12, 0.09)):
        limb = np.minimum(round_cone(p, a, m, ra, rm), round_cone(p, m, b, rm, rb))
        d = smooth_min(d, limb, 0.07)

    # Paws and feet are light, like socks.
    paws = np.minimum(ellipsoid(p, P["paw_l"], vec(0.12, 0.12, 0.12)), ellipsoid(p, P["paw_r"], vec(0.12, 0.12, 0.12)))
    feet = np.minimum(ellipsoid(p, P["foot_l"] + vec(0, -0.02, 0.09), vec(0.14, 0.09, 0.2)),
                      ellipsoid(p, P["foot_r"] + vec(0, -0.02, 0.09), vec(0.14, 0.09, 0.2)))
    socks = np.minimum(paws, feet)
    d = smooth_min(d, socks, 0.04)

    # Tail: a chain that waves more towards the tip.
    prev = P["hip"] + vec(0, -0.14, -0.30)
    for i in range(1, 8):
        u = i / 7
        phase = np.pi * P["beat"] - 2.2 * u
        pos = P["hip"] + vec(0.46 * u * np.sin(phase), -0.14 + 1.05 * u * u, -0.30 - 0.32 * u)
        d = np.minimum(d, round_cone(p, prev, pos, 0.085 - 0.03 * (u - 1 / 7), 0.085 - 0.03 * u))
        prev = pos

    # The head has its own frame, so it can tilt.
    h = rot_z(p - P["head"], P["tilt"])
    o = vec(0, 0, 0)
    skull = ellipsoid(h, o, vec(0.42, 0.34, 0.36))
    for sx in (-1, 1):
        cheek = ellipsoid(h, vec(sx * 0.25, -0.09, 0.08), vec(0.17, 0.14, 0.16))
        ear = round_cone(h, vec(sx * 0.24, 0.24, 0), vec(sx * 0.32, 0.56, -0.02), 0.13, 0.015)
        skull = smooth_min(smooth_min(skull, cheek, 0.06), ear, 0.03)
    d = smooth_min(d, skull, 0.05)

    muzzle = np.minimum(ellipsoid(h, vec(-0.09, -0.10, 0.31), vec(0.12, 0.09, 0.09)),
                        ellipsoid(h, vec(0.09, -0.10, 0.31), vec(0.12, 0.09, 0.09)))
    d = smooth_min(d, muzzle, 0.03)
    eyes = np.minimum(ellipsoid(h, vec(-0.17, 0.05, 0.31), vec(0.08, 0.095, 0.05)),
                      ellipsoid(h, vec(0.17, 0.05, 0.31), vec(0.08, 0.095, 0.05)))
    nose = ellipsoid(h, vec(0, -0.04, 0.39), vec(0.05, 0.035, 0.03))
    d = np.minimum(np.minimum(d, eyes), nose)

    # Which surface: the features win where they stick out, the light fur where it's near the surface.
    mat = np.full(len(p), FUR)
    mat[(belly < 0.02) | (muzzle < 0.02) | (socks < 0.02)] = LIGHT_FUR
    mat[eyes < 0.012] = EYE
    mat[nose < 0.012] = NOSE

    # Tabby stripes across the back and the top of the head, in each part's frame.
    stripe = (np.sin(p[:, 1] * 22) > 0.45) & (p[:, 2] < 0.05)
    stripe |= (h[:, 1] > 0.15) & (np.abs(np.sin(h[:, 0] * 18)) < 0.3) & (h[:, 2] > -0.2)
    return d, mat, stripe


def render(P):
    """One frame as ROWS lines of text."""
    # Camera rays, one per character.
    forward = LOOK_AT - CAM
    dist = np.linalg.norm(forward)
    forward = forward / dist
    right = np.cross(forward, vec(0, 1, 0))
    right /= np.linalg.norm(right)
    up = np.cross(right, forward)

    half_h = VIEW_HEIGHT / 2
    half_w = half_h * COLS * CELL_ASPECT / ROWS
    xs = (np.arange(COLS) + 0.5) / COLS * 2 - 1
    ys = 1 - (np.arange(ROWS) + 0.5) / ROWS * 2
    gx, gy = np.meshgrid(xs * half_w, ys * half_h)
    dirs = forward * dist + gx.reshape(-1, 1) * right + gy.reshape(-1, 1) * up
    dirs /= np.linalg.norm(dirs, axis=1, keepdims=True)

    # March every ray until it hits the cat or leaves the scene.
    t = np.full(len(dirs), 3.0)
    live = np.ones(len(dirs), bool)
    hit = np.zeros(len(dirs), bool)
    for _ in range(64):
        if not live.any():
            break
        d, _, _ = cat(CAM + t[live, None] * dirs[live], P)
        idx = np.where(live)[0]
        t[idx] += d * 0.9
        done = d < 0.004
        hit[idx[done]] = True
        live[idx[done]] = False
        live[idx[t[idx] > 9.0]] = False

    out = np.full(len(dirs), " ", dtype="<U1")

    # The floor: a shadow under the cat that tightens as it hops up.
    with np.errstate(divide="ignore", invalid="ignore"):
        ft = -CAM[1] / dirs[:, 1]
    fp = CAM + ft[:, None] * dirs
    r = np.hypot(fp[:, 0] - P["hip"][0] * 0.6, fp[:, 2]) / (0.95 - 0.25 * P["hop"])
    floor = (ft > 0) & (r < 1.0) & ~hit
    out[floor & (r >= 0.55)] = "."
    out[floor & (r < 0.55)] = ":"

    # Shade the hits.
    idx = np.where(hit)[0]
    if len(idx):
        pts = CAM + t[idx, None] * dirs[idx]
        _, mat, stripe = cat(pts, P)
        e = 0.008
        offs = (vec(1, -1, -1), vec(-1, -1, 1), vec(-1, 1, -1), vec(1, 1, 1))
        n = sum(o[None, :] * cat(pts + e * o, P)[0][:, None] for o in offs)
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
        # The cat turns, the light doesn't, so the shading moves over it as it spins.
        lambert = np.clip(n @ rot_y(LIGHT[None, :], P["yaw"])[0], 0, 1)
        n_world = rot_y(n, -P["yaw"])
        rim = 0.20 * (1 - np.clip(-(n_world * dirs[idx]).sum(axis=1), 0, 1)) ** 2
        v = 0.16 + 0.70 * lambert + rim
        v = np.where(mat == LIGHT_FUR, v * 1.05 + 0.05, v * 0.82)
        v = np.where((mat == FUR) & stripe, v * 0.5, v)
        levels = np.clip((v * len(RAMP)).astype(int), 0, len(RAMP) - 1)
        chars = np.array(list(RAMP))[levels]
        chars[mat == EYE] = " "
        chars[mat == NOSE] = "v"
        out[idx] = chars

    grid = out.reshape(ROWS, COLS)
    return [("".join(row)).rstrip() for row in grid]


def frames():
    total = BEATS * FRAMES_PER_BEAT
    return [render(pose(BEATS * i / total)) for i in range(total)]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--preview", type=int, help="print one frame instead of writing frames.js")
    args = ap.parse_args()
    if args.preview is not None:
        print("\n".join(render(pose(args.preview / FRAMES_PER_BEAT))))
        return
    body = ",\n".join(json.dumps("\n".join(f)) for f in frames())
    out = Path(__file__).with_name("frames.js")
    out.write_text(".pragma library\n// Made by make_frames.py; edit that, not this.\n"
                   f"var perBeat = {FRAMES_PER_BEAT};\nvar frames = [\n{body}\n];\n")
    print(out, out.stat().st_size // 1024, "KB")


if __name__ == "__main__":
    main()
