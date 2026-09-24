-- Authored alternatives; no user-facing tuning panel.
local C={}
-- A 12px pitch overlaps the blade's 10px cross-section plus the soul hitbox.
local base={knifeSpeed=140,spacing=12,warning=.85,hold=.8,radius=38,
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
    out.radius,out.spacing=22,12
    out.wave03Prototype={
        emerge=.36,spin=.42,pause=.13,burst=.60,expand=.27,edgeDelay=.20,
        slashAt=.30,firstCut=.06,cutGap=.10,cutSettle=.24,lightEntry=1.0,
        moveTime=.90,launchAt=.18,beats=5,hold=.16,retract=.34,
        kind="glide",flights={1.85,1.65,1.45,1.30,1.24},
    }
    return out
end
return C
