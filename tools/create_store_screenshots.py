from PIL import Image, ImageDraw, ImageFont, ImageFilter
from pathlib import Path
import math

OUT = Path(r"C:\Users\HP\Downloads\temp_screenshots")
OUT.mkdir(parents=True, exist_ok=True)

W, H = 1080, 1920
BG = (7, 24, 28)
CYAN = (125, 235, 255)
WHITE = (247, 251, 255)
MUTED = (165, 190, 198)
CARD = (19, 43, 49)
CARD2 = (26, 54, 61)
GREEN = (124, 239, 187)
ORANGE = (255, 196, 112)

FONT_DIRS = [
    Path(r"C:\Windows\Fonts"),
    Path(r"C:\Users\HP\AppData\Local\Microsoft\Windows\Fonts"),
]
def font(size, bold=False):
    names = ["Poppins-Bold.ttf", "segoeuib.ttf"] if bold else ["Poppins-Regular.ttf", "segoeui.ttf"]
    for d in FONT_DIRS:
        for n in names:
            p = d / n
            if p.exists(): return ImageFont.truetype(str(p), size)
    return ImageFont.load_default()

F_TITLE = font(62, True)
F_SUB = font(27)
F_H = font(34, True)
F_BODY = font(25)
F_SMALL = font(21)
F_TINY = font(18)
F_NUM = font(38, True)

def rounded(draw, box, radius=24, fill=CARD, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)

def text(draw, xy, value, f=F_BODY, fill=WHITE, anchor=None):
    draw.text(xy, value, font=f, fill=fill, anchor=anchor)

def wrap(draw, value, xy, max_width, f=F_BODY, fill=MUTED, gap=8):
    words, line, lines = value.split(), "", []
    for word in words:
        trial = (line + " " + word).strip()
        if draw.textlength(trial, font=f) <= max_width: line = trial
        else:
            lines.append(line); line = word
    if line: lines.append(line)
    y = xy[1]
    for line in lines:
        text(draw, (xy[0], y), line, f, fill)
        y += f.size + gap
    return y

def base(title, subtitle, accent=CYAN):
    im = Image.new("RGB", (W, H), BG)
    glow = Image.new("RGBA", (W, H), (0,0,0,0)); gd = ImageDraw.Draw(glow)
    gd.ellipse((-260, -220, 650, 560), fill=(*accent, 45))
    gd.ellipse((700, 1300, 1350, 2050), fill=(56, 112, 128, 28))
    glow = glow.filter(ImageFilter.GaussianBlur(90)); im = Image.alpha_composite(im.convert("RGBA"), glow)
    d = ImageDraw.Draw(im)
    text(d, (64, 70), "LIMS", font(25, True), accent)
    text(d, (64, 145), title, F_TITLE, WHITE)
    wrap(d, subtitle, (68, 235), 900, F_SUB, MUTED, 6)
    d.line((64, 350, 1016, 350), fill=(80, 120, 129), width=2)
    return im.convert("RGB"), d

def topbar(d, label):
    rounded(d, (54, 392, 1026, 492), 26, CARD2)
    d.ellipse((78, 417, 128, 467), fill=CYAN)
    text(d, (103, 442), "✓", font(27, True), BG, "mm")
    text(d, (154, 420), label, F_H, WHITE)
    text(d, (154, 460), "Offline-first workspace", F_TINY, MUTED)

def stat(d, x, y, w, label, value, accent=CYAN):
    rounded(d, (x, y, x+w, y+150), 24, CARD)
    text(d, (x+24, y+25), label, F_TINY, MUTED)
    text(d, (x+24, y+78), value, F_NUM, accent)

def nav(d, active):
    y = 1780
    rounded(d, (45, y, 1035, 1870), 30, (14, 35, 41))
    labels = [("⌂", "Home"), ("▦", "Products"), ("＋", "Billing"), ("▤", "Invoices"), ("⚙", "Settings")]
    for i, (icon, label) in enumerate(labels):
        x = 145 + i*200
        col = CYAN if i == active else MUTED
        text(d, (x, y+30), icon, font(30, True), col, "mm")
        text(d, (x, y+70), label, F_TINY, col, "mm")

def dashboard():
    im, d = base("Know your business at a glance", "Revenue, pending payments, products, and recent invoices in one calm dashboard.")
    topbar(d, "Counter Billing")
    stat(d, 54, 530, 300, "TOTAL REVENUE", "$12,480", GREEN)
    stat(d, 390, 530, 300, "PENDING", "$1,240", ORANGE)
    stat(d, 726, 530, 300, "INVOICES", "148", CYAN)
    rounded(d, (54, 710, 1026, 870), 26, CARD)
    text(d, (82, 742), "Estimated profit margin", F_BODY, MUTED)
    text(d, (944, 742), "34.6%", F_H, CYAN, "ra")
    text(d, (82, 810), "Healthy month", F_SMALL, GREEN)
    rounded(d, (54, 916, 1026, 1280), 26, CARD)
    text(d, (82, 950), "Recent invoices", F_H)
    text(d, (942, 960), "View all  ›", F_SMALL, CYAN, "ra")
    rows = [("INV-1048", "Paid · Today", "$420.00", GREEN), ("INV-1047", "Payment pending", "$185.50", ORANGE), ("INV-1046", "Paid · Yesterday", "$760.00", GREEN)]
    for i, (a,b,c,col) in enumerate(rows):
        yy = 1035+i*78
        d.ellipse((82, yy, 124, yy+42), fill=(43, 78, 86)); text(d, (103, yy+21), "▤", F_SMALL, CYAN, "mm")
        text(d, (150, yy), a, F_BODY); text(d, (150, yy+35), b, F_TINY, col); text(d, (970, yy+19), c, F_BODY, WHITE, "ra")
    rounded(d, (54, 1320, 1026, 1685), 26, CARD)
    text(d, (82, 1355), "Quick actions", F_H)
    actions = [("＋", "New invoice"), ("▦", "Add product"), ("▤", "Templates"), ("◉", "View orders")]
    for i,(ico,lab) in enumerate(actions):
        x = 82 + (i%2)*455; y = 1430 + (i//2)*105
        rounded(d, (x,y,x+410,y+78), 18, CARD2)
        text(d, (x+28,y+39), ico, F_H, CYAN, "mm"); text(d, (x+72,y+39), lab, F_BODY, WHITE, "lm")
    nav(d, 0); return im

def products():
    im,d = base("Your catalog, always ready", "Add, search, edit, and reuse products while creating invoices in seconds.", GREEN)
    topbar(d, "Products")
    rounded(d, (54, 530, 1026, 620), 20, CARD2); text(d, (88, 575), "⌕", F_H, CYAN, "mm"); text(d, (130, 575), "Search by product name", F_BODY, MUTED, "lm")
    text(d, (54, 690), "12 products", F_H); rounded(d, (792, 662, 1026, 722), 18, CYAN); text(d, (909, 692), "+  Add product", F_BODY, BG, "mm")
    items=[("Cappuccino", "Coffee · In stock", "$4.50", GREEN), ("Chocolate Cake", "Dessert · In stock", "$7.00", GREEN), ("Breakfast Combo", "Meal · 8 left", "$12.50", ORANGE), ("Fresh Lemonade", "Drinks · In stock", "$3.75", GREEN)]
    for i,(a,b,c,col) in enumerate(items):
        y=770+i*180; rounded(d,(54,y,1026,y+145),24,CARD)
        d.ellipse((82,y+32,150,y+100),fill=(38,75,80)); text(d,(116,y+66),"▦",font(30,True),CYAN,"mm")
        text(d,(180,y+34),a,F_H); text(d,(180,y+87),b,F_SMALL,col); text(d,(970,y+60),c,F_BODY,WHITE,"ra"); text(d,(970,y+105),"Edit  ›",F_TINY,CYAN,"ra")
    rounded(d,(54,1510,1026,1670),24,CARD2); text(d,(86,1550),"Fast search",F_H); wrap(d,"Find any product instantly and keep your catalog organized as your business grows.",(86,1600),850,F_SMALL,MUTED,4)
    nav(d,1); return im

def billing():
    im,d = base("Turn a sale into an invoice", "Fast billing with quantity controls, a live cart, and locally generated PDF invoices.", ORANGE)
    topbar(d,"Billing")
    rounded(d,(54,530,1026,620),20,CARD2); text(d,(88,575),"⌕",F_H,CYAN,"mm"); text(d,(130,575),"Search products",F_BODY,MUTED,"lm")
    text(d,(54,690),"Choose products",F_H)
    products=[("Cappuccino","$4.50"),("Chocolate Cake","$7.00"),("Breakfast Combo","$12.50")]
    for i,(a,b) in enumerate(products):
        y=750+i*105; rounded(d,(54,y,1026,y+82),20,CARD); text(d,(88,y+41),a,F_BODY,"white","lm"); text(d,(640,y+41),b,F_BODY,CYAN,"lm"); rounded(d,(846,y+18,990,y+64),14,CARD2); text(d,(918,y+41),"−  1  +",F_SMALL,WHITE,"mm")
    rounded(d,(54,1095,1026,1430),26,CARD2); text(d,(84,1132),"Current cart",F_H); text(d,(84,1200),"Cappuccino × 2",F_BODY); text(d,(970,1200),"$9.00",F_BODY,WHITE,"ra"); text(d,(84,1250),"Chocolate Cake × 1",F_BODY); text(d,(970,1250),"$7.00",F_BODY,WHITE,"ra"); d.line((84,1300,996,1300),fill=(75,110,118),width=2); text(d,(84,1340),"Total",F_H); text(d,(970,1340),"$16.00",F_H,CYAN,"ra")
    rounded(d,(54,1480,1026,1600),24,CYAN); text(d,(540,1540),"Generate invoice  →",F_H,BG,"mm")
    rounded(d,(54,1640,1026,1720),20,CARD); text(d,(84,1680),"PDF saved locally on your device",F_SMALL,GREEN,"lm"); nav(d,2); return im

def templates():
    im,d = base("Make every invoice yours", "Choose a reusable template with your logo, currency, notes, terms, and accent color.", CYAN)
    topbar(d,"Invoice Templates")
    text(d,(54,690),"Saved templates",F_H); rounded(d,(805,662,1026,722),18,CYAN); text(d,(915,692),"+  New",F_BODY,BG,"mm")
    for i,(name,desc,sel) in enumerate([("Modern Blue","USD · Thank you for your business",True),("Minimal Receipt","USD · Due on receipt",False)]):
        y=760+i*280; rounded(d,(54,y,1026,y+235),26,CARD)
        rounded(d,(84,y+30,300,y+205),14,(235,247,249)); d.rectangle((112,y+60,270,y+78),fill=(25,87,102)); d.rectangle((112,y+98,254,y+110),fill=(150,180,186)); d.rectangle((112,y+128,254,y+140),fill=(150,180,186)); d.rectangle((112,y+158,220,y+170),fill=(150,180,186))
        text(d,(350,y+42),name,F_H); text(d,(350,y+94),desc,F_SMALL,MUTED); text(d,(350,y+150),"Selected template" if sel else "Use this template",F_SMALL,GREEN if sel else CYAN)
        if sel: rounded(d,(850,y+35,976,y+78),14,GREEN); text(d,(913,y+56),"Active",F_TINY,BG,"mm")
    rounded(d,(54,1380,1026,1615),26,CARD2); text(d,(84,1420),"Designed for consistency",F_H); wrap(d,"Save your preferred invoice details once and keep every PDF polished and on-brand.",(84,1480),850,F_BODY,MUTED,7)
    nav(d,3); return im

def orders():
    im,d = base("Orders, without the noise", "Receive nearby customer orders, prepare them, and keep your workflow moving.", GREEN)
    topbar(d,"Nearby Orders")
    rounded(d,(54,530,1026,650),24,CARD2); text(d,(88,570),"◉",F_H,GREEN,"lm"); text(d,(145,570),"Shop visibility",F_BODY,MUTED,"lm"); text(d,(145,612),"Visible to nearby customers",F_SMALL,GREEN,"lm"); rounded(d,(914,558,980,622),30,GREEN); d.ellipse((948,568,970,590),fill=(12,55,50))
    text(d,(54,730),"Recent orders",F_H)
    for i,(num,customer,status,total,col) in enumerate([("ORD-208","Aarav Mehta","Preparing","$24.50",ORANGE),("ORD-207","Sara Khan","Ready","$18.00",GREEN),("ORD-206","Noah Williams","Completed","$42.75",CYAN)]):
        y=800+i*185; rounded(d,(54,y,1026,y+150),24,CARD); text(d,(88,y+28),num,F_SMALL,CYAN); text(d,(88,y+70),customer,F_H); text(d,(88,y+112),status,F_SMALL,col); text(d,(970,y+62),total,F_H,WHITE,"ra"); text(d,(970,y+108),"Open  ›",F_TINY,CYAN,"ra")
    rounded(d,(54,1395,1026,1625),26,CARD2); text(d,(84,1435),"Offline-first workflow",F_H); wrap(d,"Orders and catalog changes stay on this device and sync through nearby connections when available.",(84,1495),860,F_BODY,MUTED,7)
    nav(d,0); return im

for name, maker in [("01_dashboard_overview",dashboard),("02_product_catalog",products),("03_fast_billing",billing),("04_invoice_templates",templates),("05_nearby_orders",orders)]:
    maker().save(OUT / f"{name}.png", optimize=True)

print(f"Created {len(list(OUT.glob('*.png')))} screenshots in {OUT}")
