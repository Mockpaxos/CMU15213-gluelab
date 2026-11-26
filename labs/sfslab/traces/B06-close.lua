-- open and close files repeatedly, ensuring contents are preserved
-- checks that certain operations on closed/open files behave as they should 
-- tests with file system limit in terms of number of open files possible

-- macro taken from sfs-disk.c
local FILE_COUNT_LIMIT = 15

local function check(rv, ...)
  if not rv then
      message = ...
      error(message, 2)
  end
  return rv
end

-- need extra space on disk than just 4096 because we are maxing out on file count
check(disk.format("disks/B06-close.sfs", 4096 * 50))

local function openClose()
  local fds = {}
  for i = 1, FILE_COUNT_LIMIT do
    local name = "file" .. tostring(i) .. ".txt"
    fds[i] = check(disk.open(name))
    assert(check(disk.getPos(fds[i])) == 0)
    disk.seek(fds[i], 15213)
    assert(check(disk.getPos(fds[i])) == 0)
  end

  local sumOfFds = 0 
  for i = 1, FILE_COUNT_LIMIT do
    sumOfFds = sumOfFds + fds[i]
  end
  sumOfFds = sumOfFds + 1

  assert(not disk.getPos(sumOfFds))

  for i = 1, FILE_COUNT_LIMIT do
    disk.close(fds[i])
    assert(not disk.getPos(fds[i]))
    assert(not disk.seek(fds[i], 0))
  end
  return true
end

openClose()