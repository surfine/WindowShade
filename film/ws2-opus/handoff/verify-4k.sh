#!/bin/zsh
# 4K 專屬複驗：在最終母帶上抽關鍵缺陷，裁切放大存成證據圖。
# 縮放會把接縫、細邊、抗鋸齒與半像素錯位放大到看得見，所以每一項都在 4K 上重量一次。
set -eu
cd /Users/aaron/Documents/WindowShade/film/ws2-opus
SRC=${1:-out/future/gate/draft20-4k.mp4}
DST=${2:-out/future/gate/d20-4k-evidence}
mkdir -p "$DST"

grab() { # grab <frame@30> <name>
  ffmpeg -hide_banner -loglevel error -ss "$(echo "scale=6;$1/30" | bc)" -i "$SRC" -frames:v 1 "$DST/raw-$2.png" -y
}

echo "母帶：$SRC"
for pair in "640:desk-neo" "950:live-air" "1025:live-air-food" "1560:away-air" "1200:close-neo" "1750:pomo-neo"; do
  fr=${pair%%:*}; nm=${pair##*:}
  grab "$fr" "$nm"
  echo "  $nm <- frame $fr"
done

python3 - "$DST" <<'PY'
import sys, os
from PIL import Image
from PIL import ImageEnhance as E
dst = sys.argv[1]
def crop(name, box, out, zoom=2, boost=1.0):
    p = os.path.join(dst, f'raw-{name}.png')
    if not os.path.exists(p): print('  ! 缺', p); return
    im = Image.open(p).convert('RGB'); W, H = im.size
    x0, y0, x1, y1 = box
    c = im.crop((int(W*x0), int(H*y0), int(W*x1), int(H*y1)))
    if boost != 1.0: c = E.Brightness(c).enhance(boost)
    c = c.resize((int(c.size[0]*zoom), int(c.size[1]*zoom)), Image.LANCZOS)
    c.save(os.path.join(dst, f'{out}.png'))
    print(f'  {out}.png  {c.size[0]}x{c.size[1]}  (母帶 {W}x{H})')

# 1. 手機：整個機身（看四角圓度與螢幕有沒有直角穿出）
crop('live-air',       (0.24, 0.00, 0.45, 0.95), 'x1-phone-4k', zoom=2, boost=2.0)
# 2. Air 劉海兩端接縫
crop('away-air',       (0.44, 0.00, 0.67, 0.13), 'x2-air-notch-4k', zoom=4, boost=1.5)
# 3. 島的圓角與內容留白
crop('live-air-food',  (0.40, 0.00, 0.62, 0.13), 'x3-island-4k', zoom=6, boost=1.25)
# 4. 金屬邊框高光
crop('desk-neo',       (0.15, 0.60, 0.90, 0.99), 'x4-metal-4k', zoom=2, boost=1.8)
# 5. Dock 與選單列細線
crop('desk-neo',       (0.00, 0.00, 0.50, 0.05), 'x5-menubar-4k', zoom=5, boost=1.6)
crop('live-air',       (0.20, 0.85, 0.90, 1.00), 'x5b-dock-4k', zoom=3, boost=1.8)
PY
echo "證據圖在 $DST"
