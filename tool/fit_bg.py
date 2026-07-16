"""Fit a generated poster into a store-shot frame's aspect ratio.

The image generator only makes 2:3 portraits (1024x1536), but the export frames
are 1242x2688 (mobile, 1:2.16) and 2048x2732 (ipad, 1:1.33). Handing the raw
generation to the editor lets `bgFit: cover` crop it sideways — on mobile that
cuts 31% of the width and slices the Korean headline off at both ends.

So author the bg at the frame's aspect instead (like miles1's bgs). Keep the
full width — the text must never be cropped — and fix the height:

  - height to spare (ipad): crop the excess off the BOTTOM, which is floor/scene.
  - height missing (mobile): extend downward, fading the art's own bottom edge to
    black. The extension lands under the phone frame and the narrow side strips,
    where these scenes are already dark.

Either way the text block also moves as a fraction of the reframed image, which
is what decides the phone's topFraction (see workflows/STORETOOL.md).

Usage: fit_bg.py <src.png> <out.jpg> [mobile|ipad]
"""
import sys
from PIL import Image

# Authored bg sizes, one per device — same aspect as that device's export frame
# (kStoreDevices in store_device.dart), matching miles1's bgs.
TARGETS = {
    "mobile": (853, 1844),   # frame 1242x2688
    "ipad": (2064, 2752),    # frame 2048x2732
}
FADE_SAMPLE = 8  # px of the art's bottom edge averaged for the extension


def fit(src_path, out_path, device="mobile"):
    if device not in TARGETS:
        raise SystemExit(f"unknown device {device!r}; use {'/'.join(TARGETS)}")
    out_w, out_h = TARGETS[device]

    im = Image.open(src_path).convert("RGB")
    art = im.resize((out_w, round(im.height * out_w / im.width)), Image.LANCZOS)

    if art.height >= out_h:
        canvas = art.crop((0, 0, out_w, out_h))
        note = f"crop {art.height - out_h}px off the bottom"
    else:
        canvas = Image.new("RGB", (out_w, out_h), (0, 0, 0))
        canvas.paste(art, (0, 0))
        tail = out_h - art.height
        edge = art.crop((0, art.height - FADE_SAMPLE, out_w, art.height))
        edge = edge.resize((out_w, tail), Image.LANCZOS)
        black = Image.new("RGB", (out_w, tail), (0, 0, 0))
        mask = Image.linear_gradient("L").resize((out_w, tail))
        canvas.paste(Image.composite(black, edge, mask), (0, art.height))
        note = f"art {art.height}px + fade {tail}px"

    canvas.save(out_path, quality=92)
    print(f"{out_path}: {out_w}x{out_h} [{device}] ({note})")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    fit(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "mobile")
