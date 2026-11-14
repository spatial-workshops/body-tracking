#!/usr/bin/env python3
"""Checks the MediaPipe-format output against the YOLO-format output for the same image (CI)."""
import json
import sys

yolo = json.load(open(sys.argv[1]))["payload"]["data"]
message = json.load(open(sys.argv[2]))
assert message["operation"] == "pubsub.publish"
mediapipe = message["payload"]["data"]
assert len(mediapipe) == len(yolo) > 0, (len(mediapipe), len(yolo))

# MediaPipe index -> COCO keypoint name, for the landmarks YOLO detects directly.
DIRECT = {0: "nose", 2: "left_eye", 5: "right_eye", 7: "left_ear", 8: "right_ear",
          11: "left_shoulder", 12: "right_shoulder", 13: "left_elbow", 14: "right_elbow",
          15: "left_wrist", 16: "right_wrist", 23: "left_hip", 24: "right_hip",
          25: "left_knee", 26: "right_knee", 27: "left_ankle", 28: "right_ankle"}

for landmarks, pose in zip(mediapipe, yolo):
    assert len(landmarks) == 33, len(landmarks)
    points = {k["name"]: k for k in pose["keypoints"]}
    for index, landmark in enumerate(landmarks):
        assert set(landmark) == {"x", "y", "z", "visibility"}, landmark
        assert landmark["z"] == 0
        if index in DIRECT:
            source = points[DIRECT[index]]
            assert (landmark["x"], landmark["y"], landmark["visibility"]) == (source["x"], source["y"], source["confidence"]), index
        else:
            assert landmark["visibility"] == 0, index
print(f"ok: {len(mediapipe)} poses x 33 landmarks")
