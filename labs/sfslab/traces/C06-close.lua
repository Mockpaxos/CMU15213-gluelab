-- open and close files repeatedly, ensuring contents are preserved
-- checks that certain operations on closed/open files behave as they should 
-- we modify the OPEN_FILE_LIMIT since we need to account for the possible of all threads having all possible files open

lanes.configure{ with_timers = false }

local N_THREADS = 5

-- based on macro from sfs-disk.c
local FILE_COUNT_LIMIT = 15 // N_THREADS

local function check(rv, ...)
  if not rv then
      message = ...
      error(message, 2)
  end
  return rv
end


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
    disk.getPos(fds[i])
    disk.seek(fds[i], 0)
  end
  return true
end

check(disk.format("disks/C06-close.sfs", 4096))

local laneproc = lanes.gen("string,disk", openClose)

local lanes = {}
for i = 1, N_THREADS do
  lanes[i] = laneproc(i)
end

for i = 1, N_THREADS do
  check(lanes[i]:join())
end
