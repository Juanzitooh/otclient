#!/usr/bin/env python3
"""Render the transparent Elemental signature reveal from its SVG source."""

from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent
SIGNATURE = ROOT.parent / "identity" / "brand-package" / "elemental-signature-dark.svg"
OUTPUT = ROOT / "elemental-logo-reveal.mov"
WIDTH, HEIGHT, FPS = 1920, 1080, 24
LOGO_X, LOGO_Y, LOGO_WIDTH = 300, 390, 1320
LOGO_HEIGHT = 399
DURATION = 6
FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf"
TAGLINE = "COLETE, CONSTRUA, LUTE E VIVA ESSA AVENTURA"


def smoothstep(value: float) -> float:
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def progress(time: float, start: float, end: float) -> float:
    return smoothstep((time - start) / (end - start))


def load_signature() -> Image.Image:
    with tempfile.TemporaryDirectory(prefix="elemental-logo-") as temporary:
        png_path = Path(temporary) / "signature.png"
        subprocess.run(
            [
                "inkscape",
                str(SIGNATURE),
                f"--export-filename={png_path}",
                f"--export-width={LOGO_WIDTH}",
            ],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        return Image.open(png_path).convert("RGBA")


def draw_tracked_text(
    draw: ImageDraw.ImageDraw,
    text: str,
    center_x: float,
    baseline: int,
    font: ImageFont.FreeTypeFont,
    opacity: float,
) -> None:
    tracking = 1.2
    advances = [font.getlength(character) for character in text]
    text_width = sum(advances) + tracking * max(0, len(text) - 1)
    cursor_x = center_x - text_width / 2
    fill = (247, 241, 228, round(255 * opacity))
    for character, advance in zip(text, advances):
        draw.text((round(cursor_x), baseline), character, font=font, fill=fill, anchor="ls")
        cursor_x += advance + tracking


def make_frame(time: float, signature: Image.Image, font: ImageFont.FreeTypeFont) -> Image.Image:
    frame = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))

    logo_opacity = progress(time, 0.25, 0.85)
    icon_reveal = progress(time, 0.25, 1.38)
    word_reveal = progress(time, 1.38, 4.32)
    reveal_width = round(330 * icon_reveal + (LOGO_WIDTH - 330) * word_reveal)

    if logo_opacity > 0 and reveal_width > 0:
        clip = Image.new("L", signature.size, 0)
        ImageDraw.Draw(clip).rectangle((0, 0, reveal_width, signature.height), fill=255)
        alpha = ImageChops.multiply(signature.getchannel("A"), clip)
        alpha = alpha.point([round(channel * logo_opacity) for channel in range(256)])
        revealed_signature = signature.copy()
        revealed_signature.putalpha(alpha)
        frame.alpha_composite(revealed_signature, (LOGO_X, LOGO_Y))

    tagline_opacity = progress(time, 3.82, 4.50) * (1.0 - progress(time, 5.60, 6.0))
    if tagline_opacity > 0:
        draw_tracked_text(
            ImageDraw.Draw(frame),
            TAGLINE,
            center_x=1102,
            baseline=683,
            font=font,
            opacity=tagline_opacity,
        )

    fade_out = 1.0 - progress(time, 5.60, 6.0)
    if fade_out < 1:
        alpha = frame.getchannel("A").point([round(channel * fade_out) for channel in range(256)])
        frame.putalpha(alpha)
    return frame


def encode_frames(frames) -> None:
    if not shutil.which("ffmpeg"):
        raise RuntimeError("ffmpeg não foi encontrado no sistema.")
    command = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "rawvideo", "-pix_fmt", "rgba",
        "-s:v", f"{WIDTH}x{HEIGHT}", "-r", str(FPS), "-i", "-", "-an",
        "-c:v", "qtrle", "-pix_fmt", "argb", str(OUTPUT),
    ]
    process = subprocess.Popen(command, stdin=subprocess.PIPE)
    assert process.stdin is not None
    try:
        for frame in frames:
            process.stdin.write(frame.tobytes())
    finally:
        process.stdin.close()
    if process.wait() != 0:
        raise RuntimeError(f"ffmpeg falhou ao criar {OUTPUT.name}.")


def main() -> None:
    signature = load_signature()
    font = ImageFont.truetype(FONT_PATH, 19)
    frames = (
        make_frame(frame / FPS, signature, font)
        for frame in range(DURATION * FPS)
    )
    encode_frames(frames)
    print(f"Criado: {OUTPUT}")


if __name__ == "__main__":
    main()
