# SFace — the face model MacB ships

`FaceEmbedding.mlpackage` turns an aligned 112×112 face into 128 numbers. Two
pictures of the same face give two vectors close together; two people give two
vectors far apart. That is all it does: it cannot tell who somebody is, only
whether this face is the one already enrolled on this Mac.

- Model: SFace (a MobileFaceNet trained with the SFace loss), as published in
  [OpenCV Zoo](https://github.com/opencv/opencv_zoo/tree/main/models/face_recognition_sface),
  file `face_recognition_sface_2021dec.onnx`
- Licence: **Apache 2.0** — the full text is in `LICENSE` beside this file
- Paper: [SFace: Sigmoid-Constrained Hypersphere Loss for Robust Face
  Recognition](https://arxiv.org/abs/2205.12010), Zhong et al.
- Reported accuracy in OpenCV Zoo's own evaluation: 0.9940
- Source file SHA-256:
  `0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79`

## How this copy was made

The published ONNX file was converted to Core ML on an Apple Silicon Mac:

```
python3.12 -m venv faceenv
faceenv/bin/pip install coremltools onnx onnx2torch torch
# onnx2torch loads the graph, torch.jit traces it, coremltools writes the
# mlpackage as an ML program in float16.
```

The converted model was checked against the original: for random inputs the
cosine similarity between the two outputs is 0.99999, so the conversion did
not change what the model says.

## What MacB does with it

- The picture is aligned to the model's own 112×112 template from the five
  landmarks Vision finds, then handed over as BGR values from 0 to 255, which
  is what this model was trained on.
- Nothing is written to disk and no image leaves the Mac. Only the 128 numbers
  are kept, encrypted, to compare the next face against.
- Face unlock guards MacB's own private sections. It never unlocks macOS, and
  Touch ID remains the way in when a face is not recognised.
