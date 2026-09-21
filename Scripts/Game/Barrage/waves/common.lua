local C={}
function C.clamp(x) return math.max(0,math.min(1,x)) end
function C.lerp(a,b,t) return a+(b-a)*C.clamp(t) end
function C.ease(t) t=C.clamp(t); return t*t*(3-2*t) end
function C.curve(name,t)
    t=C.clamp(t)
    if name=="sine" then return (1-math.cos(math.pi*t))/2 end
    local power=name=="quint" and 5 or name=="quart" and 4 or 3
    return t<.5 and (2*t)^power/2 or 1-(-2*t+2)^power/2
end
function C.light(x,y,r) return {x=x,y=y,r=r} end
return C
