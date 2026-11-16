#!/usr/bin/env python3
"""Checks body scale and pixel offset (CI).

usage: check-transform.py original.json transformed.json transformed-hands.json <canvas w> <canvas h> <scale> <dx> <dy>
  original.json / transformed.json: YOLO-format output without and with --scale/--offset
  transformed-hands.json: the same transform in the "MediaPipe (modified)" format
"""
import json
import sys


def load(path):
    return json.load(open(path))["payload"]["data"]


original, transformed, hands = (load(p) for p in sys.argv[1:4])
W, H, scale, dx, dy = (float(v) for v in sys.argv[4:9])
EPS = 2e-6
assert len(original) == len(transformed) > 0 and len(hands) == 2 * len(original)

for body, (before, after) in enumerate(zip(original, transformed)):
    points = {k["name"]: k for k in before["keypoints"]}
    cx = (points["left_shoulder"]["x"] + points["right_shoulder"]["x"]) / 2
    cy = (points["left_shoulder"]["y"] + points["right_shoulder"]["y"]) / 2

    def expect(x, y):
        return cx + (x - cx) * scale + dx / W, cy + (y - cy) * scale + dy / H

    for a, b in zip(before["keypoints"], after["keypoints"]):
        ex, ey = expect(a["x"], a["y"])
        assert abs(b["x"] - ex) < EPS and abs(b["y"] - ey) < EPS, (a, b)
        assert b["confidence"] == a["confidence"]
    ex, ey = expect(before["box"]["x"], before["box"]["y"])
    assert abs(after["box"]["x"] - ex) < EPS and abs(after["box"]["y"] - ey) < EPS
    assert abs(after["box"]["width"] - before["box"]["width"] * scale) < EPS

    # The chest itself only moves by the offset, in true canvas pixels.
    torso = hands[2 * body]["torso"]
    assert abs(torso["x"] - (cx * W + dx)) < 0.02 and abs(torso["y"] - (cy * H + dy)) < 0.02, torso
    for hand, name in ((hands[2 * body], "left_wrist"), (hands[2 * body + 1], "right_wrist")):
        ex, ey = expect(points[name]["x"], points[name]["y"])
        assert abs(hand["wrist"]["x"] - ex * W) < 0.02 and abs(hand["wrist"]["y"] - ey * H) < 0.02, hand["wrist"]
print(f"ok: {len(original)} bodies scaled by {scale} and moved by ({dx}, {dy}) px")
