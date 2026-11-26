--
-- RECURSIVE.LUA
--
-- Test program for Lua Lanes
--
local lanes = lanes.configure { with_timers = false }
io.stdout:write( "depth:" )
local function func( depth )
    io.stdout:write(" " .. depth)
    if depth > 10 then
        return "done!"
    end

    local lane= lanes.gen("*", func)( depth+1 )
    return lane[1]
end

local v= func(0)
assert(v=="done!")
io.stdout:write("\n")
