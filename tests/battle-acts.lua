-- Run from the project root: luajit tests/battle-acts.lua
local json = dofile('Scripts/Libraries/Utils/dkjson.lua')
local language, current, changes
Localize = {localizeText = function(key) return assert(language[key], key) end}
UI = {state = {}}
Battle = {}
Battle.NewDialogue = function(lines)
    current = {lines = lines, kind = 'narration', Destroy = function(self)
        if self._onComplete then self._onComplete() end
    end}
    return current
end
Battle.ChangeState = function(state) changes[#changes + 1] = state end
Battle.BattleDialogue = function(lines, state)
    local t = Battle.NewDialogue(lines)
    t._onComplete = function() Battle.ChangeState(state) end
end
Typers = {EText = {New = function(lines, position, layer, size, mode)
    local t = Battle.NewDialogue(lines)
    t.kind, t.mode = 'bubble', mode
    t.size = size
    t.UseBondFont = function(self, config) self.bondfont = config end
    t.ShowBubble = function(self, direction) self.direction = direction end
    return t
end}}
local module = dofile('Scripts/Game/Logics/battle_acts.lua')
for _, locale in ipairs({'en', 'zh_CN'}) do
    local file = assert(io.open('Localization/' .. locale .. '.json'))
    language = assert(json.decode(file:read('*a')))
    file:close()
    for _, action in ipairs({'Applause', 'Boo'}) do
        changes = {}
        local acts = module.New()
        acts:Use({_id = 7, id = 'Chara', position = {320, 120}}, {id = action})
        assert(Battle.dialogue_started and current.kind == 'narration')
        -- en and zh_CN do not agree on how many elements an ACT text array has
        -- (zh_CN still carries the pre-split single-element form), so assert the
        -- shape rather than the count.
        assert(#current.lines >= 1 and #changes == 0)
        current:_onComplete() -- Confirm initial narration.
        assert(current.kind == 'bubble' and current.mode == 'manual')
        assert(current.direction == 'right' and #changes == 0)
        for _, line in ipairs(current.lines) do assert(not line:find('* ', 1, true)) end
        current:_onComplete() -- Confirm all enemy speech.
        assert(current.kind == 'narration' and #changes == 0)
        assert(next(acts.pending) == nil)
        if locale == 'zh_CN' and action == 'Applause' then
            assert(current.lines[1] == '* Chara的动作变慢了，但瞄的更精准了！')
        end
        current:_onComplete() -- Only final confirmation requests defense/animation.
        assert(#changes == 1 and changes[1] == 'DEFENDING')
        assert(acts.pending[7] and not acts.pending[1])
        acts:DefenseStarting()
        assert(next(acts.pending) == nil)
        if action == 'Applause' then
            assert(acts.active[7].slower_bullets and acts.active[7].precise_aim)
        else
            assert(acts.active[7].increased_damage)
        end
        acts:DefenseEnding()
        assert(next(acts.active) == nil)
        acts:DefenseStarting()
        assert(next(acts.active) == nil)
    end
    changes = {}
    local acts = module.New()
    acts:Use({id = 'Chara'}, {id = 'Check'})
    current:_onComplete()
    assert(#changes == 1 and changes[1] == 'ACTIONSELECT')
    -- Recall reads back the rules announced so far and, like Check, hands the
    -- turn straight back instead of reaching DEFENDING.  One rule is announced
    -- per round, so round 3 has three: the lead-in alone, then all three on one
    -- screen, since three is exactly what the box holds.
    Battle.game = {round = 3}
    changes = {}
    acts = module.New()
    acts:Use({id = 'Chara'}, {id = 'Recall'})
    assert(current.kind == 'narration' and #current.lines == 2)
    local _, newlines = current.lines[2]:gsub('\n', '\n')
    assert(newlines == 2, 'three rules belong on one screen')
    if locale == 'zh_CN' then
        -- Compare with the [tag]s stripped: these pin the wording, not the
        -- pacing, so retuning a [wait:] must not break them.
        local plain = function(s) return (s:gsub('%[.-%]', '')) end
        assert(plain(current.lines[1]) == '* 你开始回想...这场演出的规矩。')
        assert(plain(current.lines[2]):find('* 敌人先手开局。', 1, true))
        assert(plain(current.lines[2]):find('* 聚光灯里才是安全的。', 1, true))
        assert(plain(current.lines[2]):find('* 黑暗里按 X键，弹幕大幅变慢。', 1, true))
    end
    current:_onComplete()
    assert(#changes == 1 and changes[1] == 'ACTIONSELECT')
    assert(next(acts.pending) == nil, 'Recall is not an action taken at the enemy')
    changes = {}
    acts:Use({_id = 8, id = 'Napstablook', position = {520, 120}}, {id = 'Applause'})
    current:_onComplete()
    assert(current.kind == 'bubble' and #changes == 0)
    current:_onComplete()
    assert(changes[1] == 'DEFENDING' and next(acts.pending) == nil)
    changes = {}
    acts:Use({_id = 7, id = 'Chara', position = {320, 120}}, {id = 'Boo'})
    acts:Clear()
    assert(#changes == 0 and acts.typer == nil, 'Scene cleanup must not advance ACT')
end
print('PASS: bilingual ACT phases, final-confirm transition, Check, Recall, per-enemy tags and cleanup')
