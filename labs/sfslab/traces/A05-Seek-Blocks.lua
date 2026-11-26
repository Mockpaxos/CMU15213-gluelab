-- Will run the following checks on files with chunks of 1, 2, and 3 blocks
-- 1. Writes x blocks of B, seeks x blocks, writes x blocks of B
--    a. Asserts by doing the same read and seek pattern
--    b. Asserts by seeking x blocks, asserting x blocks of A
-- 2. Seeks x blocks, writes x blocks of B. Asserts with same pattern as previous
-- 3. Runs the initial seek pattern in 1. but with reverse seeks.

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

local function assert_sandwich(contents, bread, meat)
    local combined = bread .. meat .. bread
    assert(contents == combined)
end

local function write_sandwich_seek(fd, bread)
    assert(check(disk.getPos(fd)) == 0)
    assert(check(disk.write(fd, bread)) == #bread)
    assert(check(disk.getPos(fd)) == #bread)
    assert(check(disk.seek(fd, #bread)) == #bread * 2)
    assert(check(disk.getPos(fd)) == #bread * 2)
    assert(check(disk.write(fd, bread)) == #bread)
    assert(check(disk.getPos(fd)) == #bread * 3)
end

local function write_sandwich_seek_rev(fd, bread)
    assert(check(disk.getPos(fd)) == 0)
    assert(check(disk.seek(fd, #bread * 2)) == #bread * 2)
    assert(check(disk.write(fd, bread)) == #bread)
    assert(check(disk.getPos(fd)) == #bread * 3)
    assert(check(disk.seek(fd, #bread * -3)) == 0)
    assert(check(disk.getPos(fd)) == 0)
    assert(check(disk.write(fd, bread)) == #bread)
    assert(check(disk.getPos(fd)) == #bread)
end

local function read_sandwich_seek(fd, bread)
    assert(check(disk.getPos(fd)) == 0)
    assert(check(disk.read(fd, #bread)) == bread)
    assert(check(disk.getPos(fd)) == #bread)
    assert(check(disk.seek(fd, #bread)) == #bread * 2)
    assert(check(disk.getPos(fd)) == #bread * 2)
    assert(check(disk.read(fd, #bread)) == bread)
    assert(check(disk.getPos(fd)) == #bread * 3)
end

local function read_sandwich_seek_rev(fd, bread)
    assert(check(disk.getPos(fd)) == 0)
    assert(check(disk.seek(fd, #bread * 2)) == #bread * 2)
    assert(check(disk.read(fd, #bread)) == bread)
    assert(check(disk.getPos(fd)) == #bread * 3)
    assert(check(disk.seek(fd, #bread * -3)) == 0)
    assert(check(disk.getPos(fd)) == 0)
    assert(check(disk.read(fd, #bread)) == bread)
    assert(check(disk.getPos(fd)) == #bread)
end

local function seek_sandwich_write(fd, meat)
    assert(check(disk.getPos(fd)) == 0)
    assert(check(disk.seek(fd, #meat)) == #meat)
    assert(check(disk.getPos(fd)) == #meat)
    assert(check(disk.write(fd, meat)) == #meat)
    assert(check(disk.getPos(fd)) == #meat * 2)
    assert(check(disk.seek(fd, #meat)) == #meat * 3)
    assert(check(disk.getPos(fd)) == #meat * 3)
end

local function seek_sandwich_read(fd, meat)
    assert(check(disk.getPos(fd)) == 0)
    assert(check(disk.seek(fd, #meat)) == #meat)
    assert(check(disk.getPos(fd)) == #meat)
    assert(check(disk.read(fd, #meat)) == meat)
    assert(check(disk.getPos(fd)) == #meat * 2)
    assert(check(disk.seek(fd, #meat)) == #meat * 3)
    assert(check(disk.getPos(fd)) == #meat * 3)
end

local function run_write_sandwich_seek(filename, bread, expected)
    local fd1 = check(disk.open(filename))
    write_sandwich_seek(fd1, bread)
    disk.close(fd1)

    local fd2 = check(disk.open(filename))
    local contents = disk.read(fd2, #expected)
    assert(contents == expected)
    disk.close(fd2)
end

local function run_write_sandwich_seek_rev(filename, bread, expected)
    local fd1 = check(disk.open(filename))
    write_sandwich_seek_rev(fd1, bread)
    disk.close(fd1)

    local fd2 = check(disk.open(filename))
    local contents = disk.read(fd2, #expected)
    assert(contents == expected)
    disk.close(fd2)
end

local function run_read_sandwich_seek(filename, bread)
    local fd1 = check(disk.open(filename))
    read_sandwich_seek(fd1, bread)
    disk.close(fd1)
end

local function run_read_sandwich_seek_rev(filename, bread)
    local fd1 = check(disk.open(filename))
    read_sandwich_seek_rev(fd1, bread)
    disk.close(fd1)
end

local function run_seek_sandwich_write(filename, meat, expected)
    local fd1 = check(disk.open(filename))
    seek_sandwich_write(fd1, meat)
    disk.close(fd1)

    local fd2 = check(disk.open(filename))
    local contents = disk.read(fd2, #expected)
    assert(contents == expected)
    disk.close(fd2)
end

local function run_seek_sandwich_read(filename, meat)
    local fd1 = check(disk.open(filename))
    seek_sandwich_read(fd1, meat)
    disk.close(fd1)
end

BLOCK_OF_A = [[AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA]]

BLOCK_OF_B = [[BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB]]

TWO_BLOCKS_A = BLOCK_OF_A .. BLOCK_OF_A
THREE_BLOCKS_A = BLOCK_OF_A .. BLOCK_OF_A .. BLOCK_OF_A

TWO_BLOCKS_B = BLOCK_OF_B .. BLOCK_OF_B
THREE_BLOCKS_B = BLOCK_OF_B .. BLOCK_OF_B .. BLOCK_OF_B

SMALL_FILE = THREE_BLOCKS_A
MEDIUM_FILE = THREE_BLOCKS_A .. THREE_BLOCKS_A
LARGE_FILE = THREE_BLOCKS_A .. THREE_BLOCKS_A .. THREE_BLOCKS_A

SMALL_1_RES = BLOCK_OF_B .. BLOCK_OF_A .. BLOCK_OF_B
SMALL_2_RES = BLOCK_OF_A .. BLOCK_OF_B .. BLOCK_OF_A

MED_1_RES = TWO_BLOCKS_B .. TWO_BLOCKS_A .. TWO_BLOCKS_B
MED_2_RES = TWO_BLOCKS_A .. TWO_BLOCKS_B .. TWO_BLOCKS_A

LARGE_1_RES = THREE_BLOCKS_B .. THREE_BLOCKS_A .. THREE_BLOCKS_B
LARGE_2_RES = THREE_BLOCKS_A .. THREE_BLOCKS_B .. THREE_BLOCKS_A

check(disk.format("disks/A05-seek-blocks.sfs", 4096 * 50))

-- Small file

creat("small1", SMALL_FILE)
run_write_sandwich_seek("small1", BLOCK_OF_B, SMALL_1_RES)
run_read_sandwich_seek("small1", BLOCK_OF_B)
run_seek_sandwich_read("small1", BLOCK_OF_A)

creat("small2", SMALL_FILE)
run_seek_sandwich_write("small2", BLOCK_OF_B, SMALL_2_RES)
run_read_sandwich_seek("small2", BLOCK_OF_A)
run_seek_sandwich_read("small2", BLOCK_OF_B)

creat("small1_rev", SMALL_FILE)
run_write_sandwich_seek_rev("small1_rev", BLOCK_OF_B, SMALL_1_RES)
run_read_sandwich_seek("small1_rev", BLOCK_OF_B)
run_seek_sandwich_read("small1_rev", BLOCK_OF_A)
run_read_sandwich_seek_rev("small1_rev", BLOCK_OF_B)

-- Medium file

creat("med1", MEDIUM_FILE)
run_write_sandwich_seek("med1", TWO_BLOCKS_B, MED_1_RES)
run_read_sandwich_seek("med1", TWO_BLOCKS_B)
run_seek_sandwich_read("med1", TWO_BLOCKS_A)

creat("med2", MEDIUM_FILE)
run_seek_sandwich_write("med2", TWO_BLOCKS_B, MED_2_RES)
run_read_sandwich_seek("med2", TWO_BLOCKS_A)
run_seek_sandwich_read("med2", TWO_BLOCKS_B)

creat("med1_rev", MEDIUM_FILE)
run_write_sandwich_seek_rev("med1_rev", TWO_BLOCKS_B, MED_1_RES)
run_read_sandwich_seek("med1_rev", TWO_BLOCKS_B)
run_seek_sandwich_read("med1_rev", TWO_BLOCKS_A)
run_read_sandwich_seek_rev("med1_rev", TWO_BLOCKS_B)

-- Large file

creat("large1", LARGE_FILE)
run_write_sandwich_seek("large1", THREE_BLOCKS_B, LARGE_1_RES)
run_read_sandwich_seek("large1", THREE_BLOCKS_B)
run_seek_sandwich_read("large1", THREE_BLOCKS_A)

creat("large2", LARGE_FILE)
run_seek_sandwich_write("large2", THREE_BLOCKS_B, LARGE_2_RES)
run_read_sandwich_seek("large2", THREE_BLOCKS_A)
run_seek_sandwich_read("large2", THREE_BLOCKS_B)

creat("large1_rev", MEDIUM_FILE)
run_write_sandwich_seek_rev("large1_rev", THREE_BLOCKS_B, LARGE_1_RES)
run_read_sandwich_seek("large1_rev", THREE_BLOCKS_B)
run_seek_sandwich_read("large1_rev", THREE_BLOCKS_A)
run_read_sandwich_seek_rev("large1_rev", THREE_BLOCKS_B)