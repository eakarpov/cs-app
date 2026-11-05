"""Render native glyphs from the bundled OFL font. Tool-only: fonttools, Pillow.
Usage: python tool/generate_icons.py [cs|yat|yus]
"""
import json
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / 'assets/fonts/MonomakhUnicode.otf'
OUT = ROOT / 'assets/branding'
CANDIDATES = {'cs': 'ЦС', 'yat': 'Ѣ', 'yus': 'Ѧ'}
BURGUNDY, CREAM, INK = '#850014', '#faf5de', '#060606'
font = TTFont(FONT)
glyphs = font.getGlyphSet()
cmap = font.getBestCmap()

def outline(text):
    bounds_pen = BoundsPen(glyphs)
    x = 0
    for c in text:
        name = cmap[ord(c)]
        glyphs[name].draw(TransformPen(bounds_pen, (1, 0, 0, 1, x, 0)))
        x += glyphs[name].width
    left, bottom, right, top = bounds_pen.bounds
    scale = min(610 / (right-left), 610 / (top-bottom))
    x = 0
    pen = SVGPathPen(glyphs)
    for c in text:
        glyph = glyphs[cmap[ord(c)]]
        glyph.draw(TransformPen(pen, (scale, 0, 0, -scale,
            512 + (x-(left+right)/2)*scale, 512 + (top+bottom)/2*scale)))
        x += glyph.width
    return pen.getCommands()

def image(text, size=1024):
    result = Image.new('RGB', (1024, 1024), BURGUNDY)
    draw = ImageDraw.Draw(result)
    draw.ellipse((64,64,960,960), fill=CREAM, outline=INK, width=9)
    initial = ImageFont.truetype(str(FONT), 1000)
    l,t,r,b = draw.textbbox((0,0),text,font=initial)
    scale = min(610/(r-l),610/(b-t))
    actual = ImageFont.truetype(str(FONT), round(1000*scale))
    l,t,r,b = draw.textbbox((0,0),text,font=actual)
    draw.text((512-(l+r)/2,512-(t+b)/2),text,font=actual,fill=INK)
    return result.resize((size,size),Image.Resampling.LANCZOS)

OUT.mkdir(exist_ok=True, parents=True)
for key, text in CANDIDATES.items():
    image(text).save(OUT / f'{key}.png')
    (OUT / f'{key}.svg').write_text(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" role="img" aria-label="ЦС Словарь: {text}"><rect width="1024" height="1024" fill="{BURGUNDY}"/><circle cx="512" cy="512" r="448" fill="{CREAM}" stroke="{INK}" stroke-width="9"/><path d="{outline(text)}" fill="{INK}"/></svg>\n')
selected = sys.argv[1] if len(sys.argv)>1 else 'cs'
text = CANDIDATES[selected]
image(text).save(OUT / 'app-icon.png')
(OUT / 'app-icon.svg').write_bytes((OUT / f'{selected}.svg').read_bytes())
for density, size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    image(text,size).save(ROOT / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png')
folder = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for item in json.loads((folder/'Contents.json').read_text())['images']:
    if 'filename' in item:
        size = round(float(item['size'].split('x')[0])*float(item['scale'].strip('x')))
        image(text,size).save(folder/item['filename'])
# Contact sheet includes 48px samples to review actual launcher-size legibility.
preview = Image.new('RGB',(1056,440),'#e9e5dc')
draw = ImageDraw.Draw(preview)
label = ImageFont.truetype(str(FONT),26)
for index,(key,title) in enumerate(CANDIDATES.items()):
    x=16+index*352
    preview.paste(image(title,320),(x,16))
    preview.paste(image(title,48),(x+40,362))
    draw.text((x+110,362),title,font=label,fill=INK)
preview.save(OUT/'concepts.png')
print(f'Generated concepts; selected {selected}')
