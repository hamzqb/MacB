# Third-party notices

MacB ships one third-party library, llama.cpp, and no third-party model
weights. This file records that library, the model MacB can download at the
user's request, the work MacB learned from, and the licence reasons behind two
deliberate omissions.

## llama.cpp and ggml — vendored source

- Project: [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp), release
  v0.4.1 (commit b29c606), which includes ggml
- Licence: MIT, Copyright (c) 2023-2026 The ggml authors
- Where: `Vendor/llama` (the library, compiled into MacB) and
  `Vendor/llama-metal` (its GPU kernels as source, copied into the app and
  compiled by the GPU driver). The full licence is in `Vendor/llama/LICENSE`.
- How it got there: `scripts/vendor-llama.sh`, from an unmodified checkout.

It runs the local model inside MacB's own process. Nothing about it talks to
the network.

## Qwen 3 4B Instruct (2507) — downloaded on request, not bundled

- Model: Qwen/Qwen3-4B-Instruct-2507, as the 4-bit GGUF file
  `Qwen3-4B-Instruct-2507-Q4_K_M.gguf` published by unsloth on Hugging Face
- Licence: Apache 2.0, Copyright Alibaba Cloud (Qwen team)
- SHA-256: `3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597`

MacB does not ship the weights. They are fetched only when the user presses
"İndir" under Settings › Asistan › Yerel model, checked against the SHA-256
above, and kept in `~/Library/Application Support/MacB/Models`. Removing them
moves the file to the Trash.

## Glance — architectural reference

- Project: [jonnyoo/glance](https://github.com/jonnyoo/glance)
- Licence: MIT, Copyright (c) 2026 Jonathan Zhou

MacB's face unlock follows the same pipeline shape that Glance uses: Vision for
detection, landmarks and head pose; a five-point similarity transform onto a
112x112 canonical crop; an embedding compared by cosine similarity against an
averaged template; and AES-GCM storage under a Keychain key protected by
`userPresence`. The MIT licence permits reuse, and the Swift in
`Sources/MacB/FaceUnlock/` was written for MacB rather than copied.

Two Glance capabilities are intentionally absent from MacB:

- **Storing the macOS account password.** MacB never asks for, stores, or
  encrypts the Mac password.
- **Typing the password at the lock screen.** MacB has no keystroke injection
  and does not unlock macOS itself. Face unlock opens MacB's own private areas
  only, and every failure falls back to the system's own LocalAuthentication
  prompt, where Touch ID, Apple Watch or the password are handled entirely by
  macOS.

## SFace — the face model MacB ships

- Model: SFace, a MobileFaceNet trained with the SFace loss, as published in
  [OpenCV Zoo](https://github.com/opencv/opencv_zoo/tree/main/models/face_recognition_sface)
- Licence: **Apache 2.0**, in `Vendor/face-sface/LICENSE`
- Paper: Zhong et al., [SFace: Sigmoid-Constrained Hypersphere Loss for Robust
  Face Recognition](https://arxiv.org/abs/2205.12010)
- Where: `Vendor/face-sface/FaceEmbedding.mlpackage`, copied into the app and
  compiled by Core ML on the user's own Mac at first use
- How it got there: the published ONNX file was converted to Core ML with
  coremltools; `Vendor/face-sface/README.md` records the exact steps, the
  source file's SHA-256 and the check that the conversion did not change the
  model's output.

It turns an aligned face into 128 numbers on this Mac. No image is written to
disk and nothing about a face leaves the Mac.

## InsightFace ArcFace weights — deliberately not bundled

Glance bundles an ArcFace Core ML model converted from the InsightFace
`w600k_mbf` weights. Those weights are published for **non-commercial research
use only**, so they are not redistributable inside MacB and are not present in
this repository or in any MacB build.

MacB ships SFace instead, which is Apache 2.0 and may be redistributed. Apple's
own `VNGenerateImageFeaturePrintRequest` remains as the fallback for a Mac where
the model cannot be loaded; it separates faces less sharply, which is one reason
face unlock guards MacB's own surfaces and never the macOS login.

If a user installs their own compiled Core ML face model at
`~/Library/Application Support/MacB/Models/FaceEmbedding.mlmodelc`, MacB can use
it, but only while the experimental setting is on. Choosing a model and
complying with its licence is the user's decision, not a default MacB makes for
them. Samples record which embedder produced them, so switching models retires
the old enrollment instead of silently comparing vectors from different spaces.

## Apple frameworks

Vision, Core ML, AVFoundation, CryptoKit, LocalAuthentication, Security and
AppKit are used under the Apple SDK licence that ships with Xcode.

## Interface research

MacB's Dock previews and notch interactions were evaluated against
[DockDoor](https://github.com/ejbills/DockDoor) and
[boring.notch](https://github.com/TheBoredTeam/boring.notch). Both projects are
GPL-3.0. MacB does not copy, compile, link, or redistribute their source code.
The multi-display behavior, one-panel preview lifecycle, compact system status,
media surface, file shelf, camera mirror, and gesture ideas were implemented
independently for MacB, primarily with Apple's documented frameworks, so MacB
can remain MIT licensed. Numbered Mission Control desktop grouping separately
uses dynamically loaded, read-only SkyLight symbols and has a public fallback;
no DockDoor or boring.notch source is copied or linked.

## Weather data

Current conditions come from [Open-Meteo](https://open-meteo.com), free for
non-commercial use under CC BY 4.0. MacB sends only a place name the user typed
and the coordinates that name resolves to. No account and no API key are used,
and the request runs only while the weather widget is on screen.

## Lid angle sensor

Apple silicon MacBooks expose the hinge angle through an undocumented HID
feature report. The matching criteria (vendor `0x05ac`, product `0x8104`, usage
page `0x20`, usage `0x8a`) and the two-byte little-endian report layout come
from [Lid Plane](https://github.com/jh3y/lid-plane) by Jhey Tompkins, which is
MIT licensed. MacB's reader is its own code and the sensor is only ever read,
never seized or written to; readings outside 0–180° are discarded rather than
trusted, and machines without the sensor keep the feature switched off.

MIT License, Copyright (c) 2026 Jhey. Permission is hereby granted, free of
charge, to any person obtaining a copy of this software and associated
documentation files to deal in the Software without restriction, subject to the
copyright notice and this permission notice being included in all copies or
substantial portions of the Software. The Software is provided "as is", without
warranty of any kind.
