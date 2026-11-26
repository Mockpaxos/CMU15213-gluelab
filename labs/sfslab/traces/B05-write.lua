-- Write to files sequentially.

local N_THREADS = 5
local SHORT_CONTENTS = 
"According to all known laws of aviation, there is no way that a bee should be able to fly. Its wings are too small to get its fat little body off the ground. The bee, of course, flies anyways. Because bees don't care what humans think is impossible."

local REVERSED_CONTENTS =
".elbissopmi si kniht snamuh tahw erac t'nod seeb esuaceB .syawyna seilf ,esruoc fo ,eeb ehT .dnuorg eht ffo ydob elttil taf sti teg ot llams oot era sgniw stI .ylf ot elba eb dluohs eeb a taht yaw on si ereht ,noitaiva fo swal nwonk lla ot gnidroccA"

local BUFFERED_CONTENTS =
"Acrigt l nw aso vain hr sn a htabesol eal ofy t ig r o ml ogtisftltl oyoftegon.Tebe fcus,fisayas eas esdntcr hthmn hn sipsil."

local function check(rv, ...)
  if not rv then
      message = ...
      error(message, 2)
  end
  return rv
end

check(disk.format("disks/B05-write.sfs", 4096))

local function writefile()
  local fd = check(disk.open("B05-fname.txt"))
  assert(check(disk.write(fd, SHORT_CONTENTS)) == #SHORT_CONTENTS)
  check(disk.seek(fd, -(#SHORT_CONTENTS)))
  assert(check(disk.read(fd, #SHORT_CONTENTS)) == SHORT_CONTENTS)
  check(disk.seek(fd, -(#SHORT_CONTENTS)))

  assert(check(disk.write(fd, REVERSED_CONTENTS)) == #REVERSED_CONTENTS)
  check(disk.seek(fd, -(#REVERSED_CONTENTS)))
  assert(check(disk.read(fd, #REVERSED_CONTENTS)) == REVERSED_CONTENTS)
  check(disk.seek(fd, -(#REVERSED_CONTENTS)))
  disk.close(fd)
  disk.remove("B05-fname.txt")
  return true
end

local function bufferedWrite()
  local fd = check(disk.open("B05-bname.txt"))
  for i = 1, #SHORT_CONTENTS do
    if i % 2 == 1 then
      local s = string.sub(SHORT_CONTENTS, i, i)
      assert(check(disk.write(fd, s)) == #s)
    end
  end
  check(disk.seek(fd, -(#SHORT_CONTENTS)))
  assert(check(disk.read(fd, #SHORT_CONTENTS)) == BUFFERED_CONTENTS)
  disk.close(fd)
  disk.remove("B05-bname.txt")
  return true
end

for i = 1, N_THREADS do
  writefile()
  bufferedWrite()
end

local files = disk.list()
assert(#files == 0)


