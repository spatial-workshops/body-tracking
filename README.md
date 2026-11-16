# Body Tracking

A macOS app that runs real-time YOLO pose detection on one or more webcams and publishes the
detected body landmarks to a WebSocket pubsub server.

- Swift + SwiftUI, macOS 15 (Sequoia) or later
- Ultralytics **YOLO26 pose** models running on Core ML (Neural Engine / GPU / CPU)
- Any number of tracker windows, each with its own camera, resolution, detection rate, model and topic
- One shared WebSocket connection with automatic reconnection

## Requirements

- macOS 15 or later
- An internet connection for the first build, which downloads the
  [Yams](https://github.com/jpsim/Yams) YAML parser
- Xcode 16 or later installed (only its command-line toolchain is used; there is no Xcode project).
  The Command Line Tools on their own are enough for a native build:

  ```bash
  xcode-select --install
  ```

## Build

```bash
git clone https://github.com/spatial-workshops/body-tracking.git
```

```bash
cd body-tracking
```

```bash
./scripts/build-app.sh
```

This compiles a release build with SwiftPM, assembles `build/BodyTracking.app` and ad-hoc signs it.

```bash
open build/BodyTracking.app
```

Always launch the `.app` bundle rather than `swift run`: the camera permission prompt needs the
bundle's `Info.plist`. An ad-hoc signed build runs only on the Mac that built it, and macOS asks for
camera permission again after each rebuild. Signing with your Developer ID (below) fixes both.

Build options are environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `SIGN_IDENTITY` | `-` (ad-hoc) | `codesign` identity |
| `BUNDLE_ID` | `com.spatial-workshops.BodyTracking` | Bundle identifier |
| `VERSION` | `0.1.0` | Marketing version |
| `BUILD_NUMBER` | git commit count | Build number |
| `UNIVERSAL` | `0` | `1` builds arm64 + x86_64 (needs full Xcode) |

## Using the app

1. **Open a window.** The first window opens at launch; **File › New Window** (⌘N) opens more.
   Each window is an independent tracker.
2. **Pick a camera and resolution** in the window's side panel. The resolution defaults to
   1920 × 1080 when the camera offers it.
3. **Pick a model.** The first launch downloads YOLO26n Pose (about 3 MB). Choosing a model that
   isn't installed downloads and compiles it. **Manage Models…** (⇧⌘M) lists, deletes and imports models.
4. **Set the detection rate** (1–60 fps, default 15), the window's **topic** and the output
   **format** (see [Published messages](#published-messages)).
5. **Connect.** Set the server URL and client ID in **Settings** (⌘,) and press **Connect**, either
   there or in the bar at the bottom of any window.

Per-window options are restored with the window. The server URL, client ID and
"connect at launch" are app-wide.

### Startup configuration file

The app reads `~/bodytracking.yaml` at launch, if it exists. It sets the server options and
describes the windows to open, so a whole setup starts without any clicking.
[`bodytracking.example.yaml`](bodytracking.example.yaml) lists every setting:

```bash
cp bodytracking.example.yaml ~/bodytracking.yaml
```

```yaml
server:
  url: ws://localhost:4000
  connectOnStartup: true

windows:
  - topic: bouncy.3.hands
    camera: FaceTime HD Camera
    resolution: 1920x1080
  - topic: stage.left
    camera: Logitech
    detectionRate: 30
    format: yolo
```

Every setting is optional; one that is left out keeps the app's default.

| `server` setting | Meaning |
| --- | --- |
| `url` | WebSocket server URL |
| `connectOnStartup` | `true` connects as soon as the app launches |
| `clientId` | Client ID; leave out to keep the generated UUID |

| `windows` setting | Meaning | Default |
| --- | --- | --- |
| `topic` | Pubsub topic | `pose` |
| `camera` | Camera name as shown in the Camera menu, part of the name, or the camera's unique ID | System default camera |
| `resolution` | `WIDTHxHEIGHT` | `1920x1080` if offered |
| `cameraOn` | Start the camera | `true` |
| `mirrorPreview` | Mirror the preview (display only) | `true` |
| `model` | Model ID, such as `yolo26s-pose`, or the name of an imported model | `yolo26n-pose` |
| `detectionRate` | Detections per second, 1–60 | `15` |
| `minConfidence` | Threshold for reporting a person, 0.05–0.95 | `0.35` |
| `format` | `mediapipe-modified`, `mediapipe` or `yolo` | `mediapipe-modified` |
| `canvas` | Receiving canvas, `WIDTHxHEIGHT` in pixels | `1920x1080` |
| `scale` | Body scale | `1.0` |
| `offsetX`, `offsetY` | Offset in canvas pixels | `0` |
| `flipHorizontally` | Mirror x in the published data | `false` |
| `multiPoseTest` | Multi-pose test mode | `false` |

How the file is applied:

- **Server settings** replace the ones in the Settings window at every launch. You can still change
  them in the app; the file wins again at the next launch.
- **Windows:** one window opens per entry, in order. When the file lists windows, the app opens
  exactly those and does not restore the windows of the previous session. Windows you open
  afterwards with ⌘N start from the defaults. Without a `windows` list the app behaves as it does
  with no file.
- **Cameras** are matched by unique ID, then by exact name, then by part of the name, ignoring
  case. If no camera matches, or the camera does not offer the requested resolution, the window
  falls back to the default and says so at the top of its Camera section.
- **The file is read only at launch** and the app never writes to it.
- **Mistakes:** if the file cannot be parsed it is ignored and the first window shows the reason.
  Settings with unknown names are ignored and listed the same way.

To use a file somewhere else, pass `--config`:

```bash
open build/BodyTracking.app --args --config /path/to/setup.yaml
```

To validate a file without starting the app, which prints the settings as the app understood them:

```bash
build/BodyTracking.app/Contents/MacOS/BodyTracking --check-config --config ~/bodytracking.yaml
```

### Connection behaviour

- The default URL is `ws://localhost:4000`; the default client ID is a random UUID generated on
  first launch.
- After **Connect**, the app keeps the connection alive. If the server is unreachable or the socket
  drops, it retries every 2 seconds until it succeeds or you press **Disconnect**.
- The URL and client ID are locked while a connection is active.
- After every successful connection or reconnection the app sends:

```json
{
  "operation": "client.register",
  "payload": {
    "clientId": "<client ID>",
    "clientType": "pose-detector"
  }
}
```

### Published messages

While connected, each window sends one text frame per processed camera frame, including frames
with nobody in view (`data` is then `[]`). Nothing is sent while the topic is empty.

```json
{
  "operation": "pubsub.publish",
  "clientId": "<client ID>",
  "clientType": "pose-detector",
  "payload": {
    "topic": "<window topic>",
    "data": []
  }
}
```

The **Format** picker in each window chooses the layout of `data`: **MediaPipe (modified)** (the
default), **MediaPipe** or **YOLO**. In every format people are ordered by descending confidence,
the origin is the top-left corner of the camera frame, and "left" and "right" are the person's own.

**Flip horizontally** mirrors x in the published data, in every format (x becomes 1 − x; left and
right labels stay with the person). It is off by default. "Mirror preview" is separate and only
affects the display.

Each window can also adjust the bodies before publishing. Only the adjusted values are published,
and the preview overlay draws them too, so with a scale other than 1 the skeleton no longer sits
exactly on the person in the video.

- **Body scale** resizes each body about its chest (the midpoint between its shoulders): `0.5`
  halves it, `2` doubles it. The default is `1`.
- **Offset (px)** then moves every body by x and y, in pixels of the canvas set in **Canvas size**
  (default 1920 × 1080). Positive x is right, positive y is down, and negative values are allowed.
  The defaults are `0`. In the MediaPipe and YOLO formats, whose coordinates are normalized, the
  offset is divided by the canvas width or height.

The order is: scale → multi-pose test copies → flip → offset. The offset is applied last, so it is
never scaled and a positive x always moves bodies to the right. Adjusted coordinates are not
clamped and can fall outside the frame.

**Multi-pose test mode** is a testing aid for multi-person receivers. While it is on and exactly
one person is detected, that pose is published together with copies of it shifted left and right
by whole multiples of its bounding-box width, as many as fit entirely inside the frame (20 at
most). The row is ordered left to right, the detected person stays where they are, and the preview
draws the copies too. With zero or several people detected, the output is unchanged. It is off by
default and applies to every format.

#### MediaPipe (modified) format (default)

`data` is a flat list of hands, two per detected person (left, then right), built from the
MediaPipe-format landmarks below. Coordinates are in pixels of a canvas whose size you set in the
window's **Canvas size** fields (default 1920 × 1080): each normalized coordinate is multiplied by
the canvas width or height.

```json
"data": [
  {
    "side": "left",
    "wrist": { "x": 1012.48, "y": 640.15 },
    "index": { "x": 1040.11, "y": 688.4 },
    "body": 0,
    "elbow": { "x": 929.6, "y": 495.4, "score": 0.9712 },
    "torso": { "x": 860.2, "y": 310.75, "score": 0.9903 },
    "leftShoulder": { "x": 940.8, "y": 312.1, "score": 0.9931 },
    "rightShoulder": { "x": 779.6, "y": 309.4, "score": 0.9903 },
    "leftHip": { "x": 915.3, "y": 610.2, "score": 0.9854 },
    "rightHip": { "x": 801.9, "y": 608.8, "score": 0.9849 },
    "head": { "x": 858.7, "y": 201.6, "score": 0.9876 }
  }
]
```

| Field | Source |
| --- | --- |
| `side` | `"left"` or `"right"` |
| `body` | Index of the person; both of a person's hands carry the same torso fields |
| `wrist` | MediaPipe landmark 15 (left) or 16 (right) |
| `index` | Estimated: on the ray from the elbow through the wrist, one third of the forearm's length beyond the wrist |
| `elbow` | Landmark 13 or 14 |
| `leftShoulder`, `rightShoulder` | Landmarks 11 and 12 |
| `torso` | Midpoint of the shoulders; `score` is the lower of the two shoulder scores |
| `leftHip`, `rightHip` | Landmarks 23 and 24 |
| `head` | Landmark 0 (nose) |

- `score` is the landmark's `visibility`. `wrist` and `index` have no score.
- Every person yields exactly two hands, including when a wrist is occluded or out of frame; use the
  `elbow` score to judge an arm's reliability.
- `index` can fall outside the canvas when the arm points off-screen.
- The one-third factor is `HandsConverter.indexFingerExtension` in
  `Sources/BodyTracking/Pose/HandsFormat.swift`.

#### MediaPipe format

Coordinates are normalized to the camera frame: `(0, 0)` is the top-left corner and `(1, 1)` the
bottom-right.

`data` matches the `landmarks` field of a MediaPipe Pose Landmarker result: one array of 33
landmarks per person, in MediaPipe's index order.

```json
"data": [
  [
    { "x": 0.4512, "y": 0.1873, "z": 0, "visibility": 0.9876 },
    { "x": 0.4633, "y": 0.1701, "z": 0, "visibility": 0 }
  ]
]
```

The YOLO model detects 17 body points, so the translation works like this:

| MediaPipe landmarks | Source | `visibility` |
| --- | --- | --- |
| 0 nose, 2 / 5 eyes, 7 / 8 ears, 11–16 shoulders, elbows, wrists, 23–28 hips, knees, ankles | The matching YOLO keypoint | The keypoint's confidence |
| 1, 3, 4, 6 inner and outer eye corners | Position of the same-side eye | 0 |
| 9, 10 mouth | Position of the nose | 0 |
| 17–22 pinky, index, thumb | Position of the same-side wrist | 0 |
| 29–32 heel, foot index | Position of the same-side ankle | 0 |

- The 16 landmarks YOLO cannot detect are placeholders: they keep the array at 33 entries so
  MediaPipe indices work, and their `visibility` of 0 marks them as not detected.
- `z` is always 0, because YOLO pose has no depth estimate.
- MediaPipe's `worldLandmarks` (metric 3D) and segmentation masks have no YOLO equivalent and are
  not sent. The person's bounding box and overall confidence are not part of this format.

#### YOLO format

Coordinates are normalized, as in the MediaPipe format.

```json
"data": [
  {
    "id": 0,
    "confidence": 0.9312,
    "box": { "x": 0.2811, "y": 0.1042, "width": 0.3120, "height": 0.8514 },
    "keypoints": [
      { "name": "nose", "x": 0.4512, "y": 0.1873, "confidence": 0.9876 },
      { "name": "left_eye", "x": 0.4633, "y": 0.1701, "confidence": 0.9811 }
    ]
  }
]
```

- `id` is the person's index within that frame. It is **not** a stable identity across frames.
- `keypoints` always holds the 17 COCO keypoints in this order: `nose`, `left_eye`, `right_eye`,
  `left_ear`, `right_ear`, `left_shoulder`, `right_shoulder`, `left_elbow`, `right_elbow`,
  `left_wrist`, `right_wrist`, `left_hip`, `right_hip`, `left_knee`, `right_knee`, `left_ankle`,
  `right_ankle`.
- Keypoints that are occluded or out of frame are still listed, with a low `confidence`. Filter on
  it (the preview draws keypoints at 0.5 and above).

In every format, "Min. confidence" in the window sets the threshold for reporting a person at all.

## Models

The app manages its own models. The built-in catalog is the five YOLO26 pose sizes, downloaded on
demand from the official Core ML exports that Ultralytics publishes as release assets of
[ultralytics/yolo-ios-app](https://github.com/ultralytics/yolo-ios-app/releases/tag/v8.3.0):

| Model | Download | Notes |
| --- | --- | --- |
| YOLO26n Pose | 2.8 MB | Default, fastest |
| YOLO26s Pose | 9.7 MB | |
| YOLO26m Pose | 19.9 MB | |
| YOLO26l Pose | 24.1 MB | |
| YOLO26x Pose | 53.0 MB | Most accurate |

Compiled models are cached in `~/Library/Application Support/BodyTracking/Models`.

To use a model that isn't in the catalog (a newer generation, or one you trained), export it to
Core ML and use **Manage Models… › Import Core ML Model…**:

```bash
pip install ultralytics
```

```bash
yolo export model=yolo26n-pose.pt format=coreml
```

The importer accepts `.mlpackage`, `.mlmodel`, `.mlmodelc` or a zip of one. Both Ultralytics pose
output layouts are supported: NMS-free (YOLO26) and classic (YOLO11, YOLOv8). To add a model to the
built-in catalog, edit `Sources/BodyTracking/Models/ModelCatalog.swift`.

**Licensing:** the Ultralytics YOLO models are distributed under AGPL-3.0, with a commercial
license available from Ultralytics. The app downloads them at run time and does not bundle them,
but check that the license fits how you plan to distribute or use the app.

## Signing and notarizing

You need a **Developer ID Application** certificate in your keychain (create one in Xcode ›
Settings › Accounts › Manage Certificates, or on developer.apple.com).

1. Find the identity name:

   ```bash
   security find-identity -v -p codesigning
   ```

2. Store notarization credentials in the keychain, once. This uses an
   [app-specific password](https://support.apple.com/102654):

   ```bash
   xcrun notarytool store-credentials "bodytracking-notary" --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"
   ```

3. Build and sign with the hardened runtime:

   ```bash
   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" UNIVERSAL=1 ./scripts/build-app.sh
   ```

4. Notarize, staple, and zip:

   ```bash
   NOTARY_PROFILE="bodytracking-notary" ./scripts/notarize.sh
   ```

The result is `build/BodyTracking.zip`, which opens on any Mac running macOS 15 or later without
Gatekeeper warnings. `xcrun notarytool` and `stapler` ship with Xcode, so steps 2 and 4 need the
full Xcode install.

The app is not sandboxed (it is distributed outside the Mac App Store). Its only entitlement is
camera access, in `Support/BodyTracking.entitlements`.

## Checking a model from the terminal

The binary has a headless mode that runs one detection on an image file and prints the
`pubsub.publish` message the app would send. It needs neither a camera nor a server:

```bash
build/BodyTracking.app/Contents/MacOS/BodyTracking --detect photo.jpg --model yolo26s-pose
```

`--model` takes a catalog ID, a path to a Core ML model, or an `https` URL of a zipped one.
`--confidence` sets the threshold (default 0.35). `--format` is `mediapipe-modified` (default), `mediapipe` or `yolo`. `--canvas 1280x720` sets the
canvas size for the modified format and `--flip` mirrors x. `--multi-pose` applies multi-pose test mode.
`--scale 0.5` and `--offset 100,-50` set the body scale and the pixel offset.

## Project layout

```
Package.swift                     SwiftPM manifest (single executable target)
Support/Info.plist                Bundle metadata, camera and network usage strings
Support/BodyTracking.entitlements Hardened-runtime entitlements
scripts/build-app.sh              Build, bundle, sign
scripts/notarize.sh               Notarize, staple, zip
Sources/BodyTracking/
  main.swift                      Entry point (app, or --detect)
  App/                            App scenes, app-wide settings
  Networking/                     WebSocket client, message formats
  Camera/                         Capture session, frame-rate throttling
  Pose/                           Core ML inference, output decoding
  Models/                         Catalog, download, compile, cache
  Views/                          Tracker window, settings, model manager
```

`.github/workflows/build.yml` builds the app on a macOS 15 runner and runs the headless detection
against a sample image with both output layouts.
