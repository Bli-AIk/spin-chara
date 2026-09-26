-- Authored alternatives; no user-facing tuning panel.
local Knife=require("Scripts.Game.Barrage.knife")
local C={}
-- The pitch the blade sprite asks for: its own 14px cross-section plus a 2px
-- seam, so a row or fan reads as separate blades instead of one squeezed mass.
-- The outline is grown with the sprite (see knife.lua), so the seam stays too
-- narrow for the soul to slip between two blades.
local base={knifeSpeed=140,spacing=Knife.pitch(),warning=.85,hold=.8,radius=38,
    lightSpeed=80,slowFactor=.35,orbitSpeed=42,triggerDistance=16,
    thrustLength=14,thrustTime=.85,damage=3,hurtTime=30,punishDamage=2,seed=73,
    sweepDuration=2.25,stagger=.035,easing="cubic",lightDuration=2.8,
    ringGap=38,ringCount=9,ringDelay=.45,lightWander=2.8,alternate=false,phaseOffset=.23}
C.presets={
    {label="A · 从容",wave02Label="A · 明停 / 突刺",wave02Light=.82,wave02Reaction=.34,wave02Thrust=.42,wave02Hold=.30,wave02Pattern="together",wave02Curve="quart",
        sweepDuration=2.65,lightDuration=3.2,easing="sine",orbitSpeed=32,ringGap=42,lightWander=3.2},
    {label="B · 顿挫",wave02Label="B · 短停 / 重刺",wave02Light=.72,wave02Reaction=.22,wave02Thrust=.28,wave02Hold=.24,wave02Pattern="together",wave02Curve="quint",
        sweepDuration=2.05,lightDuration=2.8,easing="quint",orbitSpeed=42,ringGap=38,lightWander=2.7},
    {label="C · 错拍",wave02Label="C · 中央 / 扩散",wave02Light=.80,wave02Reaction=.28,wave02Thrust=.36,wave02Hold=.26,wave02Pattern="centre",wave02Stagger=.035,wave02Curve="quart",
        sweepDuration=2.25,lightDuration=3.0,easing="cubic",stagger=.085,orbitSpeed=36,ringGap=40,alternate=true,lightWander=3.0},
    {label="D · 紧凑",wave02Label="D · 双拍 / 连刺",wave02Light=.68,wave02Reaction=.16,wave02Thrust=.25,wave02Hold=.22,wave02Pattern="alternate",wave02Stagger=.09,wave02Curve="quint",
        sweepDuration=1.85,lightDuration=2.65,easing="cubic",orbitSpeed=48,ringGap=34,ringDelay=.35,lightWander=2.35},
}
function C.defaults(index)
    local out={}
    for k,v in pairs(base) do out[k]=v end
    for k,v in pairs(C.presets[index or 1]) do out[k]=v end
    return out
end
function C.wave03A()
    local out=C.defaults(3)
    out.label="B · 滑灯截刀"
    -- Only the light shrinks; the rows keep the shared blade pitch.
    out.radius=22
    out.wave03Prototype={
        -- The opener's wind-up is introHold + emerge + spin + pause. The frame
        -- grows to the round's square over the last growTime of it, landing on
        -- the sweep; expand is the width it takes on after that sweep.
        introHold=.18,
        -- emerge slides the rows out, spin turns them end over end, and pause
        -- is the beat where they hang still, wound up, before the sweep: the
        -- one moment that tells the player a row is about to cross the frame.
        emerge=.22,spin=.26,pause=.25,burst=.60,growTime=.25,expand=.27,edgeDelay=.20,
        slashAt=.30,firstCut=.06,cutGap=.10,cutSettle=.24,lightEntry=1.0,
        moveTime=.90,launchAt=.18,beats=5,hold=.16,retract=.34,
        kind="glide",flights={1.85,1.65,1.45,1.30,1.24},
    }
    return out
end
function C.wave05()
    local out=C.defaults(1)
    out.label="A · 平稳"
    out.wave05Profile={kind="steady",moves={240/54,240/54,240/54,240/54},
        pauses={0,0,0,0},wavePeriod=2.6,
        warning=.48,thrust=.30,hold=.12,retract=.36,cooldown=.60}
    return out
end
function C.wave06D()
    local out=C.defaults(1)
    out.label="D · 逐趟加速"
    out.wave06Profile={speeds={65,145,185,225,265,305},rest=0}
    return out
end
return C
