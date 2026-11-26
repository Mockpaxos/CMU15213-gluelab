-- Add the debugger workspace after Neovim has loaded the user's config.
local directory = vim.fn.fnamemodify(vim.env.NDB_INIT, ":h")
local assembly_mode = vim.env.NDB_ASSEMBLY == "1"
local args = {}
for i = 0, tonumber(vim.env.NDB_ARGC or "0") - 1 do
  args[#args + 1] = vim.env["NDB_ARG_" .. i] or ""
  vim.env["NDB_ARG_" .. i] = nil
end
vim.env.NDB_ARGC = nil
vim.env.NDB_INIT = nil

if vim.fn.has("nvim-0.12") == 0 then
  vim.api.nvim_err_writeln("ndb requires Neovim 0.12+ with bundled Termdebug")
  vim.cmd("cquit 1")
  return
end

vim.opt.mouse = "a"
vim.opt.scrollback = 50000
vim.opt.autoread = true
vim.opt.modeline = false
local ui = dofile(directory .. "/ui.lua")
ui.setup()

local state_directory = vim.fn.tempname()
vim.fn.mkdir(state_directory, "p", 448) -- private, session-only snapshots (0700)
local state_path = state_directory .. "/state.json"
vim.env.NDB_STATE = state_path
local stop_ui
local function cleanup()
  if stop_ui then
    stop_ui()
    stop_ui = nil
  end
  vim.fn.delete(state_directory, "rf")
end
vim.api.nvim_create_autocmd("VimLeavePre", { callback = cleanup })

-- This is a viewer, not a second editor. Avoid accidental edits and allow
-- automatic reload after a source file is saved in another editor.
vim.api.nvim_create_autocmd("BufReadPost", {
  callback = function(event)
    if vim.bo[event.buf].buftype == "" then
      vim.bo[event.buf].readonly = true
      vim.bo[event.buf].modifiable = false
    end
  end,
})
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter" }, {
  command = "silent! checktime",
})

vim.g.ndb_args = args
vim.g.termdebug_config = {
  command = {
    "gdb",
    -- Keep normal init loading. Set the launch policy before project init can
    -- run an inferior; install snapshots afterwards, before the MI UI connects.
    "-ex", "set confirm off",
    "-iex", "set startup-with-shell off",
    -- A debuginfod consent prompt can block opening a stripped executable
    -- before Termdebug can accept input. Preserve an explicit on/off choice.
    "-iex", [[python
try:
    if gdb.parameter("debuginfod enabled") == "ask":
        gdb.execute("set debuginfod enabled off")
except RuntimeError:
    pass  # GDB built without debuginfod support
]],
    "-ex", "python exec(compile(open(" .. vim.json.encode(directory .. "/inspect.py")
      .. ", encoding='utf-8').read(), 'ndb-inspect', 'exec'))",
  },
  -- Leave native K (keyword help), + and - (line movement) untouched.
  map_K = 0,
  map_plus = 0,
  map_minus = 0,
  wide = 1,
  disasm_window = 1,
  variables_window = 0, -- Compact, read-only variables come from inspect.py.
}

-- Append --args AFTER Termdebug's own GDB options. TermdebugCommand otherwise
-- joins program arguments into a command string, losing argument boundaries.
vim.cmd([[
  function! NdbGdbCommand(command) abort
    " The program helper must release its controlling PTY before .gdbinit can
    " run an inferior. This hook runs after both helpers start, before GDB.
    let started = reltime()
    while !filereadable($NDB_PTY_READY)
      if reltimefloat(reltime(started)) > 5
        throw 'ndb: program terminal helper did not become ready'
      endif
      sleep 10m
    endwhile
    return a:command + (empty(g:ndb_args) ? [] : ['--args'] + g:ndb_args)
  endfunction
  let g:termdebug_config.command_filter = function('NdbGdbCommand')
  packadd termdebug
]])

vim.api.nvim_create_autocmd("User", {
  pattern = "TermdebugStopPre",
  callback = cleanup,
})
vim.api.nvim_create_autocmd("User", {
  pattern = "TermdebugStopPost",
  callback = function()
    -- Let Termdebug finish restoring its windows before closing the viewer.
    vim.schedule(function()
      vim.cmd("qa!")
    end)
  end,
})

-- Defer intermediate redraws until the handshake chatter is concealed.
local lazyredraw = vim.o.lazyredraw
local shell = vim.o.shell
vim.env.NDB_ORIGINAL_SHELL = shell
vim.env.NDB_PTY_READY = state_directory .. "/pty-ready"
-- 'shell' parses double quotes itself, not POSIX shellescape's single quotes.
vim.o.shell = vim.json.encode(directory .. "/pty-shell.py")
vim.o.lazyredraw = true
local ok, started = pcall(function()
  vim.cmd("Termdebug")
  if not vim.g.termdebug_is_running then return false end
  stop_ui = ui.layout(state_path, assembly_mode)
  return true
end)
vim.o.lazyredraw = lazyredraw
vim.o.shell = shell
vim.env.NDB_ORIGINAL_SHELL = nil
vim.env.NDB_PTY_READY = nil
vim.env.NDB_STATE = nil
vim.env.NDB_ASSEMBLY = nil
if not ok or not started then
  cleanup()
  vim.api.nvim_err_writeln("ndb: Termdebug failed to start" .. (ok and "" or ": " .. tostring(started)))
  vim.cmd("cquit 1")
  return
end

-- A tmux-style prefix: wait for one literal key, with no mapping timeout.
-- Exit terminal input before reading the key so it never reaches GDB/the program.
local views = {
  g = { "Gdb", true },
  s = { "Source", false },
  a = { "Asm", false },
  v = { "Var", false },
  p = { "Program", true },
}
if assembly_mode then
  views.s = { "Stack", false }
  views.r = { "Registers", false }
  views.v = nil
end
local prefix_help = assembly_mode
  and "ndb: g GDB | a Asm | r Registers | s Stack | p I/O | b Browse | Esc cancel"
  or "ndb: g GDB | s Source | a Asm | v Vars | p I/O | b Browse | Esc cancel"
vim.api.nvim_create_user_command("NdbPrefix", function(options)
  vim.api.nvim_echo({ {
    prefix_help,
    "Question",
  } }, false, {})
  vim.cmd("redraw")
  local ok, key = pcall(vim.fn.getcharstr)
  vim.api.nvim_echo({ { "", "Normal" } }, false, {})
  if not vim.g.termdebug_is_running then
    return
  end
  local view = ok and views[key] or nil
  if view then
    vim.cmd(view[1])
    if view[2] then
      vim.cmd("normal! G")
      vim.cmd("startinsert")
    end
  elseif not (ok and key == "b") and options.args == "input" then
    -- Escape, Ctrl+C, or an unknown key cancels without changing the input line.
    vim.cmd("startinsert")
  end
end, { nargs = 1 })

-- Legacy terminals send NUL (Ctrl+@); enhanced keyboard protocols can report
-- Ctrl+Space separately. Accept both without stealing other readline controls.
for _, prefix in ipairs({ "<C-Space>", "<C-@>" }) do
  vim.keymap.set("n", prefix, "<Cmd>NdbPrefix browse<CR>", { desc = "Debugger views" })
  vim.keymap.set("t", prefix, [[<C-\><C-n><Cmd>NdbPrefix input<CR>]],
    { desc = "Debugger views" })
end
vim.cmd("Gdb")
vim.cmd("startinsert")
