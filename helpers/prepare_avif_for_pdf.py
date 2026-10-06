"""Prepare AVIF pages as JPEG 2000, keeping the NUL-separated image list in order.

Requires: numpy, imagecodecs, Pillow.
"""

from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import sys
from tempfile import mkdtemp

QUALITY = 35


def convert_page(task):
    import numpy as np
    from imagecodecs import jpeg2k_encode
    from PIL import Image

    source, destination = task
    with Image.open(source) as image:
        # img2pdf cannot read AVIF alpha directly; PNG preserves it as a PDF soft mask.
        if image.n_frames == 1 and image.mode in ("RGBA", "LA"):
            destination = destination.with_suffix(".png")
            metadata = {key: image.info[key] for key in ("icc_profile", "exif", "dpi") if key in image.info}
            image.save(destination, format="PNG", **metadata)
            return os.fsencode(destination)
        # Keep the existing img2pdf path when JP2 would discard supported image information.
        if (
            image.n_frames != 1
            or image.mode not in ("RGB", "L")
            or any(image.info.get(key) for key in ("icc_profile", "exif", "dpi", "transparency"))
        ):
            return source
        encoded = jpeg2k_encode(np.asarray(image), level=QUALITY, numthreads=1)
    destination.write_bytes(encoded)
    return os.fsencode(destination)


def main():
    image_list = Path(sys.argv[1])
    paths = image_list.read_bytes().split(b"\0")[:-1]
    indices = [i for i, path in enumerate(paths) if path.lower().endswith(b".avif")]
    if not indices:
        return

    output_dir = Path(mkdtemp(prefix="jp2.", dir=sys.argv[2]))
    tasks = [(paths[i], output_dir / f"{i:06d}.jp2") for i in indices]
    workers = min(8, os.cpu_count() or 1, len(tasks))
    print(f"Preparing {len(tasks)} AVIF pages as JP2 (quality {QUALITY}, {workers} workers)", file=sys.stderr)
    converted = 0
    with ThreadPoolExecutor(max_workers=workers) as executor:
        for done, (index, path) in enumerate(zip(indices, executor.map(convert_page, tasks)), 1):
            converted += path != paths[index]
            paths[index] = path
            print(f"\rPrepared {done}/{len(tasks)} AVIF pages", end="", file=sys.stderr, flush=True)
    print(f"\nConverted {converted}; retained {len(tasks) - converted} for image information", file=sys.stderr)
    image_list.write_bytes(b"\0".join(paths) + b"\0")


if __name__ == "__main__":
    try:
        main()
    except ModuleNotFoundError as error:
        sys.exit(f"Missing dependency for AVIF conversion: {error.name}")
