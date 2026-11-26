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
end

local function simpleList()
  local arr = {}
  for i = 1, N_THREADS do
    name = "file" .. tostring(i) .. ".txt"
    arr[i] = check(disk.open(name))
  end
  checkList(N_THREADS)

  for i = 1, N_THREADS do
    disk.close(arr[i])
    checkList(N_THREADS)
  end
  for i = 1, N_THREADS do
    name = "file" .. tostring(N_THREADS - i + 1) .. ".txt"
    disk.remove(name)
    checkList(N_THREADS - i)
  end
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
end


check(disk.format("disks/B08-list.sfs", 4096))
simpleList()
sameList()


