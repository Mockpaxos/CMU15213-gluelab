lanes.configure{ with_timers = false }

local N_THREADS = 5

local function check(rv, ...)
  if not rv then
      message = ...
      error(message, 2)
  end
  return rv
end

local function checkList(expectedLen)
  local files = disk.list()
  assert(#files == expectedLen)
  for i = 1, expectedLen do
    name = "file" .. tostring(i) .. ".txt"
    assert(files[i] == name)
  end
  return true 
end

local function simpleList()
  local arr = {}
  for i = 1, N_THREADS do
    name = "file" .. tostring(i) .. ".txt"
    arr[i] = check(disk.open(name))
  end

  for i = 1, N_THREADS do
    disk.close(arr[i])
  end
  for i = 1, N_THREADS do
    name = "file" .. tostring(N_THREADS - i + 1) .. ".txt"
    disk.remove(name)
  end
  return true 
end

local function sameList()
  local arr = {}
  for i = 1, N_THREADS do
    name = "same.txt"
    arr[i] = check(disk.open(name))
  end
  
  files = disk.list()
  assert(#files == 1)
  assert(files[1] == "same.txt")

  for i = 1, N_THREADS do
    disk.close(arr[i])
  end
  return true
end

check(disk.format("disks/C08-list.sfs", 4096))

local laneprocSimple = lanes.gen("string,disk", simpleList)
local laneprocSame = lanes.gen("string,disk", sameList)

local lanes = {}
for i = 1, N_THREADS do
  lanes[i] = laneprocSimple(i)
end

for i = 1, N_THREADS do
  check(lanes[i]:join())
end

assert(#disk.list() == 0)

local lanes = {}
for i = 1, N_THREADS do
  lanes[i] = laneprocSame(i)
end

for i = 1, N_THREADS do
  check(lanes[i]:join())
end
