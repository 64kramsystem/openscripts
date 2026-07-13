#!/usr/bin/env python3

import contextlib
import importlib.machinery
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest

import numpy as np
from PIL import Image


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "create_jp2_pdf"


def load_real_script():
    """Load the script with the real dependencies (no mocks)."""
    loader = importlib.machinery.SourceFileLoader("create_jp2_pdf_real", str(SCRIPT))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def parse_spec(raw):
    return dict(item.split("=", 1) for item in raw.decode().split())


def load_script():
    state = types.SimpleNamespace(encoded=[], pages=[])

    imagecodecs = types.ModuleType("imagecodecs")

    def png_decode(raw):
        spec = parse_spec(raw)
        return np.zeros((int(spec["h"]), int(spec["w"]), int(spec.get("c", "3"))), dtype=np.uint8)

    def jpeg2k_encode(pixels, /, level=None, *, codecformat=None, reversible=None):
        state.encoded.append({
            "shape": pixels.shape,
            "level": level,
            "codecformat": codecformat,
            "reversible": reversible,
        })
        return b"jp2"

    imagecodecs.png_decode = png_decode
    imagecodecs.jpeg2k_encode = jpeg2k_encode

    pypdf = types.ModuleType("pypdf")
    generic = types.ModuleType("pypdf.generic")

    class DictionaryObject(dict):
        pass

    class DecodedStreamObject(dict):
        def set_data(self, data):
            self.data = data

    class NameObject(str):
        pass

    class NumberObject(int):
        pass

    generic.DecodedStreamObject = DecodedStreamObject
    generic.DictionaryObject = DictionaryObject
    generic.NameObject = NameObject
    generic.NumberObject = NumberObject

    class FakePage(dict):
        def __init__(self, width, height):
            super().__init__({"/Resources": DictionaryObject()})
            self.width = width
            self.height = height

    class FakePdfWriter:
        def add_blank_page(self, width, height):
            page = FakePage(width, height)
            state.pages.append(page)
            return page

        def _add_object(self, obj):
            return obj

        def write(self, output):
            output.write(b"pdf")

    pypdf.PdfWriter = FakePdfWriter

    pil = types.ModuleType("PIL")
    image = types.ModuleType("PIL.Image")

    class FakeImage:
        format = "PNG"

        def __init__(self, raw):
            spec = parse_spec(raw)
            self.width = int(spec["w"])
            self.height = int(spec["h"])
            self.info = {}
            if "dpi" in spec:
                xdpi, ydpi = spec["dpi"].split("x", 1)
                self.info["dpi"] = (float(xdpi), float(ydpi))
            if "aspect" in spec:
                xaspect, yaspect = spec["aspect"].split("x", 1)
                self.info["aspect"] = (int(xaspect), int(yaspect))

        def convert(self, mode):
            channels = 4 if mode == "RGBA" else 3
            return np.zeros((self.height, self.width, channels), dtype=np.uint8)

        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

    def open_image(source):
        return FakeImage(source.getvalue())

    image.open = open_image
    pil.Image = image

    saved_modules = {
        name: sys.modules.get(name)
        for name in (
            "imagecodecs",
            "pypdf",
            "pypdf.generic",
            "PIL",
            "PIL.Image",
            "create_jp2_pdf_under_test",
        )
    }
    sys.modules["imagecodecs"] = imagecodecs
    sys.modules["pypdf"] = pypdf
    sys.modules["pypdf.generic"] = generic
    sys.modules["PIL"] = pil
    sys.modules["PIL.Image"] = image
    sys.modules.pop("create_jp2_pdf_under_test", None)

    loader = importlib.machinery.SourceFileLoader("create_jp2_pdf_under_test", str(SCRIPT))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    try:
        loader.exec_module(module)
    finally:
        for name, old_module in saved_modules.items():
            if old_module is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = old_module

    return module, state


def run_quietly(callback):
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        callback()


def capture_output(callback):
    stdout = io.StringIO()
    stderr = io.StringIO()
    with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
        callback()
    return stdout.getvalue(), stderr.getvalue()


class CreateJp2PdfTest(unittest.TestCase):
    def test_help_exits_successfully_without_jpeg2000_dependencies(self):
        env = os.environ.copy()
        env.pop("PYTHONPATH", None)

        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--help"],
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("usage:", result.stdout)
        self.assertIn("--quality", result.stdout)

    def test_custom_quality_reaches_encoder(self):
        module, state = load_script()

        with tempfile.TemporaryDirectory() as tmpdir:
            input_path = Path(tmpdir) / "input.png"
            output_path = Path(tmpdir) / "output.pdf"
            input_path.write_bytes(b"w=20 h=10")

            run_quietly(lambda: module.main(["--quality", "77", str(input_path), str(output_path)]))

        self.assertEqual([77], [call["level"] for call in state.encoded])

    def test_default_quality_is_40(self):
        module, state = load_script()

        with tempfile.TemporaryDirectory() as tmpdir:
            input_path = Path(tmpdir) / "input.png"
            output_path = Path(tmpdir) / "output.pdf"
            input_path.write_bytes(b"w=20 h=10")

            run_quietly(lambda: module.main([str(input_path), str(output_path)]))

        self.assertEqual([40], [call["level"] for call in state.encoded])

    def test_missing_dpi_uses_img2pdf_default_dpi(self):
        module, state = load_script()

        with tempfile.TemporaryDirectory() as tmpdir:
            input_path = Path(tmpdir) / "input.png"
            output_path = Path(tmpdir) / "output.pdf"
            input_path.write_bytes(b"w=200 h=100")

            run_quietly(lambda: module.build_pdf([input_path], output_path, quality=80))

        self.assertAlmostEqual(150.0, state.pages[0].width)
        self.assertAlmostEqual(75.0, state.pages[0].height)

    def test_embedded_dpi_sets_physical_page_size(self):
        module, state = load_script()

        with tempfile.TemporaryDirectory() as tmpdir:
            input_path = Path(tmpdir) / "input.png"
            output_path = Path(tmpdir) / "output.pdf"
            input_path.write_bytes(b"w=200 h=100 dpi=200x100")

            run_quietly(lambda: module.build_pdf([input_path], output_path, quality=80))

        self.assertAlmostEqual(72.0, state.pages[0].width)
        self.assertAlmostEqual(72.0, state.pages[0].height)

    def test_image_is_drawn_on_page(self):
        module, state = load_script()

        with tempfile.TemporaryDirectory() as tmpdir:
            input_path = Path(tmpdir) / "input.png"
            output_path = Path(tmpdir) / "output.pdf"
            input_path.write_bytes(b"w=20 h=10")

            run_quietly(lambda: module.build_pdf([input_path], output_path, quality=80))

        page = state.pages[0]
        self.assertIn("/Im0", page["/Resources"]["/XObject"])
        self.assertIn(b"/Im0 Do", page["/Contents"].data)
        self.assertEqual("/JPXDecode", page["/Resources"]["/XObject"]["/Im0"]["/Filter"])

    def test_progress_bar_is_printed_to_stderr(self):
        module, _state = load_script()

        with tempfile.TemporaryDirectory() as tmpdir:
            input1_path = Path(tmpdir) / "input1.png"
            input2_path = Path(tmpdir) / "input2.png"
            output_path = Path(tmpdir) / "output.pdf"
            input1_path.write_bytes(b"w=20 h=10")
            input2_path.write_bytes(b"w=30 h=10")

            stdout, stderr = capture_output(
                lambda: module.build_pdf([input1_path, input2_path], output_path, quality=80)
            )

        # Encoding is parallel, so completion order is not deterministic; assert the
        # progress bar starts empty, reports every page as encoded, and ends full.
        self.assertIn("Wrote ", stdout)
        self.assertIn("\r[--------------------] 0/2", stderr)
        self.assertIn(f"Encoded {input1_path}", stderr)
        self.assertIn(f"Encoded {input2_path}", stderr)
        self.assertIn("\r[####################] 2/2", stderr)
        self.assertTrue(stderr.endswith("\n"))

    def test_prints_pdf_size_as_percent_of_source_data(self):
        module, _state = load_script()

        with tempfile.TemporaryDirectory() as tmpdir:
            input_path = Path(tmpdir) / "input.png"
            output_path = Path(tmpdir) / "output.pdf"
            input_path.write_bytes(b"w=20 h=10")

            stdout, _stderr = capture_output(lambda: module.build_pdf([input_path], output_path, quality=80))

        self.assertIn("PDF/source size: 33.3% (0.0M/0.0M)\n", stdout)

    def test_directory_input_compresses_files_inside_it(self):
        module, state = load_script()

        with tempfile.TemporaryDirectory() as tmpdir:
            input_dir = Path(tmpdir) / "inputs"
            input_dir.mkdir()
            output_path = Path(tmpdir) / "output.pdf"
            (input_dir / "b.png").write_bytes(b"w=20 h=10")
            (input_dir / "a.png").write_bytes(b"w=30 h=10")

            run_quietly(lambda: module.main([str(input_dir), str(output_path)]))

        # Parallel encoding: both files are compressed, order of completion is unspecified.
        self.assertCountEqual([(10, 30, 3), (10, 20, 3)], [call["shape"] for call in state.encoded])

    def test_directory_input_asserts_no_subdirectories(self):
        module, _state = load_script()

        with tempfile.TemporaryDirectory() as tmpdir:
            input_dir = Path(tmpdir) / "inputs"
            input_dir.mkdir()
            (input_dir / "nested").mkdir()

            with self.assertRaisesRegex(AssertionError, "Input directory contains subdirectories"):
                module.expand_input_paths([input_dir])

    def test_pages_are_assembled_in_input_order_despite_parallel_encoding(self):
        module, state = load_script()

        with tempfile.TemporaryDirectory() as tmpdir:
            paths = []
            for name, spec in (("a.png", b"w=11 h=10"), ("b.png", b"w=22 h=10"), ("c.png", b"w=33 h=10")):
                path = Path(tmpdir) / name
                path.write_bytes(spec)
                paths.append(path)
            output_path = Path(tmpdir) / "output.pdf"

            run_quietly(lambda: module.build_pdf(paths, output_path, quality=80))

        widths = [int(page["/Resources"]["/XObject"]["/Im0"]["/Width"]) for page in state.pages]
        self.assertEqual([11, 22, 33], widths)

    def test_encoding_pool_is_capped_at_worker_count(self):
        module, _state = load_script()

        captured = {}
        real_pool = module.ThreadPoolExecutor

        class SpyPool(real_pool):
            def __init__(self, *args, max_workers=None, **kwargs):
                captured["max_workers"] = max_workers
                super().__init__(*args, max_workers=max_workers, **kwargs)

        module.ThreadPoolExecutor = SpyPool
        try:
            with tempfile.TemporaryDirectory() as tmpdir:
                paths = []
                for i in range(5):
                    path = Path(tmpdir) / f"{i}.png"
                    path.write_bytes(b"w=10 h=10")
                    paths.append(path)
                run_quietly(lambda: module.build_pdf(paths, Path(tmpdir) / "output.pdf", quality=80))
        finally:
            module.ThreadPoolExecutor = real_pool

        self.assertEqual(module.worker_count(), captured.get("max_workers"))
        self.assertLessEqual(captured.get("max_workers"), 16)


class WorkerCountTest(unittest.TestCase):
    def setUp(self):
        self.module = load_real_script()

    def test_caps_at_sixteen_workers(self):
        self.assertEqual(16, self.module.worker_count(cpu_count=32))
        self.assertEqual(16, self.module.worker_count(cpu_count=100))

    def test_uses_cpu_count_when_below_cap(self):
        self.assertEqual(4, self.module.worker_count(cpu_count=4))
        self.assertEqual(16, self.module.worker_count(cpu_count=16))

    def test_never_below_one(self):
        self.assertEqual(1, self.module.worker_count(cpu_count=1))
        self.assertEqual(1, self.module.worker_count(cpu_count=0))

    def test_defaults_to_detected_cpu_count_capped(self):
        self.assertLessEqual(self.module.worker_count(), 16)
        self.assertGreaterEqual(self.module.worker_count(), 1)


class AnyImageFormatTest(unittest.TestCase):
    def setUp(self):
        self.module = load_real_script()

    def _write(self, path, fmt, size=(40, 20)):
        Image.new("RGB", size, (10, 20, 30)).save(path, format=fmt)

    def test_decodes_common_image_formats(self):
        cases = {
            "input.png": "PNG",
            "input.jpg": "JPEG",
            "input.gif": "GIF",
            "input.bmp": "BMP",
            "input.webp": "WEBP",
        }
        with tempfile.TemporaryDirectory() as tmpdir:
            for name, fmt in cases.items():
                path = Path(tmpdir) / name
                self._write(path, fmt)
                jp2_bytes, width, height, _pw, _ph = self.module.image_to_jp2(path, quality=60)
                self.assertEqual((40, 20), (width, height), name)
                self.assertTrue(jp2_bytes, name)

    def test_width_resize_shrinks_encoded_image(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "input.jpg"
            self._write(path, "JPEG", size=(40, 20))
            _jp2, width, height, _pw, _ph = self.module.image_to_jp2(path, quality=60, width_resize=10)
        self.assertEqual((10, 5), (width, height))

    def test_height_resize_shrinks_encoded_image(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "input.jpg"
            self._write(path, "JPEG", size=(40, 20))
            _jp2, width, height, _pw, _ph = self.module.image_to_jp2(path, quality=60, height_resize=10)
        self.assertEqual((20, 10), (width, height))

    def test_fractional_width_resize_is_a_proportion(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "input.jpg"
            self._write(path, "JPEG", size=(40, 20))
            _jp2, width, height, _pw, _ph = self.module.image_to_jp2(path, quality=60, width_resize=0.5)
        self.assertEqual((20, 10), (width, height))

    def test_grayscale_image_is_accepted(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "gray.png"
            Image.new("L", (40, 20), 128).save(path, format="PNG")
            _jp2, width, height, _pw, _ph = self.module.image_to_jp2(path, quality=60)
        self.assertEqual((40, 20), (width, height))


class ParseArgsResizeTest(unittest.TestCase):
    def setUp(self):
        self.module = load_real_script()

    def test_width_resize_flag_sets_width_only(self):
        for argv in (["-w", "1000", "a.png", "o.pdf"], ["--width-resize", "1000", "a.png", "o.pdf"]):
            args = self.module.parse_args(argv)
            self.assertEqual(1000, args.width_resize)
            self.assertIsNone(args.height_resize)

    def test_height_resize_flag_sets_height_only(self):
        for argv in (["-H", "800", "a.png", "o.pdf"], ["--height-resize", "800", "a.png", "o.pdf"]):
            args = self.module.parse_args(argv)
            self.assertEqual(800, args.height_resize)
            self.assertIsNone(args.width_resize)

    def test_no_resize_flag_leaves_both_unset(self):
        args = self.module.parse_args(["a.png", "o.pdf"])
        self.assertIsNone(args.width_resize)
        self.assertIsNone(args.height_resize)

    def test_width_and_height_flags_are_mutually_exclusive(self):
        with self.assertRaises(SystemExit):
            with contextlib.redirect_stderr(io.StringIO()):
                self.module.parse_args(["-w", "100", "-H", "50", "a.png", "o.pdf"])

    def test_integer_resize_parses_as_pixels(self):
        args = self.module.parse_args(["-w", "1000", "a.png", "o.pdf"])
        self.assertEqual(1000, args.width_resize)
        self.assertIsInstance(args.width_resize, int)

    def test_decimal_resize_parses_as_proportion(self):
        args = self.module.parse_args(["-w", "0.5", "a.png", "o.pdf"])
        self.assertEqual(0.5, args.width_resize)
        self.assertIsInstance(args.width_resize, float)
        self.assertEqual(0.25, self.module.parse_args(["-H", "0.25", "a.png", "o.pdf"]).height_resize)

    def test_proportion_must_be_less_than_one(self):
        for bad in ("1.5", "1.1"):
            with self.assertRaises(SystemExit):
                with contextlib.redirect_stderr(io.StringIO()):
                    self.module.parse_args(["-w", bad, "a.png", "o.pdf"])


class ResizeDimensionsTest(unittest.TestCase):
    def setUp(self):
        self.module = load_real_script()

    def test_width_resize_scales_height_proportionally(self):
        self.assertEqual((10, 5), self.module.resize_dimensions(40, 20, width_resize=10))

    def test_height_resize_scales_width_proportionally(self):
        self.assertEqual((20, 10), self.module.resize_dimensions(40, 20, height_resize=10))

    def test_no_resize_returns_original_dimensions(self):
        self.assertEqual((40, 20), self.module.resize_dimensions(40, 20))

    def test_resize_rounds_to_nearest_pixel(self):
        self.assertEqual((1000, 1942), self.module.resize_dimensions(1215, 2359, width_resize=1000))

    def test_width_and_height_together_is_rejected(self):
        with self.assertRaises(ValueError):
            self.module.resize_dimensions(40, 20, width_resize=10, height_resize=5)

    def test_fractional_width_is_a_proportion_of_the_original(self):
        self.assertEqual((500, 300), self.module.resize_dimensions(1000, 600, width_resize=0.5))
        self.assertEqual((250, 150), self.module.resize_dimensions(1000, 600, width_resize=0.25))

    def test_fractional_height_is_a_proportion_of_the_original(self):
        self.assertEqual((500, 300), self.module.resize_dimensions(1000, 600, height_resize=0.5))

    def test_integer_resize_is_still_absolute_pixels(self):
        self.assertEqual((500, 250), self.module.resize_dimensions(1000, 500, width_resize=500))


if __name__ == "__main__":
    unittest.main()
