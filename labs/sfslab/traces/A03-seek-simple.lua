-- This trace tests your implementation of the 'seek' and 'getPos'
-- functions.

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

local function checkSmall()
    local fd = checkOpen("small")
    checkWrite(fd, "hello world\n")

    local fd2 = checkOpen("small")
    checkRead(fd2, "hello world\n")

    -- Do the same read check, but on the original fd
    checkRead(fd, "hello world\n")
    
    disk.close(fd)
    disk.close(fd2)
end

local function checkInvalid()
  local fd = disk.open("foo.txt")
  assert(not disk.seek(fd + 1, 732))
  disk.close(fd)
  assert(not disk.seek(fd, 800))
end

check(disk.format("disks/A03-seek-simple.sfs", 8 * 512))
checkSmall()
checkInvalid()
