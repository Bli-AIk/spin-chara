local wave = ImportFile("Battle.Waves")
local EndWave = wave.EndWave
local Arena = Battle.mainarena
local bones = wave.Import("Attacks.Bones")
Player.canMove = true

local mask = Masks.New("rectangle", Arena.x, Arena.y, Arena.width, Arena.height, 0, 0)

local bullet = Sprites.CreateSprite("bullet.png", "Bullets")
bullet:Scale(4, 4)
bullet:MoveTo(Arena.x + math.random(-60, 60), Arena.y + math.random(-50, 50))
bullet:SetStencils({mask})
bullet.isBullet = true
table.insert(wave.objects, bullet)

local time = 0
function wave.Update(dt)
    bones.Update(dt)
    mask:Follow(Arena.black)

    time = time + dt
    if (time >= 5) then
        EndWave()
    end
end

return wave
