# Builds Underdog.rbxlx: the Freight Yard baked in as real Parts, plus the Server/Client scripts.
import math, random
srv = open('Server.lua').read(); cli = open('Client.lua').read()
assert ']]>' not in srv + cli
MAT = dict(Plastic=256, SmoothPlastic=272, Neon=288, Wood=512, Concrete=816, Asphalt=884, CorrugatedMetal=1040, DiamondPlate=1056, Metal=1088)
n = [0]
def ref():
    n[0] += 1; return 'RBX%d' % n[0]
parts = []
def rot_y(a):
    c, s = math.cos(a), math.sin(a)
    return [c, 0, s, 0, 1, 0, -s, 0, c]
def mul(A, B):
    return [sum(A[i*3+k]*B[k*3+j] for k in range(3)) for i in range(3) for j in range(3)]
def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return [c, -s, 0, s, c, 0, 0, 0, 1]
def part(name, size, pos, color, mat='SmoothPlastic', ry=0, collide=True, transp=0, shape=1, rot=None, cls='Part'):
    parts.append(dict(name=name, size=size, pos=pos, color=color, mat=mat, rot=rot or rot_y(math.radians(ry)), collide=collide, transp=transp, shape=shape, cls=cls))
    return parts[-1]
def block(size, pos, color, mat='SmoothPlastic', ry=0, collide=True):
    return part('Block', size, pos, color, mat, ry, collide)
RGB = lambda r, g, b: (r, g, b)

HX, HZ = 70, 40
block((HX*2+6, 2, HZ*2+6), (0, -1, 0), RGB(70, 68, 78), 'Concrete')
for x in range(-60, 61, 20): block((8, .06, .6), (x, .04, 0), RGB(230, 190, 40), collide=False)
for z in (-34, 34): block((HX*2, .06, .8), (0, .04, z), RGB(230, 190, 40), collide=False)
block((900, 2, 900), (0, -3, 0), RGB(50, 46, 54), 'Asphalt')
for size, pos in [((HX*2+4, 4, 2), (0, 2, -HZ-1)), ((HX*2+4, 4, 2), (0, 2, HZ+1)), ((2, 4, HZ*2), (-HX-1, 2, 0)), ((2, 4, HZ*2), (HX+1, 2, 0))]:
    block(size, pos, RGB(150, 148, 140), 'Concrete')
for size, pos in [((HX*2+4, 80, 2), (0, 40, -HZ-1)), ((HX*2+4, 80, 2), (0, 40, HZ+1)), ((2, 80, HZ*2), (-HX-1, 40, 0)), ((2, 80, HZ*2), (HX+1, 40, 0))]:
    part('Wall', size, pos, RGB(255, 255, 255), transp=1)

CC = [RGB(168, 58, 38), RGB(42, 90, 138), RGB(58, 122, 68), RGB(200, 138, 26), RGB(216, 208, 198), RGB(42, 122, 122), RGB(138, 90, 58)]
cnt = [0]
def container(x, y, z, ry):
    cnt[0] += 1; col = CC[cnt[0] % len(CC)]
    L, H, W = 20, 8.4, 8
    part('Container', (L, H, W), (x, y+H/2, z), col, 'CorrugatedMetal', ry)
    R = rot_y(math.radians(ry))
    def child(size, off, c, m='Metal'):
        wp = (x + R[0]*off[0] + R[2]*off[2], y + H/2 + off[1], z + R[6]*off[0] + R[8]*off[2])
        part('Detail', size, wp, c, m, ry, collide=False)
    dark = RGB(26, 26, 30)
    for i in range(-4, 5): child((.4, H-.4, W+.3), (i*2.2, 0, 0), dark)
    child((.5, H, W+.2), (L/2, 0, 0), dark); child((.5, H, W+.2), (-L/2, 0, 0), dark)
    child((.3, H-1, 3.4), (L/2+.3, 0, -2), RGB(110, 114, 126)); child((.3, H-1, 3.4), (L/2+.3, 0, 2), RGB(110, 114, 126))
    child((.2, 1.4, 6), (-4, H/2-1.8, W/2+.2), RGB(240, 236, 224), 'SmoothPlastic')
def stack(x, z, ry, lv):
    for i in range(lv): container(x, i*8.4, z, ry)
layout = [(-50, -24, 0, 2), (-50, 24, 0, 1), (-32, -18, 90, 1), (-30, 28, 0, 2), (-14, -28, 0, 1), (-12, 18, 90, 1), (0, -18, 90, 1)]
for x, z, ry, lv in layout:
    stack(x, z, ry, lv); stack(-x, -z, ry, lv)

CW = 14; Y = RGB(232, 176, 28); GR = RGB(96, 98, 110)
block((34, 1, 12), (0, CW, 0), GR, 'DiamondPlate')
for sz in (-1, 1): block((34, 3, .4), (0, CW+2, sz*5.8), Y, 'Metal')
for sx in (-1, 1):
    block((.4, 3, 12), (sx*16.8, CW+2, 0), Y, 'Metal')
    for sz in (-1, 1): block((1.4, CW, 1.4), (sx*15, CW/2, sz*5), Y, 'Metal')
    for i in range(1, CW+1): block((1.6, 1, 6), (sx*(17+(CW-i)*1.6+.8), i-.5, 0), GR, 'DiamondPlate')
def gantry(x, z):
    for a in (-26, 26):
        for b in (-14, 14): block((2.6, 70, 2.6), (x+a, 35, z+b), Y, 'Metal', collide=False)
    block((60, 4, 4), (x, 70, z-14), Y, 'Metal', collide=False); block((60, 4, 4), (x, 70, z+14), Y, 'Metal', collide=False)
    block((6, 6, 30), (x-10, 66, z), RGB(60, 62, 72), 'Metal', collide=False)
gantry(0, -130); gantry(-120, 140); gantry(130, 150)
rnd = random.Random(7)
for i in range(36):
    a = i/36*math.pi*2; r = 520 + rnd.uniform(0, 160); w, d, h = rnd.uniform(30, 70), rnd.uniform(30, 70), rnd.uniform(90, 340)
    cx, cz = math.cos(a)*r, math.sin(a)*r
    block((w, h, d), (cx, h/2-3, cz), RGB(88+rnd.randint(0, 30), 92+rnd.randint(0, 24), 118), 'Concrete', collide=False)
    for k in range(1, 6):
        p = part('Windows', (w+.2, h*.05, d+.2), (cx, k*h/6-3-h/2+h/2*0+(-h/2+h/2), cz), RGB(255, 214, 140), 'Neon', collide=False, transp=.55)
        p['pos'] = (cx, (h/2-3) - h/2 + k*h/6, cz)
for x in (-60, -20, 20, 60):
    for z in (-36, 36):
        block((.8, 18, .8), (x, 9, z), RGB(90, 94, 104), 'Metal'); block((3, .8, 1.6), (x, 18.4, z), RGB(255, 240, 200), 'Neon', collide=False)
rc = random.Random(21)
for i in range(22):
    x, z = rc.uniform(-62, 62), rc.uniform(-34, 34)
    if abs(x) > 8 or abs(z) > 10:
        if rc.random() < .5:
            s = rc.uniform(2.4, 3.6); part('Crate', (s, s, s), (x, s/2, z), RGB(150, 112, 70), 'Wood', rc.uniform(0, 90))
        else:
            col = rc.choice([RGB(196, 42, 30), RGB(42, 90, 138), RGB(216, 160, 32)])
            part('Barrel', (3.4, 2.4, 2.4), (x, 1.7, z), col, 'Metal', shape=2, rot=rot_z(math.pi/2))
part('SpawnLocation', (6, 1, 6), (-58, .5, 0), RGB(255, 220, 140), 'Neon', transp=.6, cls='SpawnLocation')

def c3(c): return (0xFF000000 | (c[0] << 16) | (c[1] << 8) | c[2])
def xml_part(p):
    r = p['rot']
    s = '<Item class="%s" referent="%s"><Properties><string name="Name">%s</string><bool name="Anchored">true</bool><bool name="CanCollide">%s</bool><token name="Material">%d</token><Color3uint8 name="Color3uint8">%d</Color3uint8><float name="Transparency">%s</float>' % (p['cls'], ref(), p['name'], 'true' if p['collide'] else 'false', MAT[p['mat']], c3(p['color']), p['transp'])
    s += '<Vector3 name="size"><X>%.4f</X><Y>%.4f</Y><Z>%.4f</Z></Vector3>' % tuple(p['size'])
    s += '<CoordinateFrame name="CFrame"><X>%.4f</X><Y>%.4f</Y><Z>%.4f</Z>' % tuple(p['pos'])
    for i, nm in enumerate(['R00', 'R01', 'R02', 'R10', 'R11', 'R12', 'R20', 'R21', 'R22']): s += '<%s>%.6f</%s>' % (nm, r[i], nm)
    s += '</CoordinateFrame>'
    if p['shape'] != 1 and p['cls'] == 'Part': s += '<token name="shape">%d</token>' % p['shape']
    if p['cls'] == 'SpawnLocation': s += '<bool name="Neutral">true</bool>'
    return s + '</Properties></Item>'
def scr(cls, name, src, extra=''):
    return '<Item class="%s" referent="%s"><Properties><string name="Name">%s</string>%s<ProtectedString name="Source"><![CDATA[%s]]></ProtectedString></Properties></Item>' % (cls, ref(), name, extra, src)
def svc(cls, name, inner='', props=''):
    return '<Item class="%s" referent="%s"><Properties><string name="Name">%s</string>%s</Properties>%s</Item>' % (cls, ref(), name, props, inner)
hdr = '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
model = svc('Model', 'FreightYard', ''.join(xml_part(p) for p in parts))
x = hdr + svc('Workspace', 'Workspace', model) + '\n'
x += svc('Lighting', 'Lighting', '', '<float name="ClockTime">17.4</float><float name="Brightness">2.2</float>') + '\n'
x += svc('ReplicatedStorage', 'ReplicatedStorage') + '\n'
x += svc('ServerScriptService', 'ServerScriptService', scr('Script', 'Server', srv) + scr('LocalScript', 'Client', cli, '<bool name="Disabled">true</bool>')) + '\n'
x += svc('StarterGui', 'StarterGui') + '\n'
x += svc('StarterPlayer', 'StarterPlayer', svc('StarterPlayerScripts', 'StarterPlayerScripts') + svc('StarterCharacterScripts', 'StarterCharacterScripts')) + '\n</roblox>\n'
open('Underdog.rbxlx', 'w').write(x)
import xml.dom.minidom as m; m.parseString(x.encode()); print('parts', len(parts), 'bytes', len(x))
