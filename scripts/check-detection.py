#!/usr/bin/env python3
"""Sanity-checks the output of `BodyTracking --detect bus.jpg` (CI smoke test)."""
import json
import sys

for path in sys.argv[1:]:
    with open(path) as f:
        message = json.load(f)
    assert message["operation"] == "pubsub.publish", message["operation"]
    assert message["clientType"] == "pose-detector"
    poses = message["payload"]["data"]
    print(f"{path}: {len(poses)} poses")
    assert 3 <= len(poses) <= 6, "bus.jpg shows four people"
    for pose in poses:
        points = {k["name"]: k for k in pose["keypoints"]}
        assert len(points) == 17
        box = pose["box"]
        print(f"  conf={pose['confidence']:.2f} box=({box['x']:.2f},{box['y']:.2f},{box['width']:.2f},{box['height']:.2f})"
              f" nose=({points['nose']['x']:.2f},{points['nose']['y']:.2f})"
              f" l_hip=({points['left_hip']['x']:.2f},{points['left_hip']['y']:.2f})")
        assert 0 <= box["x"] <= 1 and 0 <= box["y"] <= 1
    # The three people standing in the foreground are upright and tall in the frame.
    best = poses[0]
    points = {k["name"]: k for k in best["keypoints"]}
    assert best["box"]["height"] > 0.3, "foreground person should fill a good part of the frame"
    assert points["nose"]["y"] < points["left_hip"]["y"] < points["left_knee"]["y"], "upright person: nose above hip above knee"
    inside = [k for k in best["keypoints"] if k["confidence"] > 0.5
              and best["box"]["x"] - 0.05 <= k["x"] <= best["box"]["x"] + best["box"]["width"] + 0.05
              and best["box"]["y"] - 0.05 <= k["y"] <= best["box"]["y"] + best["box"]["height"] + 0.05]
    confident = [k for k in best["keypoints"] if k["confidence"] > 0.5]
    assert len(confident) >= 8 and len(inside) == len(confident), "keypoints should fall inside the person's box"
print("ok")
