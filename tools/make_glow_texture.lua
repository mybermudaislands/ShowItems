-- Generates ShowItems\Textures\ShowItemsGlow.tga: a soft white glow ring for a nine-slice frame glow.
-- Run from the project root: lua5.1.exe tools\make_glow_texture.lua
--
-- 64x64, 32-bit uncompressed TGA, top-left origin. The ring is centered on a rounded rectangle that
-- is inset 16 px from every side (pixels 16..48, corner radius 5):
--   outside the rectangle the glow fades out over 16 px (down to the texture edge),
--   inside the rectangle it fades out over 8 px, so the middle of the texture (24..40) is transparent.
-- The straight part of every edge (21..43) is uniform along the edge, so the 9 slices
-- (corners 0..24 px = 0.375, stretched edges 24..40 px = 0.375..0.625) can be stretched to any size.
-- The color is white, the addon tints it with the vertex color.

local SIZE, INSET, RADIUS = 64, 16, 5
local OUT_FADE, IN_FADE = 16, 8

local half = SIZE / 2 - INSET -- half size of the rounded rectangle
local inner = half - RADIUS

-- signed distance to the rounded rectangle: positive outside, negative inside
local function SignedDistance(x, y)
    local dx, dy = math.abs(x - SIZE / 2) - inner, math.abs(y - SIZE / 2) - inner
    local outside = math.sqrt(math.max(dx, 0) ^ 2 + math.max(dy, 0) ^ 2)
    return outside + math.min(math.max(dx, dy), 0) - RADIUS
end

local function Alpha(x, y)
    local d = SignedDistance(x, y)
    local t
    if d >= 0 then t = d / OUT_FADE else t = -d / IN_FADE end
    if t >= 1 then return 0 end
    return (1 - t) ^ 2
end

local out = {}
local function Byte(n) out[#out + 1] = string.char(n) end
local function Word(n) Byte(n % 256) Byte(math.floor(n / 256)) end

Byte(0) Byte(0) Byte(2) -- no id, no color map, uncompressed true color
Word(0) Word(0) Byte(0) -- color map spec
Word(0) Word(0) -- origin
Word(SIZE) Word(SIZE)
Byte(32) Byte(0x28) -- 32 bpp, 8 alpha bits, top-left origin

for py = 0, SIZE - 1 do
    for px = 0, SIZE - 1 do
        local a = math.floor(Alpha(px + 0.5, py + 0.5) * 255 + 0.5)
        Byte(255) Byte(255) Byte(255) Byte(a) -- B G R A
    end
end

local path = "ShowItems\\Textures\\ShowItemsGlow.tga"
local file = assert(io.open(path, "wb"))
file:write(table.concat(out))
file:close()
print("written " .. path .. " (" .. (18 + SIZE * SIZE * 4) .. " bytes)")
