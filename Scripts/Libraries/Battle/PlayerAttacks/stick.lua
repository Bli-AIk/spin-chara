local atk = {_end = false, _max = false}
local enemy = {}
local attacked = false
local damage = -999
local missed = false
local time = 0

function atk.Prepare(_enemy)
    atk._end = false
    time = 0
    enemy = _enemy
    attacked = false
    missed = false

    local target = Sprites.CreateSprite("UI/Battle Screen/spr_target_0.png", "UponArena")
    target:MoveTo(Battle.mainarena.x, Battle.mainarena.y)
    atk.target = target

    local bar = Sprites.CreateSprite("UI/Battle Screen/Player Attack/spr_targetchoice_0.png", "UponArena")
    bar.y = target.y + Battle.mainarena.height / 2 + bar.height / 2

    local randomer = (math.random() <= 0.5)
    bar._rand = randomer
    bar.x = target.x + (randomer and -280 or 280)
    bar.velocity.x = 0
    bar:SetAnimation({
        "UI/Battle Screen/Player Attack/spr_targetchoice_1.png",
        "UI/Battle Screen/Player Attack/spr_targetchoice_0.png"
    }, 0.1)
    atk.bar = bar
    atk._prepared = true
    local mask = Masks.New("rectangle", 0, 0, 0, 0, 0, 0)
    mask:Follow(Battle.mainarena.black)
    for _, sprite in ipairs({target, bar}) do
        sprite:SetStencils({mask})
        sprite.Step = function() mask:Follow(Battle.mainarena.black) end
        -- Scissor also excludes stencil values left by other arena sprites.
        local draw = sprite.Draw
        function sprite:Draw()
            local arena = Battle.mainarena
            SE.graphics.push("all")
            SE.graphics.intersectScissor(arena.x - arena.width / 2,
                arena.y - arena.height / 2, arena.width, arena.height)
            draw(self)
            SE.graphics.pop()
        end
    end
    atk.Reveal(0)
end

function atk.Reveal(progress)
    local arena = Battle.mainarena
    local offset = (arena.height / 2 + math.max(atk.target.height, atk.bar.height) / 2) * (1 - progress)
    atk.target:MoveTo(arena.x, arena.y + offset)
    atk.bar.y = arena.y + offset
end

function atk.Begin()
    atk._prepared = false
    atk.bar.velocity.x = atk.bar._rand and 6 or -6
end

function atk.Restart(_enemy)
    atk.Prepare(_enemy)
    atk.Reveal(1)
    atk.Begin()
end

function atk.SetMaxDamage(dmg)
    atk._max = true
    damage = dmg
end

-- Interface pulled out by this attack pattern: signal that the targeted enemy
-- has been hit. The battle system dispatches to the enemy's animation Hurt()
-- based on enemy.id, so this attack never couples to a specific animation.
function atk.Hurt()
    if (not enemy or not enemy.id) then
        return
    end

    if (enemy.animation and enemy.animation.Hurt) then
        enemy.animation:Hurt()
    end
end

-- Interface: signal the targeted enemy's animation that an attack has just been
-- LAUNCHED (the moment the player confirms the strike, before the hit lands).
-- Animations may implement `:OnAttack(data)` to react (brace / dodge / telegraph
-- / counter, ...). `data` carries the strike details:
--   data.enemy    → the targeted enemy table
--   data.damage   → the planned damage for this hit
--   data.perfect  → true when the timing landed in the perfect zone
--   data.offset   → distance from the perfect zone (0 = perfect)
--   data.position → {x, y} of the enemy on screen
--   data.miss     → true when the strike is resolved as a miss (no damage lands)
--   data.attack   → this attack pattern instance (atk)
function atk.Attack(data)
    if (not enemy or not enemy.animation) then
        return
    end

    local anim = enemy.animation
    if (anim.OnAttack) then
        anim:OnAttack(data)
    end
end

function atk.Destroy()
    atk.bar:Destroy()
    atk.target:Destroy()

    atk._end = true
    atk._prepared = false
end

function atk.Update(dt)
    local bar = atk.bar
    local tar = atk.target
    if (not bar or not tar) then return end

    if (not attacked) then
        if (bar.x < tar.x - 280 or bar.x > tar.x + 280) then
            bar.velocity.x = 0
            bar.alpha = 0
            attacked = true
            missed = true
        elseif (Keyboard.GetState("confirm") == 1) then
            -- Calculate
            bar.velocity.x = 0
            local bonus_factor = math.abs(bar.x - tar.x)

            -- Resolve `always_miss` HERE, on the same frame the slice spawns and
            -- OnAttack() fires, so the enemy's dodge starts immediately.
            --
            -- Setting `missed` now routes the strike into the EXISTING timeout-miss
            -- branch below rather than duplicating it: the MISS text pops on the
            -- very next frame (time == 1), HP is never written at all, and
            -- Destroy() lands at time == 30 -- which is exactly how long the dodge
            -- in Animations/Chara.lua runs, so the slide can never outlive the strike.
            --
            -- Read straight off the enemy table (not a module-level local), so this
            -- attack's singleton state has nothing new to reset in Prepare().
            local always_miss = (enemy.always_miss == true)
            if (always_miss) then
                damage = 0
                missed = true
            elseif (not atk._max) then
                if (bonus_factor <= 12) then -- Perfect
                    damage = math.ceil(enemy.maxdamage + math.random(0, enemy.dmg_float))
                else
                    damage = math.max(enemy.maxdamage * 0.2, math.ceil(0.9 * (enemy.maxdamage) * (280 - bonus_factor) / 280))
                end
            end

            -- Slice.
            Audio.PlaySound("snd_slice.wav")
            local slice = Sprites.CreateSprite("UI/Battle Screen/Player Attack/spr_slice_o_0.png", "TopAll")
            slice:SetAnimation({
                "UI/Battle Screen/Player Attack/spr_slice_o_1.png",
                "UI/Battle Screen/Player Attack/spr_slice_o_2.png",
                "UI/Battle Screen/Player Attack/spr_slice_o_3.png",
                "UI/Battle Screen/Player Attack/spr_slice_o_4.png",
                "UI/Battle Screen/Player Attack/spr_slice_o_5.png",
            }, 1 / 6, "empty")
            slice:MoveTo(enemy.position[1], enemy.position[2])

            attacked = true

            -- Broadcast to the targeted enemy's animation that the attack was
            -- launched, passing the strike details so monsters can react.
            atk.Attack({
                enemy = enemy,
                damage = damage,
                perfect = (bonus_factor <= 12),
                offset = bonus_factor,
                position = {enemy.position[1], enemy.position[2]},
                -- True when this strike was resolved as a miss on this frame
                -- (always_miss today). Animations use it to dodge.
                miss = (missed == true),
                attack = atk,
            })
        end
    else
        atk._missed = missed
        atk._attacked = attacked

        time = time + 1
        if (not missed) then
            if (time == 70) then
                if (damage > 0) then
                    Audio.PlaySound("snd_damage.wav")
                    local _start = enemy.hp / enemy.maxhp * 100
                    local _target = (enemy.hp - damage) / enemy.maxhp * 100
                    UI.newMonsterBar({enemy.position[1], enemy.position[2]}, _start, _target)

                    -- Trigger the targeted enemy's hurt animation (dispatched by id)
                    atk.Hurt()
                end
                UI.newBounceText((damage > 0 and damage or "MISS"), {enemy.position[1], enemy.position[2]}, (damage <= 0 and {1, 1, 1}))
                enemy.hp = math.max(0, math.min(enemy.maxhp, enemy.hp - damage))
                atk._max = false
            elseif (time == 130) then
                atk.Destroy()
            end
        else
            if (time == 1) then
                UI.newMissText("MISS", {enemy.position[1], enemy.position[2]})
            elseif (time == 30) then
                atk.Destroy()
            end
        end
    end
end


return atk
