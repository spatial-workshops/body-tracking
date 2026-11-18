#!/usr/bin/env python3
"""Checks `BodyTracking --check-config --config bodytracking.example.yaml` output (CI)."""
import json
import sys

config = json.load(open(sys.argv[1]))
assert config["server"] == {"url": "ws://localhost:4000", "connectOnStartup": True}, config["server"]
first, second = config["windows"]
assert first == {
    "topic": "bouncy.3.hands", "camera": "FaceTime HD Camera", "resolution": "1920x1080",
    "detectionRate": 15, "model": "yolo26n-pose", "minConfidence": 0.35,
    "format": "mediapipe-modified", "canvas": "1920x1080", "scale": 1, "offsetX": 0, "offsetY": 0,
    "flipHorizontally": False, "multiPoseTest": False, "mirrorPreview": True, "cameraOn": True,
}, first
assert second == {"topic": "stage.left", "camera": "Logitech", "resolution": "1280x720",
                  "detectionRate": 30, "format": "yolo"}, second
print("ok: 1 server block, 2 windows")
