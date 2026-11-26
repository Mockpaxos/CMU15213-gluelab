-- This trace tests your implementation of the 'seek' function more 
-- extensively, focusing on the boundary cases when iterating through block.

BLOCK_DATA_SIZE = 500

local function check(rv, ...)
    if not rv then
        message = ...
        error(message, 2)
    end
    return rv
end

local function checkSeeks(fd, startPos, curPos, n)
    -- seek by zero should do nothing
    local seekPos = check(disk.seek(fd, 0))
    assert(seekPos == curPos)
    assert(check(disk.getPos(fd)) == curPos)

    -- seek by -n should put us back where we were originally
    seekPos = check(disk.seek(fd, -n))
    assert(seekPos == startPos)
    assert(check(disk.getPos(fd)) == startPos)
end

local function checkWrite(fd, data)
    local startPos = check(disk.getPos(fd))
    local written = check(disk.write(fd, data))
    local curPos = check(disk.getPos(fd))

    assert(written == #data)
    assert(curPos == startPos + written)

    checkSeeks(fd, startPos, curPos, written)
end

local function checkRead(fd, expected)
    local startPos = check(disk.getPos(fd))
    local data = check(disk.read(fd, #expected))
    local curPos = check(disk.getPos(fd))

    assert(data == expected,
           'exp ' .. expected .. ' got ' .. data)
    assert(curPos == startPos + #expected)

    checkSeeks(fd, startPos, curPos, #expected)
end

local function checkOpen(fname)
    local fd = check(disk.open(fname))
    local pos = check(disk.getPos(fd))
    assert(pos == 0)
    return fd
end

local function checkBig()
    local data1 = string.rep("a", 495) .. "bbbb\n" -- exactly one block of data
    local data2 = string.rep("c", 495) .. "dddd\n" -- exactly one block of data
    local data3 = string.rep("e", 495) .. "ffff\n" -- exactly one block of data
    local ddata = data1 .. data2 .. data3 

    read_char = {"a","c","e"}

    local fd = checkOpen("big")
    checkWrite(fd, ddata) -- only checks file position (not block)

    local fd2 = checkOpen("big")
    for i = 1, 3 do
        local rd = disk.read(fd2, 1)
        assert(rd == read_char[i], "read incorrect character")
        disk.seek(fd2, 499)
    end
    
    disk.seek(fd2, -500)
    local d = disk.read(fd2, 1)
    assert(d == "e", "did not read e")
    
    disk.close(fd)
    disk.close(fd2)
end

local function checkHuge()
    local data = {}
    for i = 32, 127 do
        -- each exactly one block of data
        table.insert(data, string.rep(string.char(i), 500)) 
    end
    data = table.concat(data)

    local fd = checkOpen("huge")
    checkWrite(fd, data)

    local fd2 = checkOpen("huge")
    checkRead(fd2, data)
    disk.close(fd)
    disk.close(fd2)
    
    -- Seek to different blocks, verify that seek updates the current block
    local fd3 = checkOpen("huge")
    for i = 32, 127 do
        local data = disk.read(fd3, 1)
        local expected = string.rep(string.char(i), 1)
        assert(data == expected,
           'exp ' .. expected .. ' got ' .. data .. " (index: " .. i .. ")")
        disk.seek(fd3, 500)
    end
    disk.seek(fd3, -500)
    for i = 32, 127 do
        local data = disk.read(fd3, 1)
        local expected = string.rep(string.char(159 - i), 1)
        assert(data == expected,
           'exp ' .. expected .. ' got ' .. data .. " (index: " .. i .. ")")
        disk.seek(fd3, -500)
    end
    disk.close(fd3)
end

check(disk.format("disks/A05-eseek.sfs", 4096 * 13))
checkBig()
checkHuge()
