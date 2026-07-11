#!/usr/bin/env python3
"""warble mark v3 generator: a songbird built FROM waveform bars (Fish-Audio language, bird envelope).
Vertical pills whose top/bottom edges trace a bird profile facing right. Tunable keypoints."""

# (x, top, bottom) envelope keypoints — linear-interpolated at each bar position.
KEY = [
    (10, 56, 62),    # tail tip (dot)
    (17, 52, 66),    # tail
    (24, 46, 72),    # into body
    (31, 42, 77),    # body rising
    (38, 40, 79),    # body max
    (45, 40, 79),    # body max
    (52, 42, 76),    # body easing
    (58, 44, 70),    # chest (still body mass)
    (58.01, 30, 60), # STEP: chest -> neck
    (64, 24, 50),    # head front
    (70, 21, 48),    # crown
    (76, 23, 46),    # head back
    (76.01, 30, 40), # STEP: head -> beak
    (83, 29, 38),    # beak (short)
    (89, 31.5, 35.5),# beak tip (dot)
]
PITCH = 6.6        # bar spacing
W = 4.4            # bar width
EYE_BAR_X = -999  # no eye: clean bars; the envelope alone carries the bird     # bar that carries the eye gap
EYE_Y = (26.5, 31.5)  # gap span (white) inside that bar

def interp(x, pts):
    for (x0, t0, b0), (x1, t1, b1) in zip(pts, pts[1:]):
        if x0 <= x <= x1:
            f = (x - x0) / (x1 - x0)
            return t0 + f * (t1 - t0), b0 + f * (b1 - b0)
    return pts[-1][1], pts[-1][2]

def pill(x, y0, y1, w=W):
    r = w / 2
    h = y1 - y0
    if h < w:  # dot
        cy = (y0 + y1) / 2
        return f'<circle cx="{x:.2f}" cy="{cy:.2f}" r="{r:.2f}"/>'
    return f'<rect x="{x - r:.2f}" y="{y0:.2f}" width="{w:.2f}" height="{h:.2f}" rx="{r:.2f}"/>'

xs = [KEY[0][0] + i * PITCH for i in range(int((KEY[-1][0] - KEY[0][0]) / PITCH) + 1)]
shapes = []
for x in xs:
    t, b = interp(x, KEY)
    if abs(x - EYE_BAR_X) < PITCH / 2:  # split this bar around the eye gap
        shapes.append(pill(x, t, EYE_Y[0]))
        shapes.append(pill(x, EYE_Y[1], b))
    else:
        shapes.append(pill(x, t, b))

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <!-- warble mark v3: the bird IS the waveform — vertical bars whose envelope traces a
       songbird (tail, body, crown, beak); the gap in the crown bar is the eye. -->
  <g fill="#000000">
    {chr(10).join('    ' + s for s in shapes)}
  </g>
</svg>
'''
open('warble_glyph.svg', 'w').write(svg)
print(f"{len(xs)} bars -> warble_glyph.svg")
