# -*- coding: utf-8 -*-
# 预览：睡觉姿势放在床上两种落点的对比（调整前 / 调整后）
from PIL import Image
import os
R = r"C:/Users/蔡璟熙/Documents/新建游戏项目/resources/Farm RPG - Tiny Asset Pack - (All in One)"
OUT = r"C:/Users/蔡璟熙/Documents/新建游戏项目/outputs"
beds = Image.open(os.path.join(R, "Objects/Interior/Beds.png")).convert("RGBA")
bed = beds.crop((7, 269, 7 + 33, 269 + 34))
sleep = Image.open(os.path.join(R, "Character/Character/Pre-made/Josh/Sleep.png")).convert("RGBA")
f0 = sleep.crop((0, 0, 32, 32))
S = 8


def up(im):
    return im.resize((im.width * S, im.height * S), Image.NEAREST)


# 精灵左上角 = 玩家原点 + (-16,-32)（ToolSprite 画在原点上方 16px、居中 32x32 帧）
def shot(land, fname):
    spr_tl = (land[0] - 16, land[1] - 32)   # 相对床左上角
    cv = Image.new("RGBA", (33 * S, 34 * S), (217, 168, 138, 255))
    cv.alpha_composite(up(bed), (0, 0))
    cv.alpha_composite(up(f0), (spr_tl[0] * S, spr_tl[1] * S))
    cv.save(os.path.join(OUT, fname))


shot((16, 17), "_bed_before.png")   # 旧：床中心
shot((16, 33), "_bed_after.png")    # 新：床左上角 + (16,33)
print("ok")
