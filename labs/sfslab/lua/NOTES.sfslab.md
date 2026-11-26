# Notes on Lua as used by sfslab

The code in this directory is a mostly-vanilla copy of Lua 5.4.
`luaconf.h` has been heavily edited as we do not need the level of
portability desired by upstream, and some of it gets in the way.

## The Lua standard library

Many functions have been removed from the Lua standard library.
The general theme is that we want to restrict access to the actual
filesystem and, as much as possible, remove the ability to load
additional code at runtime.  We also don't want to confuse students
with the coroutine library; we're already confusing them enough
with threads.

Relative to what is documented in the [standard library reference][lstd],
the following changes have been made:

* The `debug`, `math`, `string`, `table` and `utf8` libraries are unmodified.

* The `coroutine` library has been completely removed.

* From the `base` library, the functions `dofile`, `load`, and `loadfile`
  have been removed.

* The `package` library exposes everything it normally does, but its
  `loadlib` function is a stub which will always fail, `searchpath`
  will always claim that the file does not exist, and `require` will
  _only_ load the built-in libraries.  This is the bare minimum
  required for Lanes to work correctly.

* Almost everything has been removed from the `os` library, leaving only
  `getenv` and functions dealing with time (`clock`, `date`, `difftime`,
  and `time`).  Note especially that `exit` is gone, because it's not OK
  to bomb out of the entire tester in the middle of a trace.  Use the
  base library function `error` to indicate catastrophic failure of a test.

* Almost everything has been removed from the `io` library, leaving
  only `stdout`, `open`, `tmpfile`, and `type`.  `open` has been
  modified so that it will only open files in a directory designated
  by the test harness, and only for reading.  If it turns out that we
  do not need to read files of test data, and/or to create scratch
  files, this might get cut down even further.  Note that the API of
  file _objects_ (referred to as the "explicit file handles" style in
  the Lua documentation) remains unrestricted, since it is sufficient
  to control _opening_ files to enforce capability discipline.

[lstd]: https://www.lua.org/manual/5.4/manual.html#6
