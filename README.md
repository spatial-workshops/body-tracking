# Body Tracking

A macOS app that runs real-time YOLO pose detection on one or more webcams and publishes the
detected body landmarks to a WebSocket pubsub server.

- Swift + SwiftUI, macOS 15 (Sequoia) or later
- Ultralytics **YOLO26 pose** models running on Core ML (Neural Engine / GPU / CPU)
- Any number of tracker windows, each with its own camera, resolution, detection rate, model and topic
- One shared WebSocket connection with automatic reconnection

## Requirements

- macOS 15 or later
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
2. **Pick a camera and resolution** in the window's side panel.
3. **Pick a model.** The first launch downloads YOLO26n Pose (about 3 MB). Choosing a model that
   isn't installed downloads and compiles it. **Manage Models…** (⇧⌘M) lists, deletes and imports models.
4. **Set the detection rate** (1–60 fps, default 15) and the window's **topic**.
5. **Connect.** Set the server URL and client ID in **Settings** (⌘,) and press **Connect**, either
   there or in the bar at the bottom of any window.

Per-window options are restored with the window. The server URL, client ID and
"connect at launch" are app-wide.

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
  }
}
```

- `data` has one entry per detected person, ordered by descending confidence.
- `id` is the person's index within that frame. It is **not** a stable identity across frames.
- All coordinates are normalized to the camera frame: `(0, 0)` is the top-left corner and `(1, 1)`
  the bottom-right. Multiply by the frame width and height for pixels. The "Mirror preview" option
  only affects the display, never the data.
- `keypoints` always holds the 17 COCO keypoints in this order: `nose`, `left_eye`, `right_eye`,
  `left_ear`, `right_ear`, `left_shoulder`, `right_shoulder`, `left_elbow`, `right_elbow`,
  `left_wrist`, `right_wrist`, `left_hip`, `right_hip`, `left_knee`, `right_knee`, `left_ankle`,
  `right_ankle`. "Left" and "right" are the person's own left and right.
- Keypoints that are occluded or out of frame are still listed, with a low `confidence`. Filter on
  it (the preview draws keypoints at 0.5 and above).
- "Min. confidence" in the window sets the threshold for reporting a person at all.

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
`--confidence` sets the threshold (default 0.35).

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
