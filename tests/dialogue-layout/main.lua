-- Measure glyphs produced by the actual rich-text engine, not stripped strings.
local project=love.filesystem.getWorkingDirectory()
dofile(project..'/main.lua')
local gameLoad=love.load
local json=require('Scripts.Libraries.Utils.dkjson')
local failures={}
local function renderText(raw,speech,key)
    -- Preserve executable markers in production. Isolate them from typography.
    local text=raw:gsub('%[func:[^%]]+%]','')
    local t=Typers.EText.New((speech and '[colorHEX:000000]' or '')..text,{0,0},'TopAll',
        {speech and 210 or 558,speech and 100 or 120},'none')
    t.auto_wrap=true;t.voices={};t.skip.canskip=false
    if speech then t.font='speechbubble.ttf';t.fontsize=13;t.use_bondfont=false;t.scale=1;t.line_spacing=0 end
    for _=1,2000 do
        t:Update(1)
        if t.counter>#t.texts[1] and t.cantype then break end
    end
    local width,height,green=0,0,false
    for _,l in ipairs(t.letters) do
        width=math.max(width,l.x+l.width*l.scale)
        height=math.max(height,l.y+l.font:getHeight()*l.scale)
        if l.color[1]==0 and l.color[2]==1 and l.color[3]==0 then green=true end
    end
    if width>(speech and 210 or 558)+.01 or height>(speech and 100 or 120)+.01 then
        failures[#failures+1]=string.format('%s: %.0fx%.0f',key,width,height)
    end
    if raw:find('[colorHEX:00ff00]',1,true) then assert(green,'Actual green glyphs: '..key) end
    return t
end
function love.load(...)
    gameLoad(...)
    local g=love.graphics
    local font=g.newFont('Resources/Fonts/unifont_jp.otf',12)
    local count=0
    for _,lang in ipairs({'zh_CN','en'}) do
        Localize.setFile(lang)
        local data=json.decode((assert(love.filesystem.read('Localization/'..lang..'.json'))))
        local prototype=json.decode((assert(love.filesystem.read('prototypes/barrage-lab/localization/'..lang..'.json'))))
        local entries={}
        for key,value in pairs(data) do
            local speech=key:find('Battle.BarrageLab.',1,true) or key:find('Battle.Waves.',1,true)
                or key:match('^Battle%.Actions%.Texts%..*%.Reply$')
            local menu=key:find('Battle.Rules.',1,true) or key:find('Battle.Narration.',1,true)
                or key:find('Battle.Actions.Texts.',1,true) or key:match('^Battle%.Items%..*%.Use$')
                or key:match('^Battle%.Items%..*%.Repeat$') or key:match('^Battle%.Items%.Chocolate%.')
            if key:find('Battle.BarrageLab.',1,true) then assert(value==prototype[key],'Prototype text diverged: '..key) end
            if speech or menu then
                if type(value)=='string' then value={value} end
                for i,raw in ipairs(value) do
                    if not key:match('Name%d?$') then
                        entries[#entries+1]={key=key..(#value>1 and '.'..i or ''),raw=raw,speech=speech}
                    end
                end
            end
        end
        table.sort(entries,function(a,b) return a.key<b.key end)
        local page,canvas=0,nil
        local function save()
            if canvas then g.readbackTexture(canvas):encode('png',lang..'-speech-'..page..'.png') end
        end
        local slot=0
        for _,entry in ipairs(entries) do
            local t=renderText(entry.raw,entry.speech,lang..' '..entry.key)
            count=count+1
            if entry.speech then
                if slot%12==0 then
                    save();page=page+1;canvas=g.newCanvas(1260,640)
                    g.setCanvas(canvas);g.clear(.08,.08,.08,1);g.setCanvas();slot=0
                end
                local x,y=(slot%3)*420,math.floor(slot/3)*160
                g.push('all');g.setCanvas(canvas);g.setFont(font);g.setColor(1,1,1)
                g.print(entry.key:gsub('Battle.BarrageLab.',''):gsub('Battle.Actions.Texts.',''):gsub('Battle.Waves.',''),x+12,y+8)
                g.rectangle('fill',x+12,y+30,210,100)
                t.x,t.y=x+22,y+40;t:Draw();g.setCanvas();g.pop();slot=slot+1
            end
            t:Destroy()
        end
        save()
        local rules=require('Scripts.Game.Logics.battle_rules')
        for _,raw in ipairs(rules.Pages(8)) do local t=renderText(raw,false,lang..' recall page');t:Destroy() end
        local intro=data['Battle.Waves.Wave01.Intro'][4]
        assert(intro:find('[func:Wave01Warning]...[func:Wave01Slash]',1,true),'Preserve first-wave attack timing markers')
    end
    for _,msg in ipairs(failures) do print('[OVERFLOW] '..msg) end
    assert(#failures==0,'Dialogue overflow: '..#failures)
    print('[OK] '..count..' bilingual dialogue entries: native glyph bounds, green spans, recall pages, prototype parity')
    print('[CAPTURE] '..love.filesystem.getSaveDirectory())
    love.event.quit(0)
end
function love.update() end
function love.draw() end
