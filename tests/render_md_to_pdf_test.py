import base64
import pathlib
import subprocess
import tempfile
import unittest

from pypdf import PdfReader


SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "render_md_to_pdf"
STYLES = {
    "essay": ("Green Book", "GREEN BOOK", (19 / 255, 63 / 255, 44 / 255)),
    "commodware": ("C64 Blue Book", "BLUE BOOK", (53 / 255, 40 / 255, 121 / 255)),
    "palware": ("Ultraviolet Book", "ULTRAVIOLET BOOK", None),
}
HEADINGS = """# 1. Chapter
{: #chapter}

## 1.1 Section
{: #section}

### 1.1.1 Leaf
{: #leaf}

#### When the test applies

Body text with [an external link](https://example.com/reference).
"""
TOC = """- [1. Chapter](#chapter)
  - [1.1 Section](#section)
    - [1.1.1 Leaf](#leaf)
"""


class MarkdownPdfTest(unittest.TestCase):
    def render(self, style, source, directory, *options):
        markdown = pathlib.Path(directory) / "document.md"
        markdown.write_text(source)
        result = subprocess.run(
            [str(SCRIPT), style, str(markdown), *options],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(markdown.read_text(), source)
        pdf = pathlib.Path(result.stdout.strip())
        text = subprocess.check_output(
            ["pdftotext", "-layout", str(pdf), "-"], text=True,
        )
        return pdf, PdfReader(pdf), text

    def test_styles_covers_contents_and_links(self):
        for style, (label, banner, background) in STYLES.items():
            for explicit_toc in (False, True):
                with self.subTest(style=style, explicit_toc=explicit_toc), tempfile.TemporaryDirectory() as directory:
                    source = "# Heading regression\n\n" + (TOC if explicit_toc else "") + "\n" + HEADINGS
                    pdf, reader, text = self.render(style, source, directory)
                    self.assertEqual(pdf, pathlib.Path(directory) / "document.pdf")
                    self.assertEqual(reader.metadata.title, f"{label}: Heading regression")
                    self.assertIn(banner, reader.pages[0].extract_text())
                    self.assertEqual(tuple(reader.pages[0].mediabox[2:]), (1024, 1366))
                    contents = text.split("Contents", 1)[1].split("\f", 1)[0]
                    self.assertEqual(text.count("Contents"), 1)
                    for heading in ("1. Chapter", "1.1 Section", "1.1.1 Leaf"):
                        self.assertEqual(contents.count(heading), 1)
                    self.assertNotIn("Heading regression", contents)
                    self.assertNotIn("When the test applies", contents)
                    self.assertIn("When the test applies", text)
                    operations = reader.pages[0].get_contents().operations
                    rectangles = [args for args, op in operations if op == b"re"]
                    if background is None:
                        self.assertEqual(rectangles, [], "Transparent covers must not paint a page background")
                    else:
                        self.assertTrue(rectangles)
                        colors = [args for args, op in operations if op == b"rg"]
                        self.assertTrue(any(all(abs(float(x) - y) < 0.001 for x, y in zip(color, background)) for color in colors))
                    annotations = [a.get_object() for page in reader.pages for a in (page["/Annots"].get_object() if "/Annots" in page else [])]
                    self.assertTrue(any(a.get("/A", {}).get("/URI") == "https://example.com/reference" for a in annotations))
                    self.assertTrue(any("/Dest" in a or a.get("/A", {}).get("/S") == "/GoTo" for a in annotations))

    def test_prose_lists_math_tables_code_and_relative_image(self):
        with tempfile.TemporaryDirectory() as directory:
            output = pathlib.Path(directory) / "output"
            output.mkdir()
            # Tiny PNG keeps the fixture independent of image libraries.
            (pathlib.Path(directory) / "figure.png").write_bytes(base64.b64decode(
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNQaHAAAAGkAOGt06eBAAAAAElFTkSuQmCC"
            ))
            source = r"""# Essay regression

- Keep this opening list item.
- Keep this second item.

## A section

Inline math \(x^2 + y^2\) and display math:

\[ E = mc^2 \]

| Property | Meaning |
| --- | --- |
| Cognition | Useful representations |

```
Plain code: λ → value
```

![A local figure](figure.png)
"""
            pdf, reader, text = self.render("essay", source, directory, "--output", str(output))
            self.assertEqual(pdf, output / "document.pdf")
            for expected in ("Keep this opening list item.", "Keep this second item.", "Cognition", "Useful representations", "Plain code:"):
                self.assertIn(expected, text)
            self.assertTrue(any(page.images for page in reader.pages))

    def test_cli_rejects_missing_or_unknown_style(self):
        for args in ([], ["analysis", "document.md"], ["essay"]):
            with self.subTest(args=args):
                result = subprocess.run([str(SCRIPT), *args], capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("essay", result.stderr)


if __name__ == "__main__":
    unittest.main()
