"""
attendance_log.face_match
=========================

Single entry point for all face comparison in the app so the backend can be
swapped later without touching the rest of the code (controller / api.py).

Public API
----------
    encode_image(image_path_or_bytes) -> str            # serialized encoding
    compare(reference_encoding_json, new_image) -> (score: float, matched: bool)
    THRESHOLD                                           # tunable float

Backends (auto-selected, best first):
  1. "face_recognition" (dlib)  -> true 128-d face embeddings, cosine distance.
     Install with:  ./env/bin/pip install face_recognition
  2. "fallback" (Pillow + numpy, always available in the Frappe env) ->
     a 64x64 grayscale intensity descriptor compared with normalized
     cross-correlation (mean-centered cosine / NCC). NOT production-grade face
     recognition, but deterministic and discriminating: the same/similar selfie
     scores ~1.0, a structurally different image scores ~0. Documented so it can
     be upgraded to backend #1 (or a hosted API like Azure Face) later by
     editing ONLY this file.

The stored `face_encoding` on `JEW Employee Face` is a JSON string of the form
    {"backend": "<name>", "vector": [...floats...]}
so `compare()` can refuse to compare vectors produced by a different backend
(returns matched=False, score=0.0, status handled by caller).
"""

import io
import json
import math

# similarity threshold in [0,1]; >= THRESHOLD => matched. Tunable.
THRESHOLD = 0.6

# ---------------------------------------------------------------------------
# backend detection
# ---------------------------------------------------------------------------
try:
    import face_recognition as _fr  # type: ignore
    _BACKEND = "face_recognition"
except Exception:
    _fr = None
    _BACKEND = "fallback"


def backend_name():
    return _BACKEND


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def _to_bytes(image):
    """Accept a filesystem path (str) or raw bytes and return bytes."""
    if isinstance(image, (bytes, bytearray)):
        return bytes(image)
    with open(image, "rb") as fh:
        return fh.read()


def _fallback_vector(image_bytes):
    """A cheap, dependency-free descriptor: 64x64 grayscale intensities, kept
    raw (NOT normalized) so compare() can run mean-centered cosine (normalized
    cross-correlation) over the pixel structure. Deterministic."""
    from PIL import Image  # Pillow ships with Frappe
    import numpy as np

    img = Image.open(io.BytesIO(image_bytes)).convert("L").resize((64, 64))
    arr = np.asarray(img, dtype="float64").flatten()
    return arr.tolist()


def _ncc(a, b):
    """Normalized cross-correlation: cosine of mean-centered vectors, in [-1,1].
    ~1.0 for the same image, ~0 for structurally unrelated images."""
    import numpy as np
    a = np.asarray(a, dtype="float64")
    b = np.asarray(b, dtype="float64")
    a = a - a.mean()
    b = b - b.mean()
    na, nb = np.linalg.norm(a), np.linalg.norm(b)
    if na == 0 or nb == 0:
        return 0.0
    return float(np.dot(a, b) / (na * nb))


def _fr_vector(image_bytes):
    import numpy as np
    img = _fr.load_image_file(io.BytesIO(image_bytes))
    encs = _fr.face_encodings(img)
    if not encs:
        raise ValueError("No face detected in image")
    return np.asarray(encs[0], dtype="float64").tolist()


def _cosine(a, b):
    import numpy as np
    a = np.asarray(a, dtype="float64")
    b = np.asarray(b, dtype="float64")
    na, nb = np.linalg.norm(a), np.linalg.norm(b)
    if na == 0 or nb == 0:
        return 0.0
    return float(np.dot(a, b) / (na * nb))


# ---------------------------------------------------------------------------
# public API
# ---------------------------------------------------------------------------
def encode_image(image):
    """Return a JSON string encoding for storage on JEW Employee Face."""
    b = _to_bytes(image)
    if _BACKEND == "face_recognition":
        vector = _fr_vector(b)
    else:
        vector = _fallback_vector(b)
    return json.dumps({"backend": _BACKEND, "vector": vector})


def _load_reference(reference_encoding_json):
    if not reference_encoding_json:
        return None, None
    try:
        data = json.loads(reference_encoding_json)
    except Exception:
        return None, None
    if isinstance(data, dict):
        return data.get("backend"), data.get("vector")
    # legacy: bare list
    return None, data


def compare(reference_encoding_json, new_image):
    """
    Compare a stored reference encoding against a freshly uploaded image.

    Returns (score, matched):
      score   : cosine similarity mapped to [0,1] (0 on any failure)
      matched : score >= THRESHOLD
    """
    ref_backend, ref_vec = _load_reference(reference_encoding_json)
    if not ref_vec:
        return 0.0, False

    b = _to_bytes(new_image)
    try:
        if _BACKEND == "face_recognition":
            new_vec = _fr_vector(b)
        else:
            new_vec = _fallback_vector(b)
    except Exception:
        return 0.0, False

    # if the reference was produced by a different backend, encodings are not
    # comparable -> treat as not matched (caller flags for re-registration).
    if ref_backend and ref_backend != _BACKEND:
        return 0.0, False

    if _BACKEND == "face_recognition":
        # dlib distance: ~0 identical, ~0.6 typical threshold. Map to similarity.
        import numpy as np
        dist = float(np.linalg.norm(np.asarray(ref_vec) - np.asarray(new_vec)))
        score = max(0.0, 1.0 - dist)  # 1.0 identical -> 0 at distance 1
    else:
        # normalized cross-correlation over pixel structure; clamp negatives.
        score = max(0.0, _ncc(ref_vec, new_vec))

    score = max(0.0, min(1.0, score))
    return round(score, 4), (score >= THRESHOLD)
