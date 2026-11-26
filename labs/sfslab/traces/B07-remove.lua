local N_THREADS = 5

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
  for i = 1, N_THREADS do
    name = "file" .. tostring(i) .. ".txt"
    arr[i] = check(disk.open(name))
  end
  for i = 1, N_THREADS do
    name = "file" .. tostring(i) .. ".txt"
    disk.close(arr[i])
    assert(check(disk.remove(name)))
  end
end

check(disk.format("disks/B07-remove.sfs", 4096))
checkSimpleRemove()