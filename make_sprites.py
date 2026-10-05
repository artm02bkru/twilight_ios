#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
make_sprites.py — генератор спрайтов персонажей «Сумерки» для игры.

Стиль: полуреалистичная плоская иллюстрация. Пропорции ~7.4 головы,
мягкая светотень вместо контуров, объёмные конечности, пряди волос, черты лица.

Запуск:
    python3 make_sprites.py <output_dir> [sheet.png]
"""

import math
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

SS = 3
SPRITE_W, SPRITE_H = 400, 900
FIG_H = 858.0
BASE_Y = 878.0
LIGHT_ANGLE = 234.0          # свет сверху-слева

_grad_cache = {}


# ----------------------------------------------------------------------------
# Геометрия
# ----------------------------------------------------------------------------

def bez(p0, p1, p2, p3, n=24):
    out = []
    for i in range(n + 1):
        t = i / n
        mt = 1.0 - t
        a, b, c, d = mt ** 3, 3 * mt * mt * t, 3 * mt * t * t, t ** 3
        out.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0],
                    a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return out


def catmull(points, n=18):
    """Сглаженная кривая через опорные точки."""
    pts = [points[0]] + list(points) + [points[-1]]
    out = []
    for i in range(len(pts) - 3):
        p0, p1, p2, p3 = pts[i], pts[i + 1], pts[i + 2], pts[i + 3]
        for j in range(n):
            t = j / n
            t2, t3 = t * t, t * t * t
            x = 0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t +
                       (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 +
                       (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t +
                       (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 +
                       (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            out.append((x, y))
    out.append(points[-1])
    return out


class Path:
    def __init__(self):
        self.subs = []

    def move(self, p):
        self.subs.append([p]); return self

    def line(self, p):
        self.subs[-1].append(p); return self

    def curve(self, c1, c2, p):
        self.subs[-1].extend(bez(self.subs[-1][-1], c1, c2, p)[1:]); return self

    def through(self, points, tension=1.0):
        """Плавная кривая (Catmull-Rom -> кубические Безье) через список точек."""
        pts = [self.subs[-1][-1]] + list(points)
        pts = [pts[0]] + pts + [pts[-1]]
        for i in range(1, len(pts) - 2):
            p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
            c1 = (p1[0] + (p2[0] - p0[0]) / 6.0 * tension, p1[1] + (p2[1] - p0[1]) / 6.0 * tension)
            c2 = (p2[0] - (p3[0] - p1[0]) / 6.0 * tension, p2[1] - (p3[1] - p1[1]) / 6.0 * tension)
            self.curve(c1, c2, p2)
        return self

    def close(self):
        if self.subs[-1][0] != self.subs[-1][-1]:
            self.subs[-1].append(self.subs[-1][0])
        return self

    def flat(self):
        out = []
        for s in self.subs:
            out.extend(s)
        return out

    @staticmethod
    def ellipse(cx, cy, rx, ry):
        p = Path(); k = 0.5523
        p.move((cx, cy - ry))
        p.curve((cx + rx * k, cy - ry), (cx + rx, cy - ry * k), (cx + rx, cy))
        p.curve((cx + rx, cy + ry * k), (cx + rx * k, cy + ry), (cx, cy + ry))
        p.curve((cx - rx * k, cy + ry), (cx - rx, cy + ry * k), (cx - rx, cy))
        p.curve((cx - rx, cy - ry * k), (cx - rx * k, cy - ry), (cx, cy - ry))
        return p.close()


def grad_array(w, h, angle):
    key = (w, h, round(angle, 1))
    if key not in _grad_cache:
        yy, xx = np.mgrid[0:h, 0:w]
        a = math.radians(angle)
        t = xx * math.cos(a) + yy * math.sin(a)
        _grad_cache[key] = ((t - t.min()) / (t.max() - t.min() + 1e-9)).astype(np.float32)
    return _grad_cache[key]


def hexc(c):
    c = c.lstrip('#')
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def shade_of(color, k):
    r, g, b = hexc(color)
    return '#%02X%02X%02X' % (min(255, int(r * k)), min(255, int(g * k)), min(255, int(b * k)))


def mixc(a, b, t):
    ra, ga, ba = hexc(a); rb, gb, bb = hexc(b)
    return '#%02X%02X%02X' % (int(ra + (rb - ra) * t), int(ga + (gb - ga) * t), int(ba + (bb - ba) * t))


# ----------------------------------------------------------------------------
# Полотно
# ----------------------------------------------------------------------------

class Canvas:
    def __init__(self):
        self.W = SPRITE_W * SS
        self.H = SPRITE_H * SS
        self.img = Image.new('RGBA', (self.W, self.H), (0, 0, 0, 0))

    def px(self, p):
        return (self.W * 0.5 + p[0] * FIG_H * SS, (BASE_Y - p[1] * FIG_H) * SS)

    def _poly_mask(self, pts, blur=0.0, offset=(0.0, 0.0)):
        m = Image.new('L', (self.W, self.H), 0)
        d = ImageDraw.Draw(m)
        d.polygon([self.px((x + offset[0], y + offset[1])) for x, y in pts], fill=255)
        if blur > 0:
            m = m.filter(ImageFilter.GaussianBlur(blur * FIG_H * SS))
        return m

    def _stamp_mask(self, joints, radii, blur=0.0):
        m = Image.new('L', (self.W, self.H), 0)
        d = ImageDraw.Draw(m)
        for (x, y), r in zip(joints, radii):
            cx, cy = self.px((x, y))
            rr = max(1.0, r * FIG_H * SS)
            d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=255)
        if blur > 0:
            m = m.filter(ImageFilter.GaussianBlur(blur * FIG_H * SS))
        return m

    def _paint(self, mask, light, dark, angle):
        t = grad_array(self.W, self.H, angle)[..., None]
        la = np.array(hexc(light), np.float32)[None, None, :]
        da = np.array(hexc(dark), np.float32)[None, None, :]
        layer = Image.fromarray((da * (1 - t) + la * t).astype(np.uint8), 'RGB').convert('RGBA')
        layer.putalpha(mask)
        self.img = Image.alpha_composite(self.img, layer)

    # --- публичные примитивы ------------------------------------------------
    def shape(self, path, light, dark, angle=LIGHT_ANGLE, blur=0.0):
        self._paint(self._poly_mask(path.flat(), blur), light, dark, angle)

    def flat(self, path, color, alpha=1.0, blur=0.0):
        m = self._poly_mask(path.flat(), blur)
        if alpha < 1.0:
            m = m.point(lambda v: int(v * alpha))
        self._paint(m, color, color, 270)

    def limb(self, joints, radii, light, dark, angle=LIGHT_ANGLE, blur=0.003):
        sm = catmull(joints, 16)
        rr = []
        n = len(sm) - 1
        for i in range(len(sm)):
            u = i / n * (len(radii) - 1)
            i0 = min(int(u), len(radii) - 2)
            f = u - i0
            rr.append(radii[i0] * (1 - f) + radii[i0 + 1] * f)
        self._paint(self._stamp_mask(sm, rr, blur), light, dark, angle)

    def darken(self, mask, color, alpha, blur=0.006):
        if alpha <= 0:
            return
        m = mask.filter(ImageFilter.GaussianBlur(blur * FIG_H * SS)).point(lambda v: int(v * alpha))
        layer = Image.new('RGBA', (self.W, self.H), hexc(color) + (255,))
        layer.putalpha(m)
        self.img = Image.alpha_composite(self.img, layer)

    def circle_shade(self, cx, cy, rx, ry, color, alpha, blur=0.010):
        self.darken(self._poly_mask(Path.ellipse(cx, cy, rx, ry).flat(), 0), color, alpha, blur)

    def edge_shadow(self, path, dx, dy, color, alpha, blur=0.010):
        """Серп вдоль края фигуры — даёт объём без «пятен»."""
        base = self._poly_mask(path.flat(), 0)
        shifted = self._poly_mask(path.flat(), 0, offset=(dx, dy))
        crescent = ImageChops.multiply(ImageChops.subtract(base, shifted), base)
        self.darken(crescent, color, alpha, blur)

    def edge_light(self, path, dx, dy, color, alpha, blur=0.012):
        base = self._poly_mask(path.flat(), 0)
        shifted = self._poly_mask(path.flat(), 0, offset=(dx, dy))
        crescent = ImageChops.multiply(ImageChops.subtract(base, shifted), base)
        m = crescent.filter(ImageFilter.GaussianBlur(blur * FIG_H * SS)).point(lambda v: int(v * alpha))
        layer = Image.new('RGBA', (self.W, self.H), hexc(color) + (255,))
        layer.putalpha(m)
        self.img = Image.alpha_composite(self.img, layer)

    def stroke(self, pts, width, color, alpha=1.0, taper=True):
        sm = catmull(pts, 14)
        n = len(sm) - 1
        radii = []
        for i in range(len(sm)):
            t = i / n
            k = math.sin(math.pi * t) ** 0.45 if taper else 1.0
            radii.append(width * (0.35 + 0.65 * k))
        mask = self._stamp_mask(sm, radii, 0.0015)
        self.darken(mask, color, alpha, 0.0015)

    def result(self):
        return self.img.resize((SPRITE_W, SPRITE_H), Image.LANCZOS)


# ----------------------------------------------------------------------------
# Пропорции и позы
# ----------------------------------------------------------------------------

LM = dict(ankle=0.052, knee=0.290, hip=0.495, waist=0.600, chest=0.706,
          shoulder=0.782, neck=0.800, chin=0.862, top=1.0)

HEAD_HW = 0.0535


def body_metrics(cfg):
    male = cfg.get('sex', 'm') == 'm'
    shw = cfg.get('shoulder', 0.113 if male else 0.097)
    wsw = cfg.get('waist', 0.081 if male else 0.067)
    hpw = cfg.get('hip', 0.090 if male else 0.095)
    return shw, wsw, hpw


def leg_joints(cfg, side, stance=1.0):
    hpw = body_metrics(cfg)[2]
    x0 = side * hpw * 0.44 * stance
    x1 = side * hpw * 0.52 * stance
    x2 = side * hpw * 0.50 * stance
    return [(x0, LM['hip'] + 0.012), (x1, LM['knee']), (x2, LM['ankle'])]


def arm_joints(cfg, side, pose):
    shw = body_metrics(cfg)[0]
    hpw = body_metrics(cfg)[2]
    sx = side * shw * 0.86
    sy = LM['shoulder'] - 0.010

    if pose == 'stand':
        return [(sx, sy),
                (side * (shw + 0.012), 0.672),
                (side * (hpw + 0.016), 0.556),
                (side * (hpw + 0.012), 0.508)]
    if pose == 'reach':
        # правая рука выброшена вперёд (остановить фургон / поймать мяч)
        if side > 0:
            return [(sx, sy), (shw + 0.042, 0.790), (shw + 0.084, 0.812), (shw + 0.122, 0.816)]
        return [(sx, sy),
                (side * (shw + 0.012), 0.676),
                (side * (hpw + 0.016), 0.560),
                (side * (hpw + 0.012), 0.512)]
    if pose == 'bat':
        # обе руки сведены перед собой — держат биту
        return [(sx, sy),
                (side * (shw + 0.006), 0.716),
                (side * (shw - 0.008), 0.660),
                (side * 0.028, 0.646)]
    if pose == 'pitch':
        # замах Алисы: правая рука вверх, левая впереди
        if side > 0:
            return [(sx, sy), (shw + 0.020, 0.842), (shw + 0.030, 0.900), (shw + 0.026, 0.946)]
        return [(sx, sy), (side * (shw + 0.014), 0.744), (side * (shw + 0.010), 0.858), (side * 0.030, 0.878)]
    if pose == 'kneel':
        if side > 0:
            return [(sx, sy), (shw + 0.030, 0.700), (shw + 0.048, 0.630), (shw + 0.050, 0.572)]
        return [(sx, sy), (side * (shw + 0.010), 0.690), (side * (shw + 0.006), 0.600), (side * 0.030, 0.560)]
    return arm_joints(cfg, side, 'stand')


# ----------------------------------------------------------------------------
# Фигура
# ----------------------------------------------------------------------------

def draw_figure(cfg):
    c = Canvas()
    pose = cfg.get('pose', 'stand')
    male = cfg.get('sex', 'm') == 'm'
    shw, wsw, hpw = body_metrics(cfg)

    skin_l, skin_d = cfg['skin']
    hair_l, hair_d = cfg['hair']
    top_l, top_d = cfg['top']
    if 'sleeve' in cfg:
        slv_l, slv_d = cfg['sleeve']
    else:
        slv_l, slv_d = shade_of(top_l, 0.87), shade_of(top_d, 0.76)
    leg_l, leg_d = cfg['legs']
    shoe_l, shoe_d = cfg['shoes']
    trim = cfg.get('trim')
    crouch = cfg.get('crouch', 0.0)

    def dy(y):
        return y - crouch

    # ---------- 1. ВОЛОСЫ СЗАДИ ----------
    mass = build_hair_mass(cfg)
    if mass is not None:
        c.shape(mass, hair_d, shade_of(hair_d, 0.66), angle=250)

    # ---------- 2. НОГИ ----------
    for side in (-1, 1):
        j = [(x, dy(y)) for x, y in leg_joints(cfg, side, cfg.get('stance', 1.0))]
        rr = [0.046, 0.036, 0.026] if male else [0.044, 0.032, 0.022]
        if pose == 'kneel':
            j = [(x * 0.9, dy(y)) for x, y in j]
            j[1] = (j[1][0], j[1][1] - 0.06)
        if cfg.get('shorts'):
            c.limb(j, rr, leg_l, leg_d)
            upper = catmull(j, 12)[:len(catmull(j, 12)) // 2 + 2]
            m = c._stamp_mask(upper, [rr[0]] * len(upper), 0.003)
            c._paint(m, leg_l, leg_d, 245)
            lower = catmull(j, 12)[len(catmull(j, 12)) // 2:]
            rr2 = [rr[1] + (rr[2] - rr[1]) * (i / max(1, len(lower) - 1)) for i in range(len(lower))]
            m2 = c._stamp_mask(lower, rr2, 0.003)
            c._paint(m2, skin_l, skin_d, 245)
        else:
            c.limb(j, rr, leg_l, leg_d)
        # объём: тень по правому краю бедра
        jj = catmull(j, 12)
        c.circle_shade(jj[len(jj) // 3][0] * 0.55, jj[len(jj) // 3][1], 0.030, 0.075,
                       leg_d, 0.22 if male else 0.18, 0.020)

    c.stroke([(0.0, dy(0.500)), (0.0, dy(0.360)), (0.0, dy(0.210)), (0.0, dy(0.090))],
             0.007, shade_of(leg_d, 0.72), 0.32)
    for side in (-1, 1):
        jj = catmull([(x, dy(y)) for x, y in leg_joints(cfg, side, cfg.get('stance', 1.0))], 14)
        c.stroke([(x + side * 0.040, y) for x, y in jj[::max(1, len(jj) // 5)]],
                 0.005, shade_of(leg_d, 0.80), 0.22)

    # ---------- 3. ОБУВЬ ----------
    for side in (-1, 1):
        j = leg_joints(cfg, side, cfg.get('stance', 1.0))
        ax, ay = j[2][0], dy(j[2][1])
        p = Path()
        p.move((ax - 0.024, ay + 0.004))
        p.curve((ax - 0.026, ay - 0.028), (ax - 0.010, ay - 0.040), (ax + 0.014, ay - 0.040))
        p.curve((ax + 0.034, ay - 0.040), (ax + 0.042, ay - 0.020), (ax + 0.040, ay + 0.004))
        p.close()
        c.shape(p, shoe_l, shoe_d, angle=250)
        c.circle_shade(ax + 0.020, ay - 0.034, 0.018, 0.010, '#000000', 0.28, 0.005)

    # ---------- 4. ТОРС ----------
    torso = Path()
    torso.move((-shw, dy(LM['shoulder'])))
    torso.curve((-shw * 0.98, dy(0.726)), (-wsw - 0.004, dy(0.662)), (-wsw, dy(LM['waist'])))
    torso.curve((-wsw + 0.002, dy(0.548)), (-hpw, dy(0.522)), (-hpw, dy(LM['hip'] + 0.012)))
    torso.line((hpw, dy(LM['hip'] + 0.012)))
    torso.curve((hpw, dy(0.522)), (wsw - 0.002, dy(0.548)), (wsw, dy(LM['waist'])))
    torso.curve((wsw + 0.004, dy(0.662)), (shw * 0.98, dy(0.726)), (shw, dy(LM['shoulder'])))
    # линия плеч с наклоном к шее
    torso.curve((shw * 0.62, dy(0.802)), (shw * 0.26, dy(0.812)), (0.0, dy(0.810)))
    torso.curve((-shw * 0.26, dy(0.812)), (-shw * 0.62, dy(0.802)), (-shw, dy(LM['shoulder'])))
    torso.close()
    c.shape(torso, top_l, top_d, angle=240)
    c.edge_shadow(torso, -0.012, -0.008, top_d, 0.55, 0.012)
    c.edge_light(torso, 0.013, 0.007, '#FFFFFF', 0.11, 0.009)

    # грудь / складки
    if not male:
        c.circle_shade(-shw * 0.42, dy(0.712), 0.030, 0.028, top_d, 0.20, 0.022)
        c.circle_shade(shw * 0.42, dy(0.712), 0.030, 0.028, top_d, 0.30, 0.022)
        c.circle_shade(0.0, dy(0.700), 0.010, 0.040, top_d, 0.16, 0.016)
    c.circle_shade(0.0, dy(0.578), wsw * 0.75, 0.030, top_d, 0.22, 0.018)
    c.stroke([(-wsw * 0.7, dy(0.575)), (0.0, dy(0.588)), (wsw * 0.7, dy(0.575))], 0.004, top_d, 0.35)

    if trim:
        band = Path()
        band.move((-shw * 0.90, dy(0.748)))
        band.curve((0.0, dy(0.772)), (0.0, dy(0.772)), (shw * 0.90, dy(0.748)))
        band.line((shw * 0.88, dy(0.720)))
        band.curve((0.0, dy(0.744)), (0.0, dy(0.744)), (-shw * 0.88, dy(0.720)))
        band.close()
        c.shape(band, trim, shade_of(trim, 0.78), angle=250)

    # ---------- 5. РУКИ ----------
    for side in (-1, 1):
        j = [(x, dy(y)) for x, y in arm_joints(cfg, side, pose)]
        if cfg.get('shorts'):
            c.limb(j, [0.036, 0.030, 0.024, 0.020], slv_l, slv_d)
            sm = catmull(j, 16)
            half = sm[len(sm) // 2:]
            rr2 = [0.024 + (0.020 - 0.024) * (i / max(1, len(half) - 1)) for i in range(len(half))]
            c._paint(c._stamp_mask(half, rr2, 0.003), skin_l, skin_d, 245)
        else:
            c.limb(j, [0.036, 0.030, 0.025, 0.021], slv_l, slv_d)
        # кисть
        hand = j[-1]
        c.shape(Path.ellipse(hand[0] + side * 0.004, hand[1] - 0.012, 0.016, 0.024),
                skin_l, skin_d, angle=246)

    # ---------- 6. ШЕЯ ----------
    neck = Path()
    neck.move((-0.024, dy(0.796)))
    neck.curve((-0.022, dy(0.840)), (-0.024, dy(0.868)), (-0.022, dy(0.876)))
    neck.line((0.022, dy(0.876)))
    neck.curve((0.024, dy(0.868)), (0.022, dy(0.840)), (0.024, dy(0.796)))
    neck.close()
    c.shape(neck, skin_l, skin_d, angle=248)
    c.circle_shade(0.0, dy(0.870), 0.040, 0.024, mixc(skin_d, '#8A6350', 0.5), 0.60, 0.010)

    # ---------- 7. ГОЛОВА ----------
    head = head_path()
    head_t = Path()
    head_t.subs = [[(x, dy(y)) for x, y in sp] for sp in head.subs]
    c.shape(head_t, skin_l, skin_d, angle=248)
    c.edge_shadow(head_t, -0.010, -0.006, skin_d, 0.45, 0.012)
    c.edge_light(head_t, 0.012, 0.006, '#FFFFFF', 0.13, 0.008)
    c.circle_shade(0.036, dy(0.905), 0.020, 0.036, skin_d, 0.35, 0.016)
    c.circle_shade(-0.040, dy(0.890), 0.014, 0.026, skin_d, 0.18, 0.016)
    for side in (-1, 1):
        c.shape(Path.ellipse(side * HEAD_HW * 0.97, dy(0.9090), 0.0068, 0.0128), skin_l, skin_d, angle=250)
        c.circle_shade(side * HEAD_HW * 0.97, dy(0.9090), 0.0032, 0.0062, '#8A6350', 0.30, 0.004)

    # ---------- 8. ВОЛОСЫ СПЕРЕДИ + ПРЯДИ ----------
    for side in (-1, 1):
        lock = build_hair_lock(cfg, side)
        if lock is not None:
            lock_t = Path()
            lock_t.subs = [[(x, dy(y)) for x, y in sp] for sp in lock.subs]
            c.shape(lock_t, hair_l, hair_d, angle=246)
            c.edge_shadow(lock_t, -side * 0.010, 0.0, hair_d, 0.40, 0.010)

    front = build_hair_front(cfg)
    if front is not None:
        front_t = Path()
        front_t.subs = [[(x, dy(y)) for x, y in sp] for sp in front.subs]
        c.shape(front_t, hair_l, hair_d, angle=244)
        c.edge_shadow(front_t, 0.010, 0.006, hair_d, 0.45, 0.010)
        c.circle_shade(cfg.get('hl_x', -0.026), dy(0.962), 0.024, 0.016, '#FFFFFF', 0.26, 0.012)

    # ---------- 9. ЛИЦО ----------
    draw_face(c, cfg, dy)

    # ---------- 10. ОБЩИЙ СВЕТ ПО СИЛУЭТУ ----------
    alpha = c.img.getchannel('A')
    t = grad_array(c.W, c.H, 240)[..., None]
    la = np.array([255, 250, 245], np.float32)[None, None, :]
    da = np.array([28, 24, 34], np.float32)[None, None, :]
    glow = Image.fromarray((da * (1 - t) + la * t).astype(np.uint8), 'RGB').convert('RGBA')
    glow.putalpha(alpha.point(lambda v: int(v * 0.16)))
    c.img = Image.alpha_composite(c.img, glow)

    return c.result()


def head_path():
    hw = HEAD_HW
    p = Path()
    p.move((0.0, 1.0))
    p.curve((hw * 0.82, 1.0), (hw, 0.968), (hw, 0.922))
    p.curve((hw, 0.896), (hw * 0.86, 0.874), (hw * 0.56, 0.868))
    p.curve((hw * 0.34, 0.863), (hw * 0.16, 0.862), (0.0, 0.862))
    p.curve((-hw * 0.16, 0.862), (-hw * 0.34, 0.863), (-hw * 0.56, 0.868))
    p.curve((-hw * 0.86, 0.874), (-hw, 0.896), (-hw, 0.922))
    p.curve((-hw, 0.968), (-hw * 0.82, 1.0), (0.0, 1.0))
    return p.close()


# ----------------------------------------------------------------------------
# Волосы
# ----------------------------------------------------------------------------

HAIR_PROFILE = {
    #                низ    ширина  объём  волна
    'long_straight': (0.480, 0.118, 0.010, 0.000),
    'long_wavy':     (0.500, 0.124, 0.012, 0.012),
    'shoulder':      (0.660, 0.118, 0.008, 0.005),
    'long_slick':    (0.585, 0.112, 0.006, 0.000),
    'short_spiky':   (0.895, 0.078, 0.010, 0.000),
    'short_curly':   (0.900, 0.082, 0.014, 0.000),
    'messy_short':   (0.898, 0.078, 0.012, 0.000),
}


def build_hair_mass(cfg):
    style = cfg['hair_style']
    length, wdt, vol, wave = HAIR_PROFILE[style]
    if length > 0.86:
        return None
    top = 1.0 + vol
    p = Path()
    p.move((0.0, top))
    p.curve((wdt * 0.80, top), (wdt, 0.972), (wdt, 0.925))
    if wave > 0:
        steps = 7
        dy = (0.925 - length) / steps
        y = 0.925
        for i in range(steps):
            k = i / steps
            x0 = wdt * (1.0 + 0.10 * math.sin(i * 1.9))
            x1 = wdt * (1.0 + 0.10 * math.sin((i + 1) * 1.9))
            p.curve((x0, y - dy * 0.30), (x1, y - dy * 0.70), (wdt * (0.70 + 0.06 * k), y - dy))
            y -= dy
    else:
        p.curve((wdt * 1.04, 0.840), (wdt * 0.94, length + 0.080), (wdt * 0.66, length))
    p.curve((wdt * 0.26, length - 0.034), (-wdt * 0.26, length - 0.034), (-wdt * 0.66, length))
    if wave > 0:
        steps = 7
        dy = (0.925 - length) / steps
        y = length
        for i in range(steps):
            k = (i + 1) / steps
            x0 = -wdt * (0.70 + 0.34 * (i / steps))
            x1 = -wdt * (0.70 + 0.34 * ((i + 1) / steps))
            p.curve((x0, y + dy * 0.30), (x1, y + dy * 0.70),
                    (-wdt * (1.0 + 0.10 * math.sin((i + 1) * 1.9)), y + dy))
            y += dy
        p.curve((-wdt * 1.04, 0.900), (-wdt, 0.955), (-wdt, 0.925))
    else:
        p.curve((-wdt * 0.94, length + 0.080), (-wdt * 1.04, 0.840), (-wdt, 0.925))
    p.curve((-wdt, 0.972), (-wdt * 0.80, top), (0.0, top))
    return p.close()


def build_hair_lock(cfg, side):
    """Прядь, падающая впереди плеча."""
    style = cfg['hair_style']
    if style in ('short_spiky', 'short_curly', 'messy_short'):
        return None
    length, wdt, vol, wave = HAIR_PROFILE[style]
    x = side * wdt * 0.80
    p = Path()
    p.move((x - side * 0.026, 0.905))
    p.curve((x + side * 0.020, 0.830), (x + side * 0.026, 0.740), (x + side * 0.012, length + 0.055))
    if wave > 0:
        y = length + 0.055
        for i in range(4):
            p.curve((x + side * (0.026 if i % 2 == 0 else 0.004), y - 0.026),
                    (x - side * (0.012 if i % 2 == 0 else 0.030), y - 0.040),
                    (x + side * (0.010 if i % 2 == 0 else -0.004), y - 0.052))
            y -= 0.052
    else:
        p.curve((x + side * 0.030, length + 0.010), (x + side * 0.018, length - 0.010), (x - side * 0.006, length - 0.006))
    p.curve((x - side * 0.024, length + 0.070), (x - side * 0.034, 0.820), (x - side * 0.026, 0.905))
    return p.close()


def build_hair_front(cfg):
    style = cfg['hair_style']
    hw = HEAD_HW
    p = Path()

    if style in ('long_straight', 'long_wavy', 'shoulder', 'long_slick'):
        p.move((-hw * 1.06, 0.916))
        p.curve((-hw * 1.08, 0.980), (-hw * 0.86, 1.016), (0.0, 1.018))
        p.curve((hw * 0.86, 1.016), (hw * 1.08, 0.980), (hw * 1.06, 0.914))
        p.line((hw * 0.98, 0.920))
        p.through([(hw * 0.92, 0.936), (hw * 0.58, 0.956), (hw * 0.18, 0.960),
                   (-hw * 0.22, 0.958), (-hw * 0.68, 0.940), (-hw * 0.98, 0.912)])
        p.close()
    elif style == 'short_spiky':
        p.move((-hw * 1.06, 0.928))
        p.curve((-hw * 1.08, 0.986), (-hw * 0.86, 1.018), (0.0, 1.020))
        p.curve((hw * 0.86, 1.018), (hw * 1.08, 0.986), (hw * 1.06, 0.928))
        p.line((hw * 0.98, 0.932))
        p.through([(hw * 0.92, 0.950), (hw * 0.72, 0.938), (hw * 0.52, 0.952),
                   (hw * 0.30, 0.940), (hw * 0.06, 0.954), (-hw * 0.18, 0.940),
                   (-hw * 0.40, 0.952), (-hw * 0.64, 0.938), (-hw * 0.88, 0.948)])
        p.close()
    elif style == 'short_curly':
        p.move((-hw * 1.08, 0.930))
        p.curve((-hw * 1.04, 0.992), (-hw * 0.70, 1.030), (0.0, 1.030))
        p.curve((hw * 0.70, 1.030), (hw * 1.04, 0.992), (hw * 1.08, 0.930))
        p.line((hw * 0.98, 0.936))
        p.through([(hw * 0.92, 0.954), (hw * 0.72, 0.940), (hw * 0.50, 0.956),
                   (hw * 0.26, 0.942), (hw * 0.0, 0.958), (-hw * 0.26, 0.942),
                   (-hw * 0.50, 0.956), (-hw * 0.74, 0.940), (-hw * 0.94, 0.950)])
        p.close()
    else:  # messy_short — косая взлохмаченная чёлка
        p.move((-hw * 1.06, 0.922))
        p.curve((-hw * 1.08, 0.992), (-hw * 0.82, 1.024), (0.0, 1.024))
        p.curve((hw * 0.84, 1.024), (hw * 1.12, 0.988), (hw * 1.08, 0.918))
        p.line((hw * 0.98, 0.926))
        p.through([(hw * 0.94, 0.956), (hw * 0.76, 0.932), (hw * 0.56, 0.958),
                   (hw * 0.36, 0.930), (hw * 0.16, 0.954), (-hw * 0.06, 0.928),
                   (-hw * 0.30, 0.952), (-hw * 0.54, 0.930), (-hw * 0.78, 0.950),
                   (-hw * 0.98, 0.934)])
        p.close()
    return p


# ----------------------------------------------------------------------------
# Лицо
# ----------------------------------------------------------------------------

def draw_face(c, cfg, dy):
    skin_l, skin_d = cfg['skin']
    brow_c = shade_of(cfg['hair'][1], 0.80)
    lip = cfg.get('lips', '#B4736B')
    eye_color = cfg['eye']

    eye_y = dy(0.9290)
    eye_dx = 0.0245

    # очень мягкая тень у линии роста волос
    c.circle_shade(0.0, dy(0.9740), 0.050, 0.011, mixc(skin_d, '#9A7A68', 0.4), 0.16, 0.012)

    for side in (-1, 1):
        ecx = side * eye_dx

        # глазница — лёгкая, без «очков»
        c.circle_shade(ecx, eye_y + 0.0030, 0.0158, 0.0092, mixc(skin_d, '#7A5A4A', 0.30), 0.26, 0.009)
        # белок
        c.shape(Path.ellipse(ecx, eye_y, 0.0126, 0.0064), '#FDFAF8', '#E0D7D0', angle=255, blur=0.0012)
        # радужка крупная — так взгляд читается живее
        c.shape(Path.ellipse(ecx, eye_y - 0.0002, 0.0064, 0.0064), eye_color,
                shade_of(eye_color, 0.40), angle=250, blur=0.0010)
        c.flat(Path.ellipse(ecx, eye_y - 0.0003, 0.0027, 0.0027), '#160F0A', blur=0.0008)
        c.flat(Path.ellipse(ecx - side * 0.0019, eye_y - 0.0024, 0.0014, 0.0014), '#FFFFFF', 0.90, 0.0007)
        # верхнее веко
        lid = Path()
        lid.move((ecx - 0.0128, eye_y + 0.0014))
        lid.curve((ecx - 0.006, eye_y - 0.0098), (ecx + 0.006, eye_y - 0.0098), (ecx + 0.0128, eye_y + 0.0014))
        c.stroke(lid.flat(), 0.0017, '#5A4038', 0.60)
        # внешний уголок и ресницы
        c.stroke([(ecx + side * 0.0082, eye_y - 0.0052), (ecx + side * 0.0138, eye_y - 0.0084)],
                 0.0011, '#4A322A', 0.50)
        # нижнее веко — тонкая светлая линия
        c.stroke([(ecx - 0.0100, eye_y + 0.0076), (ecx + 0.0100, eye_y + 0.0076)],
                 0.0009, '#FFFFFF', 0.22)
        # бровь: мягкая дуга, внутренний конец ниже
        b = Path()
        b.move((ecx - side * 0.0148, eye_y + 0.0182))
        b.curve((ecx - side * 0.004, eye_y + 0.0244), (ecx + side * 0.008, eye_y + 0.0238),
                (ecx + side * 0.0164, eye_y + 0.0156))
        c.stroke(b.flat(), 0.0023, brow_c, 0.66)

    # нос: только мягкая тень сбоку и лёгкая тень на кончике
    c.circle_shade(0.0046, dy(0.9065), 0.0050, 0.0090, mixc(skin_d, '#8A6350', 0.30), 0.28, 0.007)
    c.circle_shade(-0.0042, dy(0.8975), 0.0020, 0.0016, '#8A6350', 0.22, 0.004)
    c.circle_shade(0.0, dy(0.9020), 0.0090, 0.0030, '#FFFFFF', 0.10, 0.008)

    # губы
    c.shape(Path.ellipse(0.0, dy(0.8848), 0.0112, 0.0028), lip, shade_of(lip, 0.62), angle=255, blur=0.0012)
    c.shape(Path.ellipse(0.0, dy(0.8806), 0.0096, 0.0034), shade_of(lip, 1.06), shade_of(lip, 0.74), angle=255, blur=0.0012)
    c.stroke([(-0.0112, dy(0.8848)), (0.0, dy(0.8858)), (0.0112, dy(0.8848))], 0.0009, shade_of(lip, 0.54), 0.55)

    # румянец
    for side in (-1, 1):
        c.circle_shade(side * 0.0315, dy(0.9000), 0.0130, 0.0078, '#D98C7A', 0.13, 0.011)


# ----------------------------------------------------------------------------
# Фургон и финальная сцена
# ----------------------------------------------------------------------------

def draw_van():
    W, H = 640, 340
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    bd = ImageDraw.Draw(img)
    body = (104, 78, 64)
    bd.rounded_rectangle([30, 44, 606, 252], radius=26, fill=body + (255,))
    bd.rounded_rectangle([30, 26, 306, 74], radius=18, fill=body + (255,))
    bd.rounded_rectangle([46, 48, 152, 132], radius=10, fill=(56, 72, 84, 255))
    bd.rounded_rectangle([166, 48, 272, 132], radius=10, fill=(56, 72, 84, 255))
    bd.rounded_rectangle([332, 58, 434, 130], radius=8, fill=(56, 72, 84, 255))
    bd.rounded_rectangle([448, 58, 550, 130], radius=8, fill=(56, 72, 84, 255))
    bd.rounded_rectangle([20, 170, 44, 236], radius=8, fill=(62, 60, 58, 255))
    bd.rounded_rectangle([24, 140, 44, 172], radius=6, fill=(240, 230, 186, 255))
    bd.rounded_rectangle([24, 234, 44, 254], radius=6, fill=(224, 152, 72, 255))
    bd.rectangle([30, 238, 606, 260], fill=(60, 50, 44, 255))
    for cx in (132, 486):
        bd.ellipse([cx - 56, 220, cx + 56, 332], fill=(30, 28, 28, 255))
        bd.ellipse([cx - 32, 244, cx + 32, 308], fill=(128, 130, 134, 255))
        bd.ellipse([cx - 15, 261, cx + 15, 291], fill=(72, 74, 78, 255))
    # объём
    t = grad_array(W, H, 236)[..., None]
    la = np.array([162, 132, 112], np.float32)[None, None, :]
    da = np.array([44, 32, 26], np.float32)[None, None, :]
    gimg = Image.fromarray((da * (1 - t) + la * t).astype(np.uint8), 'RGB').convert('RGBA')
    gimg.putalpha(img.getchannel('A').point(lambda v: int(v * 0.40)))
    return Image.alpha_composite(img, gimg)


def _stamp_limb(img, joints, radii, color):
    d = ImageDraw.Draw(img)
    for (x, y), r in zip(joints, radii):
        d.ellipse([x - r, y - r, x + r, y + r], fill=color)


def _capsule(size, center, length, width, angle_deg, color):
    """Закруглённая «капсула» — из них собираем пальцы."""
    layer = Image.new('RGBA', size, (0, 0, 0, 0))
    L = max(2.0, length)
    wd = max(2.0, width)
    tmp = Image.new('RGBA', (int(L) + 8, int(wd) + 8), (0, 0, 0, 0))
    ImageDraw.Draw(tmp).rounded_rectangle([4, 4, int(L) + 4, int(wd) + 4],
                                          radius=wd / 2.0, fill=color)
    tmp = tmp.rotate(angle_deg, expand=True, resample=Image.BICUBIC)
    layer.paste(tmp, (int(center[0] - tmp.width / 2.0), int(center[1] - tmp.height / 2.0)), tmp)
    return layer


def draw_wound():
    """Рука Эдварда сжимает запястье Беллы: следы укуса и потёки крови."""
    W, H, S = 1000, 520, 2
    w2, h2 = W * S, H * S
    img = Image.new('RGBA', (w2, h2), (0, 0, 0, 0))

    # ---- предплечье по диагонали ----
    arm = Image.new('RGBA', (w2, h2), (0, 0, 0, 0))
    n = 90
    pts, rr = [], []
    for i in range(n + 1):
        t = i / n
        x = -70 + t * (W + 140)
        y = 396 - t * 188
        r = 94 - 24 * math.sin(t * math.pi)
        pts.append((x * S, y * S))
        rr.append(r * S)
    _stamp_limb(arm, pts, rr, (240, 216, 204, 255))
    img = Image.alpha_composite(img, arm)

    # объём предплечья
    g = grad_array(w2, h2, 246)
    rgb = (np.array([168, 130, 116], np.float32)[None, None, :] * (1 - g[..., None])
           + np.array([253, 240, 232], np.float32)[None, None, :] * g[..., None]).astype(np.uint8)
    gl = Image.fromarray(rgb, 'RGB').convert('RGBA')
    gl.putalpha(img.getchannel('A').point(lambda v: int(v * 0.60)))
    img = Image.alpha_composite(img, gl)

    # ---- следы укуса: два полукруга, вытянутых вдоль руки ----
    bite = Image.new('RGBA', (w2, h2), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bite)
    bcx, bcy = 636, 268
    for ring, (rrx, rry, count, rad, col) in enumerate((
            (94, 64, 10, 18, (118, 18, 26, 255)),
            (62, 42, 8, 13, (146, 26, 34, 255)))):
        for i in range(count):
            a = -math.pi * 0.72 + i * (math.pi * 1.44 / max(1, count - 1))
            bx = (bcx + math.cos(a) * rrx) * S
            by = (bcy + math.sin(a) * rry + 14) * S
            r = rad * S
            bd.ellipse([bx - r, by - r, bx + r, by + r], fill=col)
    bite = bite.filter(ImageFilter.GaussianBlur(1.1 * S))
    img = Image.alpha_composite(img, bite)

    # потёки крови вниз — вытянутые струйки
    drip = Image.new('RGBA', (w2, h2), (0, 0, 0, 0))
    for dx, dy, length, width, tone in ((586, 300, 130, 18, 210), (626, 316, 172, 22, 235),
                                        (664, 302, 116, 15, 200), (700, 316, 84, 12, 185),
                                        (604, 320, 78, 13, 190)):
        drip = Image.alpha_composite(drip, _capsule(
            (w2, h2), (dx * S, (dy + length * 0.5) * S), length * S, width * S, 88,
            (136, 22, 30, tone)))
        drip = Image.alpha_composite(drip, _capsule(
            (w2, h2), (dx * S, (dy + length + width * 0.4) * S), width * 1.5 * S, width * 1.5 * S, 0,
            (150, 26, 34, tone)))
    drip = drip.filter(ImageFilter.GaussianBlur(0.8 * S))
    img = Image.alpha_composite(img, drip)

    # ---- кисть Эдварда: четыре пальца обхватывают руку ----
    hand = Image.new('RGBA', (w2, h2), (0, 0, 0, 0))
    grip_x = 384
    for k in range(4):
        fx = grip_x + k * 52
        fy = 268 + k * 6
        length = (196 - k * 10) * S
        width = 46 * S
        angle = -84 + k * 2.0
        hand = Image.alpha_composite(hand, _capsule(
            (w2, h2), (fx * S, fy * S), length, width, angle, (245, 230, 222, 255)))
    # большой палец снизу
    hand = Image.alpha_composite(hand, _capsule(
        (w2, h2), (520 * S, 402 * S), 150 * S, 52 * S, 26, (242, 226, 218, 255)))
    # тыльная сторона ладони
    hand = Image.alpha_composite(hand, _capsule(
        (w2, h2), (386 * S, 236 * S), 128 * S, 150 * S, -6, (246, 232, 224, 255)))
    img = Image.alpha_composite(img, hand)

    # объём кисти
    g2 = grad_array(w2, h2, 244)
    rgb2 = (np.array([182, 152, 140], np.float32)[None, None, :] * (1 - g2[..., None])
            + np.array([255, 248, 243], np.float32)[None, None, :] * g2[..., None]).astype(np.uint8)
    gl2 = Image.fromarray(rgb2, 'RGB').convert('RGBA')
    mask = Image.new('L', (w2, h2), 0)
    ImageDraw.Draw(mask).rounded_rectangle([(grip_x - 60) * S, 160 * S, 700 * S, 470 * S],
                                           radius=90 * S, fill=115)
    gl2.putalpha(mask)
    img = Image.alpha_composite(img, gl2)

    # ---- тёмный рукав Эдварда сверху ----
    sleeve = Image.new('RGBA', (w2, h2), (0, 0, 0, 0))
    sp, sr = [], []
    for i in range(31):
        t = i / 30.0
        sp.append(((-120 + t * 430) * S, (-70 + t * 300) * S))
        sr.append((112 - t * 34) * S)
    _stamp_limb(sleeve, sp, sr, (44, 48, 56, 255))
    img = Image.alpha_composite(img, sleeve)

    return img.resize((W, H), Image.LANCZOS)


def noise_py(i, salt=0):
    x = math.sin(i * 12.9898 + salt * 78.233) * 43758.5453
    return x - math.floor(x)


# ----------------------------------------------------------------------------
# Персонажи
# ----------------------------------------------------------------------------

PALE = ('#F1DFD5', '#C4A190')
PALER = ('#F6E9E2', '#CDAF9F')
WARM = ('#EEDACB', '#BF9781')
TAN = ('#E2C4A8', '#B08159')

UNIFORM = dict(top=('#F2F2EF', '#C7C7C2'), sleeve=('#2E3D5C', '#161F30'),
               trim='#2E3D5C', legs=('#EFEFEC', '#C2C2BD'), shoes=('#26262C', '#111115'))

CHARACTERS = {
    'Bella': dict(
        sex='f', skin=PALE, eye='#5B3A21', lips='#BE7A70',
        hair=('#55402C', '#281A11'), hair_style='long_straight', hl_x=-0.028,
        top=('#8B939E', '#474F5A'), legs=('#4C5C72', '#2A3542'), shoes=('#E4DED6', '#A69E95'),
        shoulder=0.097, waist=0.067, hip=0.096,
    ),
    'Edward': dict(
        sex='m', skin=PALER, eye='#C08A2E', lips='#BE8680',
        hair=('#A06A38', '#4A2C14'), hair_style='messy_short', hl_x=-0.024,
        top=('#3B414B', '#191D24'), legs=('#434A56', '#222831'), shoes=('#2A2522', '#131110'),
        shoulder=0.112, waist=0.081, hip=0.089,
    ),
    'Alice': dict(
        sex='f', skin=PALER, eye='#C9A227', lips='#C4857C',
        hair=('#34343C', '#121218'), hair_style='short_spiky', hl_x=-0.022,
        shoulder=0.089, waist=0.067, hip=0.084, **UNIFORM,
    ),
    'Rosalie': dict(
        sex='f', skin=WARM, eye='#C9A227', lips='#C27F76',
        hair=('#EBD79A', '#A28038'), hair_style='long_wavy', hl_x=-0.030,
        shoulder=0.097, waist=0.067, hip=0.096, **UNIFORM,
    ),
    'Jasper': dict(
        sex='m', skin=WARM, eye='#C9A227', lips='#BE8078',
        hair=('#E2C886', '#96762F'), hair_style='shoulder', hl_x=-0.026,
        shoulder=0.112, waist=0.081, hip=0.089, **UNIFORM,
    ),
    'Emmett': dict(
        sex='m', skin=WARM, eye='#C9A227', lips='#B87A72',
        hair=('#3B2A20', '#150E09'), hair_style='short_curly', hl_x=-0.024,
        shoulder=0.132, waist=0.096, hip=0.098, **UNIFORM,
    ),
    'James': dict(
        sex='m', skin=('#E3CEBF', '#AB8570'), eye='#8C3A22', lips='#A9716A',
        hair=('#2F251C', '#0F0A05'), hair_style='long_slick', hl_x=-0.028,
        shoulder=0.113, waist=0.082, hip=0.089,
        top=('#2D2925', '#121010'), legs=('#27231F', '#0F0D0B'), shoes=('#1E1A16', '#0B0908'),
    ),
    'Jacob': dict(
        sex='m', skin=TAN, eye='#4A2E1B', lips='#A8705F',
        hair=('#181310', '#080605'), hair_style='long_slick', hl_x=-0.028,
        shoulder=0.126, waist=0.090, hip=0.096,
        top=('#6B6E6A', '#33352F'), legs=('#3F4650', '#1F242B'), shoes=('#3A2E24', '#1A1410'),
    ),
}


def render(name, cfg, out_dir):
    img = draw_figure(cfg)
    img.save(os.path.join(out_dir, name + '.png'))
    return img


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else 'sprites'
    os.makedirs(out_dir, exist_ok=True)

    tiles = []
    for name, cfg in CHARACTERS.items():
        tiles.append((name, render(name, cfg, out_dir)))
        print('saved', name)

    # позы
    poses = [
        ('Edward_reach', dict(CHARACTERS['Edward'], pose='reach')),
        ('Edward_bat', dict(CHARACTERS['Edward'], pose='bat')),
        ('Alice_pitch', dict(CHARACTERS['Alice'], pose='pitch', shorts=True, stance=1.35)),
        ('Emmett_reach', dict(CHARACTERS['Emmett'], pose='reach', shorts=True, stance=1.2)),
        ('Rosalie_reach', dict(CHARACTERS['Rosalie'], pose='reach', shorts=True, stance=1.15)),
        ('Jasper_reach', dict(CHARACTERS['Jasper'], pose='reach', shorts=True, stance=1.15)),
        ('Edward_kneel', dict(CHARACTERS['Edward'], pose='kneel', crouch=0.30)),
    ]
    for name, cfg in poses:
        render(name, cfg, out_dir)
        print('saved', name)

    van = draw_van(); van.save(os.path.join(out_dir, 'Van.png')); print('saved Van', van.size)
    wound = draw_wound(); wound.save(os.path.join(out_dir, 'Wound.png')); print('saved Wound', wound.size)

    cols = len(tiles)
    sheet = Image.new('RGB', (SPRITE_W * cols, SPRITE_H), (16, 20, 28))
    for i, (_, im) in enumerate(tiles):
        sheet.paste(im, (i * SPRITE_W, 0), im)
    sheet.save(sys.argv[2] if len(sys.argv) > 2 else os.path.join(out_dir, '_sheet.png'))
    print('sheet saved')


if __name__ == '__main__':
    main()
