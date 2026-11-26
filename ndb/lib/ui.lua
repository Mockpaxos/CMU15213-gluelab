-- Presentation only: preserve Termdebug's native windows and debugger transport.
local M = {}
local api = vim.api

local function assembly_syntax(buf)
  api.nvim_buf_call(buf, function()
    vim.cmd([[
      syntax match NdbAsmAddress /^\s*0x[0-9a-fA-F]\+/
      syntax match NdbAsmInstruction /\%(:\s*\)\@<=\h\w*/
      syntax match NdbAsmRegister /%[a-zA-Z][a-zA-Z0-9]*/
    ]])
  end)
end

local function highlights()
  local added = api.nvim_get_hl(0, { name = "DiffAdd", link = false })
  api.nvim_set_hl(0, "debugPC", { bg = added.bg, bold = true })
  api.nvim_set_hl(0, "debugBreakpoint", { link = "DiagnosticError" })
  api.nvim_set_hl(0, "debugBreakpointDisabled", { link = "Comment" })
  api.nvim_set_hl(0, "NdbTitle", { link = "Title" })
  api.nvim_set_hl(0, "NdbVariableName", { bold = true })
  api.nvim_set_hl(0, "NdbVariableLabel", { link = "Comment" })
  api.nvim_set_hl(0, "NdbRegisterChanged", { link = "DiagnosticWarn" })
  api.nvim_set_hl(0, "NdbAsmInstruction", { link = "Statement" })
  api.nvim_set_hl(0, "NdbAsmRegister", { link = "Special" })
  api.nvim_set_hl(0, "NdbAsmAddress", { link = "Comment" })
end

function M.setup()
  vim.opt.equalalways = false
  vim.opt.winminheight = 1
  vim.opt.winminwidth = 1
  vim.opt.showtabline = 0
  vim.opt.laststatus = 2
  vim.opt.fillchars:append({ stl = "─", stlnc = "─", vert = "│", eob = " " })

  -- Use the user's colors and source highlighting; add debugger highlights only.
  api.nvim_create_autocmd("ColorScheme", { callback = highlights })
  highlights()
end

local function capture(command)
  vim.cmd(command)
  return { win = api.nvim_get_current_win(), buf = api.nvim_get_current_buf() }
end

local function decorate(view, title, source)
  local opts = vim.wo[view.win]
  opts.winbar = "%#NdbTitle# " .. title
  opts.statusline = source and " %<%f %= %l:%c " or "%#WinSeparator#"
  opts.number = source or false
  opts.relativenumber = false
  opts.signcolumn = source and "yes" or "no"
  opts.wrap = false
  opts.scrolloff = source and 4 or 0
end

local function panel(below, name, title)
  api.nvim_set_current_win(below.win)
  vim.cmd("belowright split")
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_name(buf, name)
  api.nvim_win_set_buf(0, buf)
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].filetype = "ndbinfo"
  api.nvim_buf_set_lines(buf, 0, -1, false, { "Waiting for GDB..." })
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
  local view = { win = api.nvim_get_current_win(), buf = buf }
  decorate(view, title)
  api.nvim_buf_call(buf, function()
    vim.cmd([[
      syntax match NdbAsmAddress /0x[0-9a-fA-F]\+/
    ]])
  end)
  return view
end

local function replace(view, lines)
  local old = api.nvim_buf_get_lines(view.buf, 0, -1, false)
  if vim.deep_equal(old, lines) then
    return
  end
  local position = api.nvim_win_call(view.win, vim.fn.winsaveview)
  -- Internal writes must unlock both flags: modifiable alone still emits W10.
  vim.bo[view.buf].readonly = false
  vim.bo[view.buf].modifiable = true
  local ok, message = pcall(api.nvim_buf_set_lines, view.buf, 0, -1, false, lines)
  vim.bo[view.buf].modified = false
  vim.bo[view.buf].modifiable = false
  vim.bo[view.buf].readonly = true
  if not ok then error(message) end
  api.nvim_win_call(view.win, function() vim.fn.winrestview(position) end)
end

local variable_namespace = api.nvim_create_namespace("ndb-variables")
local function variables(view, state)
  local lines, marks = {}, {}
  for _, kind in ipairs({ "arg", "loc" }) do
    local line = kind .. " "
    local row = #lines
    for _, entry in ipairs(state.variables) do
      if entry.kind == kind then
        if #line > 4 then line = line .. ", " end
        local start = #line
        line = line .. entry.name .. " = " .. entry.value
        marks[#marks + 1] = { row, start, start + #entry.name, "NdbVariableName" }
      end
    end
    if #line > 4 then
      lines[#lines + 1] = line
      marks[#marks + 1] = { row, 0, 3, "NdbVariableLabel" }
    end
  end
  replace(view, #lines > 0 and lines or { state.variables_note })
  api.nvim_buf_clear_namespace(view.buf, variable_namespace, 0, -1)
  for _, mark in ipairs(marks) do
    api.nvim_buf_set_extmark(view.buf, variable_namespace, mark[1], mark[2], {
      end_col = mark[3], hl_group = mark[4],
    })
  end
end

local register_namespace = api.nvim_create_namespace("ndb-registers")
local function registers(view, state)
  local entries = state.registers
  local cell_width = 1
  for _, entry in ipairs(entries) do
    cell_width = math.max(cell_width, #entry.name + #entry.value + 4)
  end
  local columns = math.max(1, math.min(2, math.floor(api.nvim_win_get_width(view.win) / cell_width)))
  local lines, marks, flags = {}, {}, nil
  for index, entry in ipairs(entries) do
    local column = (index - 1) % columns
    if column == 0 then lines[#lines + 1] = "" end
    local row = #lines
    local start = #lines[row]
    local cell = entry.name .. "  " .. entry.value
    lines[row] = lines[row] .. cell .. string.rep(" ", cell_width - #cell)
    if entry.changed then
      marks[#marks + 1] = { row - 1, start, start + #cell }
    end
    if entry.flags then flags = entry.flags end
  end
  if flags then lines[#lines + 1] = "Flags " .. flags end
  replace(view, #lines > 0 and lines or { state.registers_note })
  api.nvim_buf_clear_namespace(view.buf, register_namespace, 0, -1)
  for _, mark in ipairs(marks) do
    api.nvim_buf_set_extmark(view.buf, register_namespace, mark[1], mark[2], {
      end_col = mark[3], hl_group = "NdbRegisterChanged",
    })
  end
end

function M.layout(state_path, assembly_mode)
  local views = {}
  local last_state
  for key, command in pairs({ g = "Gdb", p = "Program", s = "Source", a = "Asm" }) do
    views[key] = capture(command)
  end
  -- Termdebug must read these lines to validate its handshake. Hide only the
  -- successful protocol chatter after startup, without touching terminal data.
  local startup_ns = api.nvim_create_namespace("ndb-startup")
  local startup_lines = api.nvim_buf_get_lines(views.g.buf, 0, -1, false)
  if vim.tbl_contains(startup_lines, "New UI allocated") then
    for row, line in ipairs(startup_lines) do
      if line == "startupdone" or line == "New UI allocated"
          or line:match("^%(gdb%) server new%-ui mi /dev/pts/%d+$") then
        api.nvim_buf_set_extmark(views.g.buf, startup_ns, row - 1, 0,
          { end_row = row - 1, end_col = #line, conceal_lines = "" })
      end
    end
  end
  vim.wo[views.g.win].conceallevel = 2
  vim.wo[views.g.win].concealcursor = "nvic"

  local assembly = views.a
  vim.bo[assembly.buf].readonly = false
  -- Termdebug writes directly to its assembly buffer without unlocking it.
  -- Keep its renderer in a hidden window and show a read-only mirror instead:
  -- user edits cannot corrupt the listing, and native refreshes keep working.
  api.nvim_win_set_config(assembly.win, {
    relative = "editor", row = 0, col = 0, width = 1, height = 1,
    hide = true, focusable = false, style = "minimal",
  })
  -- Keep the program PTY alive but share its display with the console. Empty
  -- program output no longer occupies a permanent half-screen window.
  vim.bo[views.p.buf].bufhidden = "hide"
  api.nvim_win_close(views.p.win, true)
  views.p.win = views.g.win

  -- Keep native source/assembly window IDs alive even when not displayed:
  -- Termdebug can continue updating them without opening unexpected splits.
  local main, detail
  if assembly_mode then
    api.nvim_win_set_config(views.s.win, {
      relative = "editor", row = 0, col = 0, width = 1, height = 1,
      hide = true, focusable = false, style = "minimal",
    })
    views.a = panel(views.g, "Ndb-assembly", "Assembly")
    api.nvim_set_current_win(views.a.win)
    vim.cmd("wincmd L")
    views.stack = panel(views.a, "Ndb-stack", "Stack — following $sp")
    views.r = panel(views.g, "Ndb-registers", "Registers")
    main, detail = views.a, views.r
    vim.wo[views.a.win].signcolumn = "yes"
    vim.wo[views.a.win].scrolloff = 4
  else
    api.nvim_set_current_win(views.s.win)
    vim.cmd("wincmd L")
    views.a = panel(views.s, "Ndb-assembly", "Assembly")
    api.nvim_set_current_win(views.g.win)
    vim.cmd("wincmd H")
    views.v = panel(views.g, "Ndb-variables", "Variables")
    decorate(views.s, "Source", true)
    vim.wo[views.v.win].wrap = true
    vim.wo[views.v.win].linebreak = true
    vim.wo[views.v.win].showbreak = "    "
    main, detail = views.s, views.v
  end
  views.breakpoints = panel(detail, "Ndb-breakpoints", "Breakpoints")
  decorate(views.g, "GDB  [Ctrl+Space g]  /  Program I/O  [Ctrl+Space p]")
  -- Preserve assembly mode's sign column and scrolling margin.
  if not assembly_mode then decorate(views.a, "Assembly") end
  for _, view in pairs(views) do
    vim.bo[view.buf].readonly = true
    vim.bo[view.buf].modifiable = false
  end
  vim.bo[views.a.buf].filetype = "asm"
  assembly_syntax(views.a.buf)
  highlights()

  local alive = true
  local function resize()
    if not alive or not api.nvim_win_is_valid(views.g.win) then
      return
    end
    local total = vim.o.lines - vim.o.cmdheight
    -- Each window uses a heading and a separator/status row. Keep the main
    -- horizontal boundary at 60%, with room for the two lower-left sections.
    -- nvim_win_set_height INCLUDES winbar but excludes the status/separator.
    local top = math.max(2, math.min(math.floor(total * 0.6) - 1, total - 7))
    local lower = math.max(2, total - top - 5)
    local details = math.max(1, math.floor(lower * (assembly_mode and 0.8 or 0.6)))
    api.nvim_win_set_width(views.g.win, math.max(1, math.floor((vim.o.columns - 1) * 0.5)))
    -- Size top-to-bottom: enlarging an earlier window takes space from its
    -- neighbors, so reversing this order can collapse the details pane.
    api.nvim_win_set_height(views.g.win, top)
    api.nvim_win_set_height(main.win, top)
    api.nvim_win_set_height(detail.win, details + 1)
    api.nvim_win_set_height(views.breakpoints.win, math.max(1, lower - details) + 1)
    if assembly_mode and last_state then registers(views.r, last_state) end
  end
  resize()
  api.nvim_create_autocmd("VimResized", { callback = function() vim.schedule(resize) end })

  -- Keep the public commands useful too, including when the console currently
  -- displays the program PTY. In default mode Source stays native.
  local function console(key)
    api.nvim_set_current_win(views.g.win)
    api.nvim_win_set_buf(views.g.win, views[key].buf)
    decorate(views.g, key == "g" and "GDB  [Ctrl+Space p: program I/O]"
      or "Program I/O  [Ctrl+Space g: GDB]")
  end
  api.nvim_create_user_command("Gdb", function() console("g") end, { force = true })
  api.nvim_create_user_command("Program", function() console("p") end, { force = true })
  api.nvim_create_user_command("Asm", function() api.nvim_set_current_win(views.a.win) end,
    { force = true })
  if assembly_mode then
    api.nvim_create_user_command("Registers", function() api.nvim_set_current_win(views.r.win) end, {})
    api.nvim_create_user_command("Stack", function() api.nvim_set_current_win(views.stack.win) end, {})
    -- Do not focus the hidden native source renderer or create a variables split.
    api.nvim_create_user_command("Source", function()
      vim.notify("ndb: source is hidden in assembly mode; use :Asm")
    end, { force = true })
    api.nvim_create_user_command("Var", function()
      vim.notify("ndb: variables are hidden in assembly mode; use :Registers")
    end, { force = true })
  else
    api.nvim_create_user_command("Var", function() api.nvim_set_current_win(views.v.win) end,
      { force = true })
  end
  api.nvim_create_user_command("Breakpoints", function()
    api.nvim_set_current_win(views.breakpoints.win)
  end, {})

  local assembly_namespace = api.nvim_create_namespace("ndb-assembly-pc")
  local breakpoint_namespace = api.nvim_create_namespace("ndb-assembly-breakpoints")
  local function sync_breakpoints()
    if not assembly_mode or not last_state then return end
    -- Compare canonical hex strings: Lua numbers cannot represent all 64-bit addresses.
    local function address(text)
      return text:lower():gsub("^0x0*", "")
    end
    local locations = {}
    for _, bp in ipairs(last_state.breakpoint_locations) do
      local key = address(bp.address)
      locations[key] = locations[key] or bp.enabled
    end
    api.nvim_buf_clear_namespace(views.a.buf, breakpoint_namespace, 0, -1)
    for row, line in ipairs(api.nvim_buf_get_lines(views.a.buf, 0, -1, false)) do
      local addr = line:match("^%s*(0x%x+)")
      local enabled = addr and locations[address(addr)]
      if enabled ~= nil then
        api.nvim_buf_set_extmark(views.a.buf, breakpoint_namespace, row - 1, 0, {
          sign_text = enabled and "●" or "○",
          sign_hl_group = enabled and "debugBreakpoint" or "debugBreakpointDisabled",
          priority = 120,
        })
      end
    end
  end
  local last_tick, last_pc
  local function sync_assembly()
    local tick = api.nvim_buf_get_changedtick(assembly.buf)
    local pc
    for _, sign in ipairs(vim.fn.sign_getplaced(assembly.buf, { group = "TermDebug" })[1].signs) do
      if sign.name == "debugPC" then pc = sign.lnum end
    end
    if tick ~= last_tick or pc ~= last_pc then
      replace(views.a, api.nvim_buf_get_lines(assembly.buf, 0, -1, false))
      api.nvim_buf_clear_namespace(views.a.buf, assembly_namespace, 0, -1)
      if pc and pc <= api.nvim_buf_line_count(views.a.buf) then
        api.nvim_buf_set_extmark(views.a.buf, assembly_namespace, pc - 1, 0,
          { line_hl_group = "debugPC", priority = 110 })
        api.nvim_win_set_cursor(views.a.win, { pc, 0 })
      end
      sync_breakpoints()
      last_tick, last_pc = tick, pc
    end
  end

  -- A project's .gdbinit may run and stop before the MI UI is connected.
  -- Ask GDB to reselect the SAME frame after our windows exist: "up 0" emits
  -- the thread/frame notification Termdebug needs, without stepping or running.
  local initial_ok, initial = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(state_path), "\n"))
  end)
  if initial_ok and initial.stopped then
    vim.cmd("0Up")
  end

  local timer = vim.uv.new_timer()
  local last_stamp
  timer:start(0, 100, vim.schedule_wrap(function()
    if not alive then return end
    sync_assembly()
    local stat = vim.uv.fs_stat(state_path)
    if not stat then return end
    local stamp = stat.mtime.sec .. ":" .. stat.mtime.nsec .. ":" .. stat.size
    if stamp == last_stamp then return end
    local ok, state = pcall(function()
      return vim.json.decode(table.concat(vim.fn.readfile(state_path), "\n"))
    end)
    if ok then
      last_state = state
      if assembly_mode then
        registers(views.r, state)
        replace(views.stack, state.stack)
        -- Titles contain debugger data; escape statusline percent sequences.
        decorate(views.stack, (state.stack_title:gsub("%%", "%%%%")))
        sync_breakpoints()
      else
        variables(views.v, state)
      end
      replace(views.breakpoints, state.breakpoints)
      last_stamp = stamp
    end
  end))
  return function()
    alive = false
    timer:stop()
    timer:close()
  end
end

return M
