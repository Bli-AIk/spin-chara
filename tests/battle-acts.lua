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
        assert(#current.lines == 1 and #changes == 0)
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
print('PASS: bilingual ACT phases, final-confirm transition, Check, per-enemy tags and cleanup')
