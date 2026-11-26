lanes.configure{ with_timers = false }

local N_THREADS = 5

local ITERS = 2

local function check(rv, ...)
  if not rv then
      message = ...
      error(message, 2)
  end
  return rv
end

local function checkSimpleRemove()
  assert(not disk.remove("This filename is a bit too long"))

  local arr = {}
  for i = 1, ITERS do
    name = "file" .. tostring(i) .. ".txt"
    arr[i] = check(disk.open(name))
  end
  for i = 1, ITERS do
    name = "file" .. tostring(i) .. ".txt"
    disk.close(arr[i])
    disk.remove(name)
  end
  return true
end

check(disk.format("disks/C07-remove.sfs", 4096))

local laneproc = lanes.gen("string,disk", checkSimpleRemove)

local lanes = {}
for i = 1, N_THREADS do
  lanes[i] = laneproc(i)
end

for i = 1, N_THREADS do
  check(lanes[i]:join())
end
