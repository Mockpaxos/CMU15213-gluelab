# Makefile for sfslab (origin version - not distributed to students)

CC           = gcc
CLANG_FORMAT = clang-format
CLANG        = /usr/bin/clang-14
OPT          = /usr/bin/opt-14
LLVM_LINK    = /usr/bin/llvm-link-14

LDFLAGS  = -O2 -g -pthread
CFLAGS   = -std=c11 $(LDFLAGS) $(WARNINGS)
CPPFLAGS = -D_GNU_SOURCE=1 -D_FORTIFY_SOURCE=2 -Ilua
WARNINGS = -Werror -Wall -Wextra -Wpedantic -Wconversion
WARNINGS += -Wstrict-prototypes -Wmissing-prototypes -Wwrite-strings
WARNINGS += -Wno-unused-parameter

PROGRAMS = sfs-fsck sfs-tester sfs-tester-ct

all: $(PROGRAMS)
.PHONY: all

# Linking rules. Note: Make does have built-in commands for linking
# but they don't work the way you might expect and are best avoided.

sfs-fsck: sfs-fsck.o
	$(CC) $(LDFLAGS) -o $@ $^ $(LIBS)

sfs-tester: LIBS = -lm -lreadline
sfs-tester: sfs-tester.o sfs-disk.o sfs-support.o lua/liblua.a
	$(CC) $(LDFLAGS) -o $@ $^ $(LIBS)

sfs-disk_ct.link.bc: sfs-disk_ct.ll
	objcopy --input binary --output elf64-x86-64 --binary-architecture i386 contech.bin contech_state.o
	$(LLVM_LINK) ct_sfs.bc $^ -o $@

sfs-disk.ll: sfs-disk.c
	$(CLANG) -O3 -S -emit-llvm -c $^

sfs-disk_ct.ll: sfs-disk.ll
	$(OPT) --enable-new-pm=0 -load=./LLVMContech.so -Contech $^ -o $@ -ContechState contech.bin

sfs-tester-ct: LIBS = -lm -lreadline
sfs-tester-ct: sfs-tester-ct.o sfs-disk_ct.link.bc sfs-support.o lua/liblua.a
	$(CLANG) -o $@ $^ -lrt -ldl -flto -lpthread contech_state.o $(LIBS)

lua/liblua.a:
	$(MAKE) -C lua liblua.a

# Dependency rules for object files are automatically generated; see
# the bottom of this file.

clean:
	-rm -f $(PROGRAMS) *.o *.ll
	$(MAKE) -C lua clean
.PHONY: clean

FORMAT_FILES = $(wildcard *.[ch])
format:
	$(CLANG_FORMAT) -style=file -i $(FORMAT_FILES)
.PHONY: format

regen-deps:
	(sed -ne '1,/^## cut here ##$$/p' Makefile && \
	 $(CC) $(CPPFLAGS) -MM *.c) > Makefile.n
	mv -f Makefile.n Makefile
.PHONY: regen-deps

# Include rules for submit, format, etc
HANDIN_FILES = sfs-disk.c sfs-disk.h \
	.clang-format .format-checked
HANDIN_TAR = sfslab-handin.tar
include .labname.mk
include helper.mk

# Do not edit below this point; use 'make regen-deps' instead.
## cut here ##
sfs-disk.o: sfs-disk.c sfs-support.c sfs-disk.h sfs-api.h
sfs-fsck.o: sfs-fsck.c sfs-disk.h
sfs-tester-ct.o: sfs-tester-ct.c lua/lanes/lanes.h lua/lua.h lua/luaconf.h \
 lua/lanes/platform.h lua/lauxlib.h lua/lua.h lua/lualib.h sfs-api.h
sfs-tester.o: sfs-tester.c lua/lanes/lanes.h lua/lua.h lua/luaconf.h \
 lua/lanes/platform.h lua/lauxlib.h lua/lua.h lua/lualib.h sfs-api.h
