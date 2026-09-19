local acts = {}

-- Tags describe intent only; waves may consume these later without changing ACT flow.
local effects = {
    Chara = {
        Applause = {"slower_bullets", "precise_aim"},
        Boo = {"increased_damage"},
    }
}

function acts.New()
    local self = {pending = {}, active = {}}

    function self:DefenseStarting()
        self.active, self.pending = self.pending, {}
    end

    function self:DefenseEnding()
        self.active = {}
    end

    function self:Clear()
        self.pending, self.active = {}, {}
        if self.typer then
            self.typer._onComplete = nil
            self.typer:Destroy()
            self.typer = nil
        end
    end

    function self:Use(enemy, action)
        local key = "Battle.Actions.Texts." .. enemy.id .. "." .. action.id
        if action.id == "Check" then
            Battle.BattleDialogue(Localize.localizeText(key), "ACTIONSELECT")
            return
        end
        local has_reply = (enemy.id == "Chara" and effects.Chara[action.id])
            or (enemy.id == "Napstablook" and action.id == "Applause")
        if not has_reply then
            Battle.BattleDialogue(Localize.localizeText(key), "DEFENDING")
            return
        end
        Battle.dialogue_started = true
        local tags = effects[enemy.id] and effects[enemy.id][action.id]
        local function finish()
            if tags then
                local target = enemy._id
                self.pending[target] = self.pending[target] or {}
                for _, tag in ipairs(tags) do self.pending[target][tag] = true end
            end
            self.typer = nil
            Battle.ChangeState("DEFENDING")
            UI.state.block_transition = true
        end
        local function result()
            if not tags then finish(); return end
            self.typer = Battle.NewDialogue(Localize.localizeText(key .. ".Effect"))
            self.typer._onComplete = finish
        end
        local function reply()
            local lines = Localize.localizeText(key .. ".Reply")
            local colored = {}
            for i, line in ipairs(lines) do colored[i] = "[colorHEX:000000]" .. line end
            local x, y = unpack(enemy.position)
            local on_left = x >= 300
            -- galadriel_redux/Scripts/Waves/wave_gr_0.lua (970e91e):
            -- speechbubble.ttf, 13 px, scale 1, no extra spacing, 210x100 bubble.
            local width, height = 210, 100
            local bx = on_left and math.max(25, x - width - 45)
                or math.min(615 - width, x + 65)
            self.typer = Typers.EText.New(colored, {bx, math.max(35, y - height / 2 + 10)},
                "UponArena", {width, height}, "manual")
            local speech = self.typer
            speech.font = "speechbubble.ttf"
            speech.fontsize = 13
            -- Existing Lua fields bypass __newindex; explicitly disable the
            -- narration font callbacks (which would double Chinese glyphs).
            speech.use_bondfont = false
            speech.scale = 1
            speech.line_spacing = 0
            self.typer.auto_wrap = true
            self.typer:ShowBubble(on_left and "right" or "left", 0.5)
            -- ShowBubble captures the outer dimensions; wrapping needs inner width.
            self.typer.size[1] = width - 20
            self.typer._onComplete = result
        end
        self.typer = Battle.NewDialogue(Localize.localizeText(key))
        self.typer._onComplete = reply
    end

    return self
end

return acts
