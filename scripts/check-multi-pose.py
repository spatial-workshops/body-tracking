#!/usr/bin/env python3
"""Checks multi-pose test mode (CI).

usage: check-multi-pose.py single.json multi.json several.json several-multi.json
  single.json / multi.json: the same one-person detection without and with --multi-pose
  several.json / several-multi.json: a multi-person detection without and with --multi-pose
"""
import json
import sys


def load(path):
    return json.load(open(path))["payload"]["data"]


single, multi, several, several_multi = (load(p) for p in sys.argv[1:5])
assert len(single) == 1, len(single)
original = single[0]
box = original["box"]
step = max(box["width"], 0.05)
EPS = 2e-4

assert len(multi) > 1, "expected copies"
assert len(multi) == int(box["x"] / step + EPS) + int((1 - box["x"] - box["width"]) / step + EPS) + 1, len(multi)
assert sum(1 for p in multi if abs(p["box"]["x"] - box["x"]) < EPS) == 1, "the original stays in place"
for order, pose in enumerate(multi):
    assert pose["id"] == order
    offset = pose["box"]["x"] - box["x"]
    multiple = round(offset / step)
    assert abs(offset - multiple * step) < EPS, offset
    assert -EPS <= pose["box"]["x"] and pose["box"]["x"] + pose["box"]["width"] <= 1 + EPS, pose["box"]
    assert (pose["box"]["y"], pose["box"]["width"], pose["box"]["height"]) == (box["y"], box["width"], box["height"])
    if order:
        assert pose["box"]["x"] > multi[order - 1]["box"]["x"], "ordered left to right"
    for copy, source in zip(pose["keypoints"], original["keypoints"]):
        assert abs(copy["x"] - source["x"] - offset) < EPS
        assert (copy["name"], copy["y"], copy["confidence"]) == (source["name"], source["y"], source["confidence"])

assert len(several) > 1 and several_multi == several, "several people: output must be unchanged"
print(f"ok: 1 pose -> {len(multi)} poses; {len(several)} poses unchanged")
