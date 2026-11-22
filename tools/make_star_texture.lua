-- Generates ShowItems\Textures\ShowItemsStar.tga: the favorite star of the character window menu.
-- Run from the project root: lua5.1.exe tools\make_star_texture.lua
--
-- 64x32, 32-bit uncompressed TGA, top-left origin, two 32x32 cells side by side:
--   left  (texture coordinates 0 .. 0.5): an empty star: a thick white ring around a dark, half transparent
--         middle, so it stays readable on bright (yellow) icons,
--   right (texture coordinates 0.5 .. 1): a filled star, white (the addon tints it gold).
-- Both have a black edge, and the points of the star are rounded. The addon tints the white with the vertex
-- color. Edges are smoothed by 4x4 supersampling.

local W, H, CELL = 64, 32, 32
local CX, CY = 16, 16.8
local OUTER, INNER = 15.5, 7.4 -- radius of the points and of the notches before the points are rounded
local ROUND = 2.2 -- rounding of the points (the star is made smaller by it and grown back)
local OUTLINE = 1.5 -- black edge outside the star
local RING = 3.0 -- white ring of the empty star
local INNER_EDGE = 1.3 -- black edge inside the ring of the empty star
local FILL_ALPHA = 0.55 -- darkness of the middle of the empty star
local SAMPLES = 4

-- the ten corners of the star, the first one points up
local points = {}
for i = 0, 9 do
    local radius = (i % 2 == 0) and OUTER or INNER
    local angle = math.pi / 2 + i * math.pi / 5
    points[#points + 1] = { CX + radius * math.cos(angle), CY - radius * math.sin(angle) }
end

-- the polygon moved inward by t: every edge moves by t, the corners are where the moved edges meet
local function Inset(poly, t)
    local area = 0
    for i = 1, #poly do
        local a, b = poly[i], poly[i % #poly + 1]
        area = area + (a[1] * b[2] - b[1] * a[2])
    end
    local sign = area > 0 and 1 or -1 -- orientation of the polygon on the screen
    local lines = {}
    for i = 1, #poly do
        local a, b = poly[i], poly[i % #poly + 1]
        local dx, dy = b[1] - a[1], b[2] - a[2]
        local len = math.sqrt(dx * dx + dy * dy)
        -- the inward normal of the edge
        local nx, ny = -dy / len * sign, dx / len * sign
        lines[i] = { px = a[1] + nx * t, py = a[2] + ny * t, dx = dx, dy = dy }
    end
    local out = {}
    for i = 1, #poly do
        local l1, l2 = lines[(i - 2) % #poly + 1], lines[i]
        local det = l1.dx * l2.dy - l1.dy * l2.dx
        local s = ((l2.px - l1.px) * l2.dy - (l2.py - l1.py) * l2.dx) / det
        out[i] = { l1.px + s * l1.dx, l1.py + s * l1.dy }
    end
    return out
end

local inset = Inset(points, ROUND)

local function SegmentDistance(px, py, a, b)
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local t = ((px - a[1]) * dx + (py - a[2]) * dy) / (dx * dx + dy * dy)
    t = math.max(0, math.min(1, t))
    local x, y = a[1] + t * dx, a[2] + t * dy
    return math.sqrt((px - x) ^ 2 + (py - y) ^ 2)
end

-- signed distance to a polygon: negative inside, positive outside
local function SignedDistance(poly, px, py)
    local best, inside = math.huge, false
    for i = 1, #poly do
        local a, b = poly[i], poly[i % #poly + 1]
        best = math.min(best, SegmentDistance(px, py, a, b))
        if (a[2] > py) ~= (b[2] > py) and px < (b[1] - a[1]) * (py - a[2]) / (b[2] - a[2]) + a[1] then
            inside = not inside
        end
    end
    return inside and -best or best
end

-- signed distance to the star with rounded points: the smaller star grown back by ROUND
local function StarDistance(px, py)
    return SignedDistance(inset, px, py) - ROUND
end

-- what is drawn at a point of the cell: color (0 black, 1 white) and opacity, or nil
local function Paint(d, filled)
    if filled then
        if d <= 0 then return 1, 1 end
        if d <= OUTLINE then return 0, 1 end
    else
        if d <= 0 and d >= -RING then return 1, 1 end
        if d > 0 and d <= OUTLINE then return 0, 1 end
        if d < -RING and d >= -(RING + INNER_EDGE) then return 0, 1 end
        if d < -(RING + INNER_EDGE) then return 0, FILL_ALPHA end
    end
    return nil
end

local pixels = {}
for y = 0, H - 1 do
    pixels[y] = {}
    for x = 0, W - 1 do
        local filled = x >= CELL
        local cellX = x % CELL
        local alphaSum, colorSum = 0, 0
        for sy = 0, SAMPLES - 1 do
            for sx = 0, SAMPLES - 1 do
                local color, alpha = Paint(StarDistance(cellX + (sx + 0.5) / SAMPLES, y + (sy + 0.5) / SAMPLES), filled)
                if color then
                    alphaSum = alphaSum + alpha
                    colorSum = colorSum + color * alpha
                end
            end
        end
        pixels[y][x] = {
            color = alphaSum > 0 and colorSum / alphaSum or 0,
            alpha = alphaSum / (SAMPLES * SAMPLES),
        }
    end
end

local out = {}
local function Byte(n) out[#out + 1] = string.char(n) end
local function Word(n) Byte(n % 256) Byte(math.floor(n / 256)) end

Byte(0) Byte(0) Byte(2) -- no id, no color map, uncompressed true color
Word(0) Word(0) Byte(0) -- color map spec
Word(0) Word(0) -- origin
Word(W) Word(H)
Byte(32) Byte(0x28) -- 32 bpp, 8 alpha bits, top-left origin

for y = 0, H - 1 do
    for x = 0, W - 1 do
        local p = pixels[y][x]
        local c = math.floor(p.color * 255 + 0.5)
        Byte(c) Byte(c) Byte(c) Byte(math.floor(p.alpha * 255 + 0.5)) -- B G R A
    end
end

local path = "ShowItems\\Textures\\ShowItemsStar.tga"
local file = assert(io.open(path, "wb"))
file:write(table.concat(out))
file:close()
print("written " .. path .. " (" .. (18 + W * H * 4) .. " bytes)")

-- a text picture of the result: # white, o black edge, : dark middle, space nothing
for y = 0, H - 1 do
    local row = {}
    for x = 0, W - 1 do
        local p = pixels[y][x]
        local ch = " "
        if p.alpha >= 0.9 then
            ch = p.color > 0.5 and "#" or "o"
        elseif p.alpha >= 0.3 then
            ch = p.color > 0.5 and "#" or ":"
        end
        row[#row + 1] = ch
    end
    print(table.concat(row))
end
