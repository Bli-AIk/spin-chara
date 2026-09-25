-- Run from the project root: luajit tests/battle-rules.lua
local json = dofile('Scripts/Libraries/Utils/dkjson.lua')
local language
Localize = {localizeText = function(key) return assert(language[key], key) end}
local rules = dofile('Scripts/Game/Logics/battle_rules.lua')

-- Rules announced through the end of each round, cumulative.
local announced_by_round = {[0] = 0, [1] = 1, [2] = 2, [3] = 4, [4] = 5, [5] = 6}

-- The menu dialogue box wraps a line that outgrows 558px.  English is
-- determination_mono, a true monospace: 16.2px a glyph at 27px, so 34 glyphs.
-- Chinese is simsun at 13px but drawn at double size to match the English, so a
-- full-width glyph costs roughly 30px and only about 17 of them fit -- which is
-- why a bare character count cannot be the guard here.  Widths are compared
-- instead, the same way the typer does it.
local BOX_WIDTH = 558
local NARROW, WIDE = 16.2, 30
local PER_SCREEN = 3

-- How wide the typer would draw a line, in the menu box's pixels.  Tag text is
-- consumed by the [tag] stripper before this runs.  LuaJIT has no utf8 library,
-- so lead bytes are classified by hand: ASCII is one byte under 0x80, a CJK
-- glyph leads with 0xE0 or above and its continuation bytes land in the
-- 0x80-0xBF range, where they add nothing and so count the glyph exactly once.
local function width(s)
    local total = 0
    for i = 1, #s do
        local byte = s:byte(i)
        if byte < 0x80 then total = total + NARROW
        elseif byte >= 0xE0 then total = total + WIDE end
    end
    return total
end

local function count_lines(screen)
    local n = 1
    for _ in screen:gmatch('\n') do n = n + 1 end
    return n
end

for _, locale in ipairs({'en', 'zh_CN'}) do
    local file = assert(io.open('Localization/' .. locale .. '.json'))
    language = assert(json.decode(file:read('*a')))
    file:close()

    for round, total in pairs(announced_by_round) do
        local screens = rules.Pages(round)
        assert(#screens == 1 + math.ceil(total / PER_SCREEN),
            ('%s r%d: %d screens for %d rules'):format(locale, round, #screens, total))

        local seen = 0
        for i, screen in ipairs(screens) do
            assert(count_lines(screen) <= PER_SCREEN,
                ('%s r%d screen %d has %d lines'):format(locale, round, i, count_lines(screen)))
            -- Only the lead-in skips the star; every rule line carries it.
            if i > 1 then
                for line in screen:gmatch('[^\n]+') do
                    assert(line:sub(1, 2) == '* ', 'rule line must open with "* ": ' .. line)
                    -- Color tags render at zero width, so measure without them.
                    -- These lines are drawn in the black arena dialogue, where
                    -- the default colour is white.  [colorHEX:000000] is the
                    -- reset used inside the enemy's *white* speech bubbles, and
                    -- in here it paints the rest of the line invisible.
                    assert(not line:find('[colorHEX:000000]', 1, true),
                        'black reset is invisible in the arena dialogue: ' .. line)
                    local plain = line:gsub('%[.-%]', '')
                    assert(width(plain) <= BOX_WIDTH,
                        ('%s r%d line wraps (%.1f > %d): %s'):format(
                            locale, round, width(plain), BOX_WIDTH, plain))
                    seen = seen + 1
                end
            end
        end
        assert(seen == total, ('%s r%d: %d rules listed, expected %d'):format(locale, round, seen, total))
    end

    -- Past the last real round there is simply nothing new to add.
    assert(#rules.Pages(99) == #rules.Pages(5), locale .. ': rounds beyond 5 must add nothing')
    -- A battle that somehow has no round yet still has the lead-in to show.
    assert(#rules.Pages(nil) == 1, locale .. ': no round means lead-in only')
end

print('PASS: rule recall screens, star prefixes and per-locale line widths')
