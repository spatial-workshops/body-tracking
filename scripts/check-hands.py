#!/usr/bin/env python3
"""Checks the "MediaPipe (modified)" hands output against the MediaPipe output for the same image (CI).

usage: check-hands.py mediapipe.json hands.json hands-flipped.json <canvas width> <canvas height>
"""
import json
import sys

bodies = json.load(open(sys.argv[1]))["payload"]["data"]
hands = json.load(open(sys.argv[2]))["payload"]["data"]
flipped = json.load(open(sys.argv[3]))["payload"]["data"]
W, H = float(sys.argv[4]), float(sys.argv[5])
TOLERANCE = 0.02  # pixels; outputs are rounded to 2 decimals


def close(a, b):
    return abs(a - b) <= TOLERANCE


def check_point(actual, landmark, scored=True, flip=False):
    x = (1 - landmark["x"]) if flip else landmark["x"]
    assert close(actual["x"], x * W) and close(actual["y"], landmark["y"] * H), (actual, landmark)
    if scored:
        assert actual["score"] == landmark["visibility"], (actual, landmark)
    else:
        assert set(actual) == {"x", "y"}, actual


def check(hands, flip):
    assert len(hands) == 2 * len(bodies) > 0, (len(hands), len(bodies))
    for i, hand in enumerate(hands):
        body = bodies[i // 2]
        side = "left" if i % 2 == 0 else "right"
        wrist, elbow = (body[15], body[13]) if side == "left" else (body[16], body[14])
        assert set(hand) == {"side", "wrist", "index", "body", "elbow", "torso",
                             "leftShoulder", "rightShoulder", "leftHip", "rightHip", "head"}, sorted(hand)
        assert hand["side"] == side and hand["body"] == i // 2
        check_point(hand["wrist"], wrist, scored=False, flip=flip)
        check_point(hand["elbow"], elbow, flip=flip)
        check_point(hand["leftShoulder"], body[11], flip=flip)
        check_point(hand["rightShoulder"], body[12], flip=flip)
        check_point(hand["leftHip"], body[23], flip=flip)
        check_point(hand["rightHip"], body[24], flip=flip)
        check_point(hand["head"], body[0], flip=flip)
        torso = hand["torso"]
        assert close(torso["x"], (hand["leftShoulder"]["x"] + hand["rightShoulder"]["x"]) / 2)
        assert close(torso["y"], (hand["leftShoulder"]["y"] + hand["rightShoulder"]["y"]) / 2)
        assert torso["score"] == min(body[11]["visibility"], body[12]["visibility"])
        # The index finger lies on the elbow -> wrist ray, a third of the forearm beyond the wrist.
        index = hand["index"]
        assert set(index) == {"x", "y"}
        assert close(index["x"], hand["wrist"]["x"] + (hand["wrist"]["x"] - hand["elbow"]["x"]) / 3)
        assert close(index["y"], hand["wrist"]["y"] + (hand["wrist"]["y"] - hand["elbow"]["y"]) / 3)


check(hands, flip=False)
check(flipped, flip=True)
print(f"ok: {len(hands)} hands from {len(bodies)} bodies")
