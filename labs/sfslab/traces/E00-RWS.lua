-- 1. Creates a file that consists of 15,360,000 characters of A
-- 2. Launches four threads that share this file descriptor
--      Two of these will seek a quarter of the file in 40 chunks
--      Two of these will write 96,000 characters of B in 40 chunks
-- 3. Launches four threads that share this file descriptor
--      Two of these will seek a quarter of the file in 40 chunks
--      Two of these will read 96,000 characters in 40 chunks, asserting that
--        all characters are the same
-- 4. This will repeat with 8 threads


lanes.configure { with_timers = false }

local function check(rv, ...)
    if not rv then
        message = ...
        error(message, 2)
    end
    return rv
end

local function creat(file, contents)
    local fd = check(disk.open(file))
    assert(check(disk.write(fd, contents)) == #contents)
    disk.close(fd)
end

local function seek_job(fd, num_seeks, seek_width)
  for i = 1, num_seeks do
    check(disk.seek(fd, seek_width))
  end
  return 0
end

local function write_job(fd, num_writes, write_string)
  for i = 1, num_writes do
    assert(check(disk.write(fd, write_string)) == #write_string)
  end
  return 0
end

local function read_job(fd, num_reads, possibility1, possibility2)
  for i = 1, num_reads do
    local chunk = disk.read(fd, #possibility1)
    if chunk ~= possibility1 and chunk ~= possibility2 then
      error(string.format("ERROR"))
    end
  end
  return 0
end

local SMALL_FILE = -- [[AAAAAAAAAAAAAAA]] -- 1500 characters exactly 
[[AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA]]

local SMALL_FILE_B = -- [[BBBBBBBBBBBBBBB]] -- 1500 characters exactly
[[BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB]]

local MEDIUM_FILE = SMALL_FILE .. SMALL_FILE .. SMALL_FILE .. SMALL_FILE -- 6000 characters exactly
local LARGE_FILE = MEDIUM_FILE .. MEDIUM_FILE .. MEDIUM_FILE .. MEDIUM_FILE -- 24000 characters exactly
local HUGE_FILE = LARGE_FILE .. LARGE_FILE .. LARGE_FILE .. LARGE_FILE -- 96000 characters exactly
local MASSIVE_FILE = HUGE_FILE .. HUGE_FILE .. HUGE_FILE .. HUGE_FILE -- 384000 characters exactly
local GIGANTIC_FILE = MASSIVE_FILE .. MASSIVE_FILE .. MASSIVE_FILE .. MASSIVE_FILE -- 1536000 characters exactly

GIGANTIC_FILE = GIGANTIC_FILE .. GIGANTIC_FILE .. GIGANTIC_FILE .. GIGANTIC_FILE .. GIGANTIC_FILE
GIGANTIC_FILE = GIGANTIC_FILE .. GIGANTIC_FILE

local MEDIUM_FILE_B = SMALL_FILE_B .. SMALL_FILE_B .. SMALL_FILE_B .. SMALL_FILE_B -- 6000 characters exactly
local LARGE_FILE_B = MEDIUM_FILE_B .. MEDIUM_FILE_B .. MEDIUM_FILE_B .. MEDIUM_FILE_B
local HUGE_FILE_B = LARGE_FILE_B .. LARGE_FILE_B .. LARGE_FILE_B .. LARGE_FILE_B

-- We need space for the massive file, plus the
-- superblock.  For each 500 bytes of data there are 12 bytes of
-- overhead.
local N_BLOCKS = (
    (#GIGANTIC_FILE / 500)
    + 1) * 512
-- And as usual we must round up to a multiple of 4096.
N_BLOCKS = ((N_BLOCKS + 4095) // 4096) * 4096

assert(#HUGE_FILE == #HUGE_FILE_B)

check(disk.format("disks/E00-RWS.sfs", N_BLOCKS))

creat("gigantic", GIGANTIC_FILE)

local lane_seek = lanes.gen("string,disk", seek_job)
local lane_write = lanes.gen("string,disk", write_job)
local lane_read = lanes.gen("string,disk", read_job)
local lanes = {}

local fd = check(disk.open("gigantic"))

lanes[1] = lane_seek(fd, 40, #HUGE_FILE)
lanes[2] = lane_write(fd, 40, HUGE_FILE_B)
lanes[3] = lane_seek(fd, 40, #HUGE_FILE)
lanes[4] = lane_write(fd, 40, HUGE_FILE_B)

check(lanes[1]:join())
check(lanes[2]:join())
check(lanes[3]:join())
check(lanes[4]:join())

disk.close(fd)

local file = check(disk.open("gigantic"))

-- Uncomment for a serial verification of the file
-- read_job(file, 160, HUGE_FILE, HUGE_FILE_B)

lanes[5] = lane_seek(file, 40, #HUGE_FILE)
lanes[6] = lane_read(file, 40, HUGE_FILE, HUGE_FILE_B)
lanes[7] = lane_seek(file, 40, #HUGE_FILE)
lanes[8] = lane_read(file, 40, HUGE_FILE, HUGE_FILE_B)

check(lanes[5]:join())
check(lanes[6]:join())
check(lanes[7]:join())
check(lanes[8]:join())

disk.close(file)

-- Round with 8 threads

local fd2 = check(disk.open("gigantic"))

lanes[1] = lane_seek(fd, 20, #HUGE_FILE)
lanes[2] = lane_write(fd, 20, HUGE_FILE_B)
lanes[3] = lane_seek(fd, 20, #HUGE_FILE)
lanes[4] = lane_write(fd, 20, HUGE_FILE_B)
lanes[5] = lane_seek(fd, 20, #HUGE_FILE)
lanes[6] = lane_write(fd, 20, HUGE_FILE_B)
lanes[7] = lane_seek(fd, 20, #HUGE_FILE)
lanes[8] = lane_write(fd, 20, HUGE_FILE_B)

check(lanes[1]:join())
check(lanes[2]:join())
check(lanes[3]:join())
check(lanes[4]:join())
check(lanes[5]:join())
check(lanes[6]:join())
check(lanes[7]:join())
check(lanes[8]:join())

disk.close(fd)

file = check(disk.open("gigantic"))

lanes[9] = lane_seek(fd, 20, #HUGE_FILE)
lanes[10] = lane_read(fd, 20, HUGE_FILE, HUGE_FILE_B)
lanes[11] = lane_seek(fd, 20, #HUGE_FILE)
lanes[12] = lane_read(fd, 20, HUGE_FILE, HUGE_FILE_B)
lanes[13] = lane_seek(fd, 20, #HUGE_FILE)
lanes[14] = lane_read(fd, 20, HUGE_FILE, HUGE_FILE_B)
lanes[15] = lane_seek(fd, 20, #HUGE_FILE)
lanes[16] = lane_read(fd, 20, HUGE_FILE, HUGE_FILE_B)

check(lanes[9]:join())
check(lanes[10]:join())
check(lanes[11]:join())
check(lanes[12]:join())
check(lanes[13]:join())
check(lanes[14]:join())
check(lanes[15]:join())
check(lanes[16]:join())

disk.close(file)