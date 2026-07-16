"""Draw the phone's footprint over a bg so you can SEE what it will cover.

The image generator ignores "keep the text in the top 30%" instructions — it
drifts down and the phone frame then slices through the headline. Never trust
the prompt; render this check and look at it before installing a bg.

It approximates the Dart compositor (StoreShotComposer): cover-fits the bg into
the device's export frame, then outlines the phone rect from doc.json's
widthFraction / topFraction / centerXFraction. Anything inside the red box (or
below the red line, at the centre) is hidden at export.

Usage: layout_check.py <bg.jpg> <out.jpg> [topFraction] [mobile|ipad]
"""
import sys
from PIL import Image, ImageDraw

# Export frame per device — kStoreDevices in store_device.dart.
FRAMES = {
    "mobile": (1242, 2688),
    "ipad": (2048, 2732),
}
# Default phone width per device, matching what the docs use.
WIDTH_FRACTION = {"mobile": 0.72, "ipad": 0.52}


def cover(im, fw, fh):
    s = max(fw / im.width, fh / im.height)
    r = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    return r.crop((
        (r.width - fw) // 2,
        (r.height - fh) // 2,
        (r.width - fw) // 2 + fw,
        (r.height - fh) // 2 + fh,
    ))


def check(path, out, top_f=0.35, device="mobile", width_f=None, cx_f=0.5):
    fw, fh = FRAMES[device]
    width_f = width_f if width_f is not None else WIDTH_FRACTION[device]
    bg = cover(Image.open(path).convert("RGB"), fw, fh)
    d = ImageDraw.Draw(bg)
    pw = fw * width_f
    x0 = fw * cx_f - pw / 2
    y0 = fh * top_f
    d.rounded_rectangle([x0, y0, x0 + pw, fh], radius=60,
                        outline=(255, 0, 0), width=10)
    d.line([(0, y0), (fw, y0)], fill=(255, 0, 0), width=6)
    bg.save(out, quality=88)
    print(f"{path} -> {out} [{device} {fw}x{fh}] "
          f"phone top y={int(y0)} ({top_f:.0%}), width {width_f:.0%}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    check(
        sys.argv[1],
        sys.argv[2],
        float(sys.argv[3]) if len(sys.argv) > 3 else 0.35,
        sys.argv[4] if len(sys.argv) > 4 else "mobile",
    )
