//
// SFS Disk - Shark File System Implementation
//
// The Shark File System is a simple, FAT-style file system that is
//   designed to illustrate the basic principles of a file system for
//   students and be extensible.  The file system relies on the "disk"
//   being memory mapped so updates to memory can be sent to durable
//   storage by the operating system.  The file system only supports
//   the bare minimum set of features - files can be accessed by name,
//   created, deleted, renamed, read from, written to.  A "production"
//   filesystem includes many other features, such as permissions,
//   access time, nested directories, long file names, etc.
//
// The disk is "formatted" into 512-byte blocks.  Each block is linked
//   to the other blocks, similar to a free list in malloc.
//
// The file system relies on the first block being the "superblock".
//   This special block contains the information about the disk being
//   used and can locate the root directory.  Under the current
//   implementation, there is only one directory, embedded in the
//   superblock; however, this could be changed by adding support for
//   a special file type of "directory" and modifying the file lookup
//   algorithm for opening a file.
//
// A file consists of one or more "disk blocks" which are chunks of 512
//   bytes.  Each block links to the one before and after it in the file,
//   which provide 500 bytes of space per allocated block.  The end of
//   the file is known by both the size of the file and the last block
//   links to block 0, which is "NULL".  A modern file system might
//   instead use a B-tree or other structure to manage the allocated
//   blocks.
//
// Open files are tracked using a two-level structure.  One level is the
//   open file descriptor tracking the position in the file for that
//   descriptor.  It links to a separate table that has a single entry
//   per file, which provides the current size of the file and the
//   reference count, so that a file could not be deleted while it is
//   still open.
//
// @author Brian Railing (bpr@cs.cmu.edu)
//

#include "sfs-disk.h"
#include "sfs-api.h"

#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

/** Maximum number of files that can exist.  Since we have not implemented
    expansion of the root directory, this is equal to the number of directory
    entries that can fit in a single disk block.  */
#define FILE_COUNT_LIMIT DIR_ENTRIES_PER_BLOCK

/** Maximum number of open files.  This is intentionally larger
    than the number of files that can exist; some of the traces
    open the same file more than once.  */
#define OPEN_FILE_LIMIT 32

static_assert(sizeof(sfs_block_file_t) == SFS_BLOCK_SIZE,
              "SFS_BLOCK_SIZE and sfs_block_file_t are out of sync");
static_assert(sizeof(sfs_block_dir_t) == SFS_BLOCK_SIZE,
              "SFS_BLOCK_SIZE and sfs_block_dir_t are out of sync");
static_assert(sizeof(sfs_filesystem_t) == SFS_BLOCK_SIZE,
              "SFS_BLOCK_SIZE and sfs_filesystem_t are out of sync");

/** This struct corresponds to what CS:APP calls a "v-node table" entry. */
typedef struct sfs_mem_file_t
{
    uint32_t refCount;
    int fileEntryIdx;
    sfs_dir_entry_t *diskFile;
} sfs_mem_file_t;

/** This struct corresponds to what CS:APP calls an "open file table" entry.
    The "descriptor table" is the openFileDescTable array itself. */
typedef struct sfs_mem_filedesc_t
{
    sfs_mem_file_t *fileEntry;
    block_id startBlock;
    block_id currBlock;
    size_t currPos;  // current position in file
    size_t blockPos; // current position in current block (not entire file)
} sfs_mem_filedesc_t;

static_assert(sizeof SFS_DISK_MAGIC == offsetof(sfs_filesystem_t, n_blocks),
              "'type' field of sfs_filesystem_t does not match SFS_DISK_MAGIC");

static sfs_mem_file_t *openFileTable[FILE_COUNT_LIMIT];
static sfs_mem_filedesc_t *openFileDescTable[OPEN_FILE_LIMIT];

//
// Internal subroutines
//

/** Round up the size_t value SIZE to the nearest multiple of N.
    Special case: for all nonzero k, roundUp(k*N, N) returns k*N,
    but roundUp(0, N) returns N.  */
static size_t roundUp(size_t size, size_t n)
{
    if (size == 0)
        size = 1;
    return n * ((size + (n - 1)) / n);
}

/** Return the smaller of two size_t quantities. */
static size_t sizeMin(size_t a, size_t b)
{
    return a < b ? a : b;
}

/** Allocate N_BLOCKS free blocks from the free list.  Set each newly
    allocated block's type to TYPE, and chain them all together.
    Return the block ID of the first block in the chain.

    If N_BLOCKS blocks are not currently available for allocation,
    leaves the free list unchanged and returns 0.  Also returns 0
    if N_BLOCKS is zero.  */
static block_id allocateBlocks(uint32_t n_blocks, const char *type)
{
    sfs_filesystem_t *super = accessSuperBlock();
    if (super->freelist == 0 || n_blocks == 0)
        return 0;

    block_id first_alloc_id = super->freelist;
    sfs_block_hdr_t *first_alloc_blk = accessFreeBlock(first_alloc_id);

    block_id last_alloc_id = first_alloc_id;
    sfs_block_hdr_t *last_alloc_blk = first_alloc_blk;

    for (uint32_t i = 1; i < n_blocks; i++)
    {
        if (last_alloc_blk->next_block == 0)
            return 0; // not enough free blocks available
        last_alloc_id = last_alloc_blk->next_block;
        last_alloc_blk = accessFreeBlock(last_alloc_id);
    }

    // At this point we know that we have n_blocks free blocks available.
    // 'first_alloc_blk' points to the first block being allocated and
    // 'last_alloc_blk' points to the last block being allocated (*not*
    // one beyond).
    block_id next_free_id = last_alloc_blk->next_block;
    if (next_free_id != 0)
    {
        sfs_block_hdr_t *next_free_blk = accessFreeBlock(next_free_id);
        next_free_blk->prev_block = 0;
        last_alloc_blk->next_block = 0;
    }
    super->freelist = next_free_id;

    for (sfs_block_hdr_t *b = first_alloc_blk; b;
         b = accessFreeBlock(b->next_block))
        setBlockType(b, type);

    return first_alloc_id;
}

/** Deallocate all of the blocks in the allocation chain starting at
    'first_block'; that is, move them to the free list and change their type
    to SFS_BLOCK_TYPE_FREE.  'first_block' does not have to be the very
    first block in an allocation chain.  */
static void freeBlocks(block_id first_block)
{
    sfs_filesystem_t *superBlock = accessSuperBlock();
    sfs_block_hdr_t *b = accessBlock(first_block);
    if (b->prev_block != 0)
    {
        sfs_block_hdr_t *p = accessBlock(b->prev_block);
        p->next_block = 0;
        b->prev_block = 0;
    }

    for (;;)
    {
        setBlockType(b, SFS_BLOCK_TYPE_FREE);
        if (b->next_block == 0)
            break;
        b = accessBlock(b->next_block);
    }
    b->next_block = superBlock->freelist;
    if (superBlock->freelist != 0)
        accessFreeBlock(superBlock->freelist)->prev_block = idOfBlock(b);
    superBlock->freelist = first_block;
}

/** Creates a new descriptor entry for an existing file.  */
static int addOpenFileEntry(int entryIndex)
{
    sfs_mem_filedesc_t *memDescFile = NULL;
    sfs_mem_file_t *fileEntry = NULL;
    int fd = -1;

    for (int idx = 0; idx < OPEN_FILE_LIMIT; idx++)
    {
        if (openFileDescTable[idx] == NULL)
        {
            memDescFile = malloc(sizeof(sfs_mem_filedesc_t));
            if (memDescFile == NULL)
                return -ENOMEM;
            fd = idx;
            break;
        }
    }

    if (memDescFile == NULL)
        return -EMFILE;

    fileEntry = openFileTable[entryIndex];
    if (fileEntry == NULL)
    {
        fileEntry = malloc(sizeof(sfs_mem_file_t));
        if (fileEntry == NULL)
        {
            free(memDescFile);
            return -ENOMEM;
        }

        sfs_filesystem_t *superBlock = accessSuperBlock();
        fileEntry->diskFile = &superBlock->files[entryIndex];
        fileEntry->fileEntryIdx = entryIndex;
        fileEntry->refCount = 0;
        openFileTable[entryIndex] = fileEntry;
    }

    fileEntry->refCount += 1;
    memDescFile->fileEntry = fileEntry;
    memDescFile->startBlock = fileEntry->diskFile->first_block;
    memDescFile->currBlock = memDescFile->startBlock;
    memDescFile->currPos = 0;
    memDescFile->blockPos = 0;
    openFileDescTable[fd] = memDescFile;
    return fd;
}

/** Create a new file named 'fileName' and return an open-file-table
    entry for it.  'emptyIndex' is known to be a free slot in the
    directory on disk.  */
static int createFile(const char *fileName, int emptyIndex)
{
    // Every file must occupy at least one block on disk, even if
    // it is empty.  This is because we use nonzero 'first_block'
    // to identify files that do exist.  (Optional puzzle for you:
    // find a way to avoid this, so that empty files consume only
    // a directory entry.)

    block_id startBlock = allocateBlocks(1, SFS_BLOCK_TYPE_FILE);
    if (startBlock == 0)
        return -ENOSPC;

    sfs_filesystem_t *superBlock = accessSuperBlock();
    sfs_dir_entry_t *sfe = &superBlock->files[emptyIndex];
    sfe->first_block = startBlock;
    sfe->size = 0;

    // Overlength names _should_ have been excluded at a higher level.
    size_t len = strlen(fileName);
    // Copy the name and then clear the rest of the space.
    memcpy(sfe->name, fileName, len);
    memset(sfe->name + len, '\0', SFS_FILE_NAME_SIZE_LIMIT - len);

    return addOpenFileEntry(emptyIndex);
}

//
// SFS API functions begin here
// see sfs-api.h for documentation comments for these functions
//

int sfs_open(const char *fileName)
{
    int ret;

    // Can only have 23 characters, because the string on disk is NUL
    // terminated.
    if (strnlen(fileName, SFS_FILE_NAME_SIZE_LIMIT + 1) + 1 >
        SFS_FILE_NAME_SIZE_LIMIT)
    {
        ret = -ENAMETOOLONG;
        goto end;
    }

    // Is a disk image available?
    if (getSFSStatus() < 0)
    {
        ret = -ENOMEDIUM;
        goto end;
    }

    sfs_filesystem_t *superBlock = accessSuperBlock();
    int fileEntry;
    int emptyEntry = -1;
    for (fileEntry = 0; (unsigned long)fileEntry < FILE_COUNT_LIMIT;
         fileEntry++)
    {
        if (superBlock->files[fileEntry].first_block != 0 &&
            strcmp(superBlock->files[fileEntry].name, fileName) == 0)
        {
            ret = addOpenFileEntry(fileEntry);
            goto end;
        }
        else if (emptyEntry == -1 &&
                 superBlock->files[fileEntry].first_block == 0)
        {
            emptyEntry = fileEntry;
        }
    }

    if (emptyEntry == -1)
    {
        ret = -ENOSPC;
        goto end;
    }

    ret = createFile(fileName, emptyEntry);

end:
    return ret;
}

//
//  initFSInternals
//    this routine allows the file system to initialize other internal
//    components as necessary.  The current design does not require any
//    additional initialization, but student designs may do so.
//
//    returns 0 if initialization is successful
//
int initFSInternals(void)
{
    return 0;
}

int checkFSUnmount(void)
{
    for (int idx = 0; idx < OPEN_FILE_LIMIT; idx++)
    {
        if (openFileDescTable[idx] != NULL)
            return -EBUSY;
    }
    for (int idx = 0; (unsigned long)idx < FILE_COUNT_LIMIT; idx++)
        assert(openFileTable[idx] == NULL);
    return 0;
}

void sfs_close(int fd)
{
    if (fd < 0 || fd >= OPEN_FILE_LIMIT)
        return;

    sfs_mem_filedesc_t *tFile = openFileDescTable[fd];
    if (tFile == NULL)
        return;

    sfs_mem_file_t *fileEntry = tFile->fileEntry;
    int idx = fileEntry->fileEntryIdx;

    openFileDescTable[fd] = NULL;
    fileEntry->refCount -= 1;
    int lastRef = (fileEntry->refCount == 0);
    if (lastRef)
        openFileTable[idx] = NULL;

    free(tFile);
    if (lastRef)
        free(fileEntry);
}

ssize_t sfs_read(int fd, char *buf, size_t len)
{
    sfs_mem_filedesc_t *tFile;
    size_t fileSize;
    size_t currPos;
    size_t totalToRead;
    size_t toRead;
    size_t blockPos;
    size_t chunkSize;
    sfs_block_file_t *diskBlock;

    if (fd < 0 || fd >= OPEN_FILE_LIMIT)
        return -EBADF;

    tFile = openFileDescTable[fd];
    if (tFile == NULL)
        return -EBADF;

    fileSize = tFile->fileEntry->diskFile->size;
    currPos = tFile->currPos;

    assert(currPos <= fileSize);
    totalToRead = sizeMin(fileSize - currPos, len);
    toRead = totalToRead;

    diskBlock = accessFileBlock(tFile->currBlock);
    blockPos = tFile->blockPos;
    chunkSize = sizeMin(BLOCK_DATA_SIZE - blockPos, toRead);

    for (;;)
    {
        if (chunkSize > 0)
        {
            memcpy(buf, &diskBlock->data[blockPos], chunkSize);
            buf += chunkSize;
            toRead -= chunkSize;
            blockPos += chunkSize;
        }
        if (toRead == 0)
            break;

        blockPos = 0;
        chunkSize = sizeMin(BLOCK_DATA_SIZE, toRead);
        diskBlock = accessFileBlock(diskBlock->h.next_block);
        assert(diskBlock != NULL);
    }

    tFile->currBlock = idOfBlock(&diskBlock->h);
    tFile->currPos = currPos + totalToRead;
    tFile->blockPos = blockPos;

    return (ssize_t)totalToRead;
}

ssize_t sfs_write(int fd, const char *buf, size_t len)
{
    sfs_mem_filedesc_t *tFile;
    size_t fileSize;
    size_t currPos;
    size_t fileAllocSize;
    size_t endPos;
    size_t toWrite;
    block_id firstNewId = 0;
    sfs_block_file_t *diskBlock;
    size_t blockPos;
    size_t chunkSize;

    if (fd < 0 || fd >= OPEN_FILE_LIMIT)
        return -EBADF;

    tFile = openFileDescTable[fd];
    if (tFile == NULL)
        return -EBADF;

    fileSize = tFile->fileEntry->diskFile->size;
    currPos = tFile->currPos;
    assert(currPos <= fileSize);

    fileAllocSize = roundUp(fileSize, BLOCK_DATA_SIZE);
    endPos = len + currPos;
    toWrite = len;

    if (endPos > fileAllocSize)
    {
        size_t fileNewAllocSize = roundUp(endPos, BLOCK_DATA_SIZE);
        if (fileNewAllocSize > SFS_MAX_FILE_SIZE)
            return -EFBIG;

        uint32_t addlBlocks =
            (uint32_t)((fileNewAllocSize - fileAllocSize) / BLOCK_DATA_SIZE);
        assert(addlBlocks >= 1);

        firstNewId = allocateBlocks(addlBlocks, SFS_BLOCK_TYPE_FILE);
        if (firstNewId == 0)
            return -ENOSPC;
    }

    diskBlock = accessFileBlock(tFile->currBlock);
    blockPos = tFile->blockPos;
    chunkSize = sizeMin(BLOCK_DATA_SIZE - blockPos, toWrite);

    for (;;)
    {
        if (chunkSize > 0)
        {
            memcpy(&diskBlock->data[blockPos], buf, chunkSize);
            buf += chunkSize;
            toWrite -= chunkSize;
            blockPos += chunkSize;
        }
        if (toWrite == 0)
            break;

        blockPos = 0;
        chunkSize = sizeMin(BLOCK_DATA_SIZE, toWrite);
        sfs_block_file_t *nextBlock = accessFileBlock(diskBlock->h.next_block);
        if (nextBlock == NULL)
        {
            assert(firstNewId != 0);
            nextBlock = accessFileBlock(firstNewId);
            diskBlock->h.next_block = firstNewId;
            nextBlock->h.prev_block = idOfBlock(&diskBlock->h);
            firstNewId = 0;
        }
        diskBlock = nextBlock;
    }

    tFile->currBlock = idOfBlock(&diskBlock->h);
    tFile->currPos = endPos;
    tFile->blockPos = blockPos;
    if (endPos > fileSize)
        tFile->fileEntry->diskFile->size = (uint32_t)endPos;

    return (ssize_t)len;
}

ssize_t sfs_getpos(int fd)
{
    /* TODO: Implement according to sfs-api.h. */
    return -ENOSYS;
}

ssize_t sfs_seek(int fd, ssize_t delta)
{
    /* TODO: Implement according to sfs-api.h. */
    return -ENOSYS;
}

int sfs_remove(const char *name)
{
    int ret;

    // Can only have 23 characters, because the string on disk is NUL
    // terminated.
    if (strlen(name) + 1 > SFS_FILE_NAME_SIZE_LIMIT)
    {
        ret = -ENAMETOOLONG;
        goto end;
    }

    // Is a disk image available?
    if (getSFSStatus() < 0)
    {
        ret = -ENOMEDIUM;
        goto end;
    }

    sfs_filesystem_t *superBlock = accessSuperBlock();
    for (int fileEntry = 0; (unsigned long)fileEntry < FILE_COUNT_LIMIT;
         fileEntry++)
    {
        if (superBlock->files[fileEntry].first_block != 0 &&
            strcmp(superBlock->files[fileEntry].name, name) == 0)
        {
            // Is this file currently open?
            if (openFileTable[fileEntry] != NULL)
            {
                // The Unix convention is, when you delete a file that's
                // open, it disappears from its directory, but its contents
                // survive until everyone has closed it.  SFS is not set up
                // to handle this, so instead we refuse to delete files
                // that are open.  Optional challenge for you: Change SFS so
                // it *can* do what Unix does.
                ret = -EBUSY;
                goto end;
            }
            block_id firstBlock = superBlock->files[fileEntry].first_block;
            superBlock->files[fileEntry].first_block = 0;
            freeBlocks(firstBlock);
            ret = 0;
            goto end;
        }
    }

    // If we get here, the file we were asked to delete does not exist.
    // The Unix convention is to report this as an error.  It would be
    // equally valid to report success -- we were asked to make the
    // file not exist, and indeed it doesn't!
    ret = -ENOENT;

end:
    return ret;
}

int sfs_rename(const char *old_name, const char *new_name)
{
    /* TODO: Implement according to sfs-api.h. */
    return -ENOSYS;
}

int sfs_list(sfs_list_cookie *cookie, char filename_out[],
             size_t filename_space)
{
    int ret;

    // Corner case: If filename_space is zero, we cannot produce
    // an empty string into it on error.
    if (filename_space == 0)
    {
        ret = -EINVAL;
        goto end;
    }

    if (getSFSStatus() < 0)
    {
        ret = -ENOMEDIUM;
        goto end;
    }

    // The cookie value is just an offset within the localFiles array,
    // cast to void*.  It could be necessary to change this in order
    // to make the filesystem thread-safe, and/or to increase the
    // number of files that can exist.  If you decide to change it,
    // keep in mind that the "cookie" argument is a pointer _to_ the
    // cookie value, not the cookie value itself.
    uintptr_t next_file_slot = (uintptr_t)*cookie;
    struct sfs_filesystem_t *superBlock = accessSuperBlock();
    while (next_file_slot < FILE_COUNT_LIMIT)
    {
        sfs_dir_entry_t *e = &superBlock->files[next_file_slot];
        if (e->first_block)
        {
            // Found a "live" directory entry.
            size_t len = strlen(e->name);
            if (len + 1 > filename_space)
            {
                ret = -ENAMETOOLONG;
                goto end;
            }
            memcpy(filename_out, e->name, len + 1);
            *cookie = (void *)(next_file_slot + 1);
            ret = 0;
            goto end;
        }
        next_file_slot++;
    }

    // No more files to report.
    *cookie = NULL;
    ret = 1;

end:
    return ret;
}
