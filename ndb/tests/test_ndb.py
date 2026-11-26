"""Real Neovim/GDB integration tests, isolated from the user's tmux and config.

Run: python3 -B -m unittest discover -s tests -p 'test_ndb.py' -v
"""
import json
import os
import platform
import re
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LauncherTest(unittest.TestCase):
    def test_options_stop_at_executable_or_separator(self):
        with tempfile.TemporaryDirectory(prefix='ndb-argv-') as directory:
            bin_dir = Path(directory)
            nvim = bin_dir / 'nvim'
            nvim.write_text('#!' + sys.executable + '\n'
                            'import json, os\n'
                            'print(json.dumps([os.environ["NDB_ASSEMBLY"], '
                            '[os.environ["NDB_ARG_" + str(i)] '
                            'for i in range(int(os.environ["NDB_ARGC"]))]]))\n')
            nvim.chmod(0o755)
            for name in ('gdb', 'python3'):
                (bin_dir / name).symlink_to(sys.executable)
            env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ['PATH'])
            for args, mode, target in [
                ([], '0', []),
                (['-a'], '1', []),
                (['--assembly', 'prog', 'two words', '', '-a', '--assembly'],
                 '1', ['prog', 'two words', '', '-a', '--assembly']),
                (['prog', '-a', '--help'], '0', ['prog', '-a', '--help']),
                (['--', '-a'], '0', ['-a']),
                (['-a', '--', '--help'], '1', ['--help']),
            ]:
                with self.subTest(args=args):
                    output = subprocess.check_output([str(ROOT / 'ndb'), *args], env=env, text=True)
                    self.assertEqual(json.loads(output), [mode, target])
            for args in (['--help'], ['-a', '-h'], ['--assembly', '--help']):
                output = subprocess.check_output([str(ROOT / 'ndb'), *args], env=env, text=True)
                self.assertIn('Source mode (default):', output)
                self.assertIn('Assembly mode (-a or --assembly):', output)
                self.assertIn('source debug.gdb', output)


@unittest.skipUnless(all(shutil.which(c) for c in ('nvim', 'gdb', 'gcc', 'tmux')),
                     'requires Neovim 0.12+, GDB, gcc, and tmux')
class NdbTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='ndb-test-')
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.socket = str(self.work / 'tmux.sock')
        self.rpc = str(self.work / 'nvim.sock')
        self.nvim = shutil.which('nvim')
        home = self.work / 'home'
        self.home = home
        home.mkdir()
        (home / '.gdbinit').write_text(
            f'add-auto-load-safe-path {self.work / ".gdbinit"}\n'
            'echo HOME_INIT_LOADED\\n\n')
        (self.work / '.gdbinit').write_text('echo PROJECT_INIT_LOADED\\n\n')
        bin_dir = self.work / 'bin'
        bin_dir.mkdir()
        wrapper = bin_dir / 'nvim'
        wrapper.write_text('#!/bin/sh\nexec ' + shlex.quote(self.nvim)
                           + ' --listen ' + shlex.quote(self.rpc) + ' "$@"\n')
        wrapper.chmod(0o755)
        self.env = dict(os.environ, HOME=str(home),
                        XDG_CONFIG_HOME=str(home / '.config'),
                        XDG_DATA_HOME=str(home / '.local/share'),
                        XDG_STATE_HOME=str(home / '.local/state'), DEBUGINFOD_URLS='',
                        XDG_CACHE_HOME=str(home / '.cache'), TERM='xterm-256color',
                        PATH=str(bin_dir) + os.pathsep + os.environ['PATH'],
                        PS1='SHELL_READY> ')
        self.env.pop('TMUX', None)
        self.env.pop('TMUX_PANE', None)
        self.source = self.work / 'main.c'
        self.source.write_text(
            '#include <stdio.h>\n'
            'int helper(int value) {\n'
            '    volatile int unique_local = value + 1;\n'
            '    return unique_local;\n'
            '}\n'
            'int main(int argc, char **argv) {\n'
            '    for (int i = 0; i < argc; ++i) printf("ARG[%d]=<%s>\\n", i, argv[i]);\n'
            '    return helper(argc);\n'
            '}\n')
        self.program = self.work / 'program with spaces'
        subprocess.run(['gcc', '-g', '-O0', '-o', str(self.program), str(self.source)],
                       check=True, capture_output=True)
        self.launcher = self.work / 'launcher with spaces'
        self.launcher.symlink_to(ROOT / 'ndb')
        self.pane = self.tmux('new-session', '-d', '-s', 'test', '-x', '180', '-y', '55',
                              '-c', str(self.work), '-P', '-F', '#{pane_id}',
                              'bash', '--noprofile', '--norc', '-i').strip()
        self.addCleanup(lambda: subprocess.run(
            ['tmux', '-S', self.socket, 'kill-server'], capture_output=True))
        self.wait(lambda: 'SHELL_READY>' in self.capture())

    def tmux(self, *args):
        return subprocess.check_output(['tmux', '-S', self.socket, '-f', '/dev/null',
                                        *args], env=self.env, text=True,
                                       stderr=subprocess.STDOUT)

    def capture(self):
        return self.tmux('capture-pane', '-p', '-t', self.pane, '-S', '-')

    def send(self, command):
        self.tmux('send-keys', '-t', self.pane, '-l', command)
        self.tmux('send-keys', '-t', self.pane, 'Enter')

    def wait(self, predicate):
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(.05)
        self.fail('Timed out; console:\n' + self.capture())

    def evaluate(self, expression):
        result = subprocess.run([self.nvim, '--server', self.rpc, '--remote-expr',
                                 'json_encode(' + expression + ')'], text=True,
                                capture_output=True, timeout=5)
        if result.returncode:
            self.fail(result.stderr)
        return json.loads(result.stdout)

    def buffers(self):
        return self.evaluate('getbufinfo()')

    def lines(self, number):
        return '\n'.join(self.evaluate(f'getbufline({number}, 1, "$")'))

    def start(self, *args, program=True, assembly=None):
        command = [str(self.launcher)]
        if assembly:
            command.append(assembly)
        if program:
            command.append(str(self.program))
        command.extend(args)
        self.send(shlex.join(command))
        self.wait(lambda: Path(self.rpc).exists() and '(gdb)' in self.capture())
        self.wait(lambda: self.evaluate('get(g:, "termdebug_is_running", 0)'))
        self.wait(lambda: self.evaluate('mode()') == 't')
        self.gdb = next(b['bufnr'] for b in self.buffers()
                        if self.evaluate(f'getbufvar({b["bufnr"]}, "&filetype")')
                        == 'termdebug')

    def prefix(self, key):
        self.tmux('send-keys', '-t', self.pane, 'C-Space', key)

    def quit(self):
        self.send('quit')
        self.wait(lambda: not Path(self.rpc).exists())
        self.wait(lambda: 'SHELL_READY>' in self.capture())

    def test_views_commands_and_gdbinit(self):
        self.start()
        output = self.lines(self.gdb)
        self.assertIn('HOME_INIT_LOADED', output)
        self.assertIn('PROJECT_INIT_LOADED', output)
        self.assertEqual(self.evaluate('&scrollback'), 50000)
        (self.work / 'debug.gdb').write_text('break helper\nrun\n')
        self.send('source debug.gdb')
        self.wait(lambda: 'Breakpoint 1, helper' in self.lines(self.gdb))
        self.wait(lambda: any(b['name'] == str(self.source) for b in self.buffers()))
        source_buf = next(b['bufnr'] for b in self.buffers()
                          if b['name'] == str(self.source))
        self.assertEqual(self.evaluate(f'getbufvar({source_buf}, "&modifiable")'), 0)
        self.assertEqual(self.evaluate(f'getbufvar({source_buf}, "&readonly")'), 1)
        self.send('next')
        self.wait(lambda: any('unique_local' in self.lines(b['bufnr'])
                             for b in self.buffers() if 'variables' in b['name'].lower()))
        self.assertTrue(any('Termdebug-asm-listing' in b['name'] for b in self.buffers()))
        self.send('up')
        self.wait(lambda: '#1' in self.lines(self.gdb) and 'main (' in self.lines(self.gdb))
        self.wait(lambda: any(
            sign['name'] == 'debugPC' and sign['lnum'] == 8
            for placement in self.evaluate(
                f'sign_getplaced({source_buf}, {{"group": "TermDebug"}})')
            for sign in placement['signs']))
        self.quit()

    def test_project_init_autorun_watchpoint_populates_views(self):
        self.source.write_text(self.source.read_text().replace(
            'int helper(int value) {',
            'volatile int heap_checker = 1;\n'
            'int helper(int value) {\n    heap_checker = 0;'))
        subprocess.run(['gcc', '-g', '-O0', '-o', str(self.program), str(self.source)],
                       check=True, capture_output=True)
        (self.work / '.gdbinit').write_text('watch heap_checker\nrun init_argument\n')
        self.start()
        self.wait(lambda: 'New value = 0' in self.lines(self.gdb))
        self.wait(lambda: any(b['name'] == str(self.source) for b in self.buffers()))
        source = self.named_buffer('main.c')
        self.wait(lambda: '<+0>:' in self.lines(self.named_buffer('Ndb-assembly')))
        self.assertTrue(any(sign['name'] == 'debugPC'
                            for placement in self.evaluate(
                                f'sign_getplaced({source}, {{"group": "TermDebug"}})')
                            for sign in placement['signs']))
        self.assertIn('hits 1', self.lines(self.named_buffer('Ndb-breakpoints')))
        self.assertEqual(self.evaluate(f'getbufvar({source}, "&modifiable")'), 0)
        self.send('print value')
        self.wait(lambda: '$1 = 2' in self.lines(self.gdb))
        self.quit()

    def test_project_init_selected_frame_is_preserved(self):
        (self.work / '.gdbinit').write_text('break helper\nrun\nup\n')
        self.start()
        self.wait(lambda: any(b['name'] == str(self.source) for b in self.buffers()))
        self.wait(lambda: 'function main:' in self.lines(self.named_buffer('Ndb-assembly')))
        self.send('print argc')
        self.wait(lambda: '$1 = 1' in self.lines(self.gdb))
        self.quit()

    def test_prefix_view_navigation(self):
        self.start()
        self.send('break main')
        self.send('run')
        self.wait(lambda: 'Breakpoint 1, main' in self.lines(self.gdb))
        for key, name in [('s', str(self.source)),
                          ('a', 'Ndb-assembly'),
                          ('v', 'Ndb-variables')]:
            self.prefix(key)
            self.wait(lambda: self.evaluate('mode()') == 'n'
                      and self.evaluate('bufname()').endswith(name))
        # Program I/O is a real terminal: typing goes to the inferior, not GDB.
        self.prefix('p')
        self.wait(lambda: self.evaluate('mode()') == 't'
                  and self.evaluate('bufnr()') != self.gdb)
        self.prefix('g')
        self.wait(lambda: self.evaluate('mode()') == 't'
                  and self.evaluate('bufnr()') == self.gdb)
        self.send('print 12345')
        self.wait(lambda: '$1 = 12345' in self.lines(self.gdb))
        self.quit()

    def test_prefix_browse_search_and_resume(self):
        self.start()
        self.send('python [print("SCROLL_%d" % i) for i in range(150)]')
        self.wait(lambda: 'SCROLL_149' in self.lines(self.gdb))
        self.prefix('b')
        self.wait(lambda: self.evaluate('mode()') == 'n')
        self.assertEqual(self.evaluate('bufnr()'), self.gdb)
        self.tmux('send-keys', '-t', self.pane, '-l', 'gg')
        self.wait(lambda: self.evaluate('line(".")') == 1)
        self.send('/SCROLL_42')
        self.wait(lambda: self.evaluate('getline(".")') == 'SCROLL_42')
        self.prefix('g')
        self.wait(lambda: self.evaluate('mode()') == 't'
                  and self.evaluate('line(".")') > 100)
        self.send('print 54321')
        self.wait(lambda: '$1 = 54321' in self.lines(self.gdb))
        self.quit()

    def test_prefix_waits_and_cancel_preserves_input(self):
        self.start()
        self.tmux('send-keys', '-t', self.pane, '-l', 'print 12')
        self.tmux('send-keys', '-t', self.pane, 'C-Space')
        self.wait(lambda: 'Esc cancel' in self.capture())
        # Longer than Neovim's default mapping timeout: the prefix stays armed.
        time.sleep(1.2)
        self.assertIn('Esc cancel', self.capture())
        self.tmux('send-keys', '-t', self.pane, 'Escape')
        self.wait(lambda: self.evaluate('mode()') == 't')
        self.prefix('x')  # Unknown keys must not leak into the GDB command line.
        self.wait(lambda: self.evaluate('mode()') == 't')
        self.send('345')
        self.wait(lambda: '$1 = 12345' in self.lines(self.gdb))
        self.tmux('send-keys', '-t', self.pane, 'C-Space')
        self.wait(lambda: 'Esc cancel' in self.capture())
        time.sleep(1.2)
        self.tmux('send-keys', '-t', self.pane, 'b')
        self.wait(lambda: self.evaluate('mode()') == 'n')
        self.prefix('Escape')
        self.wait(lambda: 'Esc cancel' not in self.capture())
        self.wait(lambda: self.evaluate('mode()') == 'n')
        self.assertEqual(self.evaluate('bufnr()'), self.gdb)
        self.prefix('g')
        self.wait(lambda: self.evaluate('mode()') == 't')
        self.quit()

    def named_buffer(self, name):
        return next(b['bufnr'] for b in self.buffers() if b['name'].endswith(name))

    def syntax_at(self, buf, line, col):
        return self.evaluate(
            'luaeval(\'vim.api.nvim_buf_call(_A[1], function() return '
            'vim.fn.synIDattr(vim.fn.synID(_A[2], _A[3], 1), "name") end)\', '
            + json.dumps([buf, line, col]) + ')')

    def assert_layout(self, assembly=False):
        windows = [w for w in self.evaluate('getwininfo()')
                   if not self.evaluate(f'nvim_win_get_config({w["winid"]}).relative')]
        self.assertEqual(len(windows), 5)
        self.assertEqual(any(b['name'].endswith('Ndb-stack') for b in self.buffers()), assembly)
        self.assertEqual(bool(self.evaluate('exists(":Stack")')), assembly)
        left = sorted([w for w in windows if w['wincol'] == 1], key=lambda w: w['winrow'])
        right = sorted([w for w in windows if w['wincol'] != 1], key=lambda w: w['winrow'])
        self.assertEqual(len(left), 3)
        self.assertEqual(len(right), 2)
        columns, lines, cmdheight = self.evaluate('[&columns, &lines, &cmdheight]')
        self.assertAlmostEqual(left[0]['width'], (columns - 1) * .5, delta=1)
        self.assertEqual(left[0]['winrow'], 1)
        self.assertEqual(right[0]['winrow'], 1)
        self.assertEqual(left[1]['winrow'], right[1]['winrow'])
        self.assertAlmostEqual(left[1]['winrow'] - 1, (lines - cmdheight) * .6, delta=1)
        for w in left[1:]:
            self.assertGreaterEqual(w['height'], 3)
        for w in windows:
            status = self.evaluate(f'getwinvar({w["winid"]}, "&statusline")')
            self.assertEqual('%f' in status, not assembly and w['winid'] == right[0]['winid'])
        return left, right

    def test_layout_resize_and_shared_console(self):
        self.start()
        left, _ = self.assert_layout()
        console = left[0]['winid']
        self.prefix('p')
        self.wait(lambda: self.evaluate('mode()') == 't'
                  and self.evaluate('bufnr()') != self.gdb)
        self.assertEqual(self.evaluate('win_getid()'), console)
        self.assert_layout()
        self.prefix('g')
        self.wait(lambda: self.evaluate('bufnr()') == self.gdb)
        for width, height in [(140, 42), (220, 68)]:
            self.tmux('resize-window', '-t', 'test:0', '-x', str(width), '-y', str(height))
            self.wait(lambda: self.evaluate('[&columns, &lines]') == [width, height])
            # Wait for the scheduled VimResized layout adjustment.
            self.wait(lambda: self.evaluate(f'winwidth({console})') == int((width - 1) * .5))
            self.assert_layout()
        self.quit()

    def test_assembly_layout_registers_stack_and_frames(self):
        self.start(assembly='-a')
        regs = self.named_buffer('Ndb-registers')
        stack = self.named_buffer('Ndb-stack')
        asm = self.named_buffer('Ndb-assembly')
        bp = self.named_buffer('Ndb-breakpoints')
        self.assert_layout(assembly=True)
        self.assertFalse(any(b['name'].endswith('Ndb-variables') for b in self.buffers()))
        self.wait(lambda: 'Program not running.' in self.lines(stack))
        self.send('break helper')
        self.send('run')
        self.wait(lambda: 'Breakpoint 1, helper' in self.lines(self.gdb))
        self.wait(lambda: '+0x00' in self.lines(stack))
        self.wait(lambda: '<+0>:' in self.lines(asm))
        self.wait(lambda: '[1] break 0x' in self.lines(bp))
        # GDB may list optional registers (e.g. x86 pl3_ssp) without a value.
        # Require live register data, not that every target register is readable.
        register_text = self.lines(regs)
        self.assertRegex(register_text, r'\b\w+\s+0x[0-9a-fA-F]+\b')
        if platform.machine() == 'x86_64':  # The fixture is compiled for the host.
            for reg in ('rip', 'rsp'):
                self.assertRegex(register_text, rf'\b{reg}\s+0x[0-9a-fA-F]+\b')
        self.assertNotIn('Program not running', register_text)
        self.assert_layout(assembly=True)  # Source updates must stay hidden.
        initial_stack = self.lines(stack)
        self.send('up')
        self.wait(lambda: self.lines(stack) != initial_stack)
        self.send('down')
        self.wait(lambda: self.lines(stack) == initial_stack)
        for key, name in [('a', 'Ndb-assembly'), ('r', 'Ndb-registers'), ('s', 'Ndb-stack')]:
            self.prefix(key)
            self.wait(lambda: self.evaluate('mode()') == 'n'
                      and self.evaluate('bufname()').endswith(name))
        for command in (':Source', ':Var'):
            self.send(command)
            self.assert_layout(assembly=True)
        self.prefix('g')
        self.wait(lambda: self.evaluate('mode()') == 't')
        self.send('si')
        namespace = self.evaluate('nvim_get_namespaces()["ndb-registers"]')
        self.wait(lambda: bool(self.evaluate(
            f'nvim_buf_get_extmarks({regs}, {namespace}, 0, -1, {{}})')))
        for win in self.evaluate('getwininfo()'):
            if self.evaluate(f'nvim_win_get_config({win["winid"]}).relative'):
                continue
            buf = win['bufnr']
            self.assertEqual(self.evaluate(f'getbufvar({buf}, "&readonly")'), 1)
            self.assertEqual(self.evaluate(f'getbufvar({buf}, "&modifiable")'), 0)
        for width, height in [(140, 42), (220, 68)]:
            self.tmux('resize-window', '-t', 'test:0', '-x', str(width), '-y', str(height))
            self.wait(lambda: self.evaluate('[&columns, &lines]') == [width, height])
            time.sleep(.15)
            self.assert_layout(assembly=True)
        self.assertNotIn('W10:', self.evaluate('execute("messages")'))
        self.assertNotIn('Traceback', self.lines(self.gdb))
        self.quit()

    def test_assembly_stripped_executable_and_breakpoint_markers(self):
        # Exercise GDB's default debuginfod consent policy without network access.
        self.send('export DEBUGINFOD_URLS=http://127.0.0.1:9')
        subprocess.run(['gcc', '-s', '-no-pie', '-O0', '-o', str(self.program), str(self.source)],
                       check=True, capture_output=True)
        info = subprocess.check_output(['gdb', '-nx', '-q', '-batch', str(self.program),
                                        '-ex', 'info files'], text=True, env=self.env)
        entry = re.search(r'Entry point: (0x[0-9a-fA-F]+)', info).group(1)
        self.source.unlink()
        self.start(assembly='--assembly')
        asm = self.named_buffer('Ndb-assembly')
        self.send('break *' + entry)
        self.send('run')
        self.wait(lambda: 'Breakpoint 1,' in self.lines(self.gdb))
        ns = self.evaluate('nvim_get_namespaces()["ndb-assembly-breakpoints"]')
        marks = lambda: self.evaluate(f'nvim_buf_get_extmarks({asm}, {ns}, 0, -1, {{"details": 1}})')
        self.wait(lambda: bool(marks()))
        self.assertEqual(len(marks()), 1)
        self.assertEqual(marks()[0][3]['sign_hl_group'], 'debugBreakpoint')
        pc_ns = self.evaluate('nvim_get_namespaces()["ndb-assembly-pc"]')
        pcs = lambda: self.evaluate(f'nvim_buf_get_extmarks({asm}, {pc_ns}, 0, -1, {{}})')
        self.wait(lambda: bool(pcs()))
        old_pc = pcs()[0][1]
        self.send('disable 1')
        self.wait(lambda: marks() and marks()[0][3]['sign_hl_group'] == 'debugBreakpointDisabled')
        self.send('si')
        self.wait(lambda: pcs() and pcs()[0][1] != old_pc)
        self.send('delete 1')
        self.wait(lambda: not marks())
        self.assert_layout(assembly=True)
        self.send('continue')
        self.wait(lambda: 'Program not running.' in self.lines(self.named_buffer('Ndb-stack')))
        self.quit()

    def test_assembly_stack_memory_refresh_and_unavailable_address(self):
        self.start(assembly='-a')
        self.send('break helper')
        self.send('run')
        stack = self.named_buffer('Ndb-stack')
        self.wait(lambda: '+0x00' in self.lines(stack))
        self.send('set $saved_sp = $sp')
        self.send('set $saved_word = *(void **)$sp')
        self.send('set *(void **)$sp = (void *)0x1234')
        self.wait(lambda: '0x0000000000001234' in self.lines(stack)
                  or '0x00001234' in self.lines(stack))
        self.send('set *(void **)$sp = $saved_word')
        self.send('set $sp = 1')
        self.wait(lambda: '<unavailable>' in self.lines(stack))
        self.send('set $sp = $saved_sp')
        self.wait(lambda: '+0x00' in self.lines(stack) and '<unavailable>' not in self.lines(stack))
        self.assertNotIn('Traceback', self.lines(self.gdb))
        self.quit()

    def test_assembly_running_and_interrupt_state(self):
        self.source.write_text('#include <unistd.h>\nint main(void) { for (;;) pause(); }\n')
        subprocess.run(['gcc', '-g', '-O0', '-o', str(self.program), str(self.source)],
                       check=True, capture_output=True)
        self.start(assembly='-a')
        self.send('break main')
        self.send('run')
        stack = self.named_buffer('Ndb-stack')
        regs = self.named_buffer('Ndb-registers')
        self.wait(lambda: '+0x00' in self.lines(stack))
        self.send('continue')
        self.wait(lambda: 'Running...' in self.lines(stack) and 'Running...' in self.lines(regs))
        self.prefix('p')
        self.wait(lambda: self.evaluate('mode()') == 't' and self.evaluate('bufnr()') != self.gdb)
        self.tmux('send-keys', '-t', self.pane, 'C-c')
        self.wait(lambda: 'received signal SIGINT' in self.lines(self.gdb))
        self.wait(lambda: '+0x00' in self.lines(stack) and 'Running...' not in self.lines(regs))
        self.prefix('g')
        self.wait(lambda: self.evaluate('mode()') == 't')
        self.quit()

    def test_assembly_project_init_selected_frame(self):
        (self.work / '.gdbinit').write_text('break helper\nrun\nup\n')
        self.start(assembly='--assembly')
        self.wait(lambda: 'function main:' in self.lines(self.named_buffer('Ndb-assembly')))
        self.wait(lambda: '+0x00' in self.lines(self.named_buffer('Ndb-stack')))
        self.assert_layout(assembly=True)
        self.send('print argc')
        self.wait(lambda: '$1 = 1' in self.lines(self.gdb))
        self.quit()

    def test_breakpoints_refresh(self):
        self.start()
        bp = self.named_buffer('Ndb-breakpoints')
        self.wait(lambda: 'No breakpoints.' in self.lines(bp))
        self.send('break helper')
        self.wait(lambda: '[1] break helper' in self.lines(bp))
        self.send('condition 1 value == 1')
        self.wait(lambda: 'if value == 1' in self.lines(bp))
        self.send('disable 1')
        self.wait(lambda: 'disabled' in self.lines(bp))
        self.send('enable 1')
        self.wait(lambda: 'enabled' in self.lines(bp))
        self.send('run')
        self.wait(lambda: 'hits 1' in self.lines(bp))
        self.send('bt')
        self.wait(lambda: '#0' in self.lines(self.gdb) and '#1' in self.lines(self.gdb))
        self.send('watch unique_local')
        self.wait(lambda: '[2] watch unique_local' in self.lines(bp))
        self.send('delete 1 2')
        self.wait(lambda: 'No breakpoints.' in self.lines(bp))
        self.send('set breakpoint pending on')
        self.send('break function_not_loaded_yet')
        self.wait(lambda: 'pending' in self.lines(bp))
        self.send('delete 3')
        self.wait(lambda: 'No breakpoints.' in self.lines(bp))
        self.quit()

    def test_source_and_assembly_highlighting(self):
        self.start()
        self.send('break helper')
        self.send('run')
        self.wait(lambda: 'Breakpoint 1, helper' in self.lines(self.gdb))
        source = self.named_buffer('main.c')
        asm = self.named_buffer('Ndb-assembly')
        self.assertEqual(self.evaluate(f'getbufvar({source}, "&filetype")'), 'c')
        if self.evaluate(f'luaeval("vim.treesitter.highlighter.active[{source}] ~= nil")'):
            captures = self.evaluate(
                f'luaeval("vim.treesitter.get_captures_at_pos({source}, 1, 0)")')
            self.assertTrue(any('type' in item['capture'] for item in captures))
        else:
            self.assertEqual(self.syntax_at(source, 2, 1), 'cType')
        for command in [None, 'next']:
            if command:
                self.send(command)
                self.wait(lambda: 'return unique_local' in self.lines(self.gdb))
            self.wait(lambda: '<+0>:' in self.lines(asm))
            instruction = next((i, line) for i, line in enumerate(self.lines(asm).splitlines(), 1)
                               if '<+0>:' in line)
            row, line = instruction
            col = line.index(':') + 2
            while line[col - 1].isspace():
                col += 1
            self.assertEqual(self.syntax_at(asm, row, col), 'NdbAsmInstruction')
        self.quit()

    def test_all_visible_panes_stay_read_only_across_refreshes(self):
        self.start()
        self.send('break helper')
        self.send('run')
        self.wait(lambda: 'Breakpoint 1, helper' in self.lines(self.gdb))
        asm = self.named_buffer('Ndb-assembly')
        self.wait(lambda: '<+0>:' in self.lines(asm))
        namespace = self.evaluate('nvim_get_namespaces()["ndb-assembly-pc"]')
        marks = lambda: self.evaluate(f'nvim_buf_get_extmarks({asm}, {namespace}, 0, -1, {{}})')
        self.wait(lambda: bool(marks()))
        old_pc = marks()[0][1]
        for refresh in range(2):
            for win in self.evaluate('getwininfo()'):
                if self.evaluate(f'nvim_win_get_config({win["winid"]}).relative'):
                    continue  # Termdebug's hidden assembly renderer is internal.
                buf = win['bufnr']
                self.assertEqual(self.evaluate(f'getbufvar({buf}, "&readonly")'), 1)
                self.assertEqual(self.evaluate(f'getbufvar({buf}, "&modifiable")'), 0)
                # Editing fails, but the same pane must still refresh from GDB.
                editable = self.evaluate(
                    'luaeval(\'select(1, pcall(vim.api.nvim_buf_set_lines, '
                    '_A, 0, 0, false, {"UNWANTED_EDIT"}))\', ' + str(buf) + ')')
                self.assertFalse(editable)
                self.assertNotIn('UNWANTED_EDIT', self.lines(buf))
            if refresh == 0:
                self.send('next')
                self.wait(lambda: marks() and marks()[0][1] != old_pc)
                self.wait(lambda: 'unique_local = 2' in self.lines(self.named_buffer('Ndb-variables')))
        self.assertNotIn('E21:', self.lines(self.gdb))
        messages = self.evaluate('execute("messages")')
        self.assertNotIn('W10:', messages)
        self.assertNotIn('Warning: Changing a readonly file', messages)
        renderer = self.named_buffer('Termdebug-asm-listing')
        self.assertEqual(self.evaluate(f'getbufvar({renderer}, "&readonly")'), 0)
        self.quit()

    def test_dashboard_style_variables_and_frame_changes(self):
        self.source.write_text(
            'struct Block { int header; char payload[8]; };\n'
            'int inspect(int size, struct Block *block) {\n'
            '    int asize = size + 1;\n'
            '    struct Block *copy = block;\n'
            '    volatile int marker = asize;\n'
            '    return marker;\n'
            '}\n'
            'int main(void) {\n'
            '    struct Block storage = {7, "hello"};\n'
            '    return inspect(12, &storage);\n'
            '}\n')
        subprocess.run(['gcc', '-g', '-O0', '-o', str(self.program), str(self.source)],
                       check=True, capture_output=True)
        self.start()
        variables = self.named_buffer('Ndb-variables')
        self.send('break main.c:6')
        self.send('run')
        self.wait(lambda: 'arg size = 12' in self.lines(variables))
        text = self.lines(variables)
        self.assertIn('block = 0x', text)
        self.assertIn(': {header = 7, payload = "hello', text)
        self.assertIn('loc asize = 13, copy = 0x', text)
        self.assertIn('marker = 13', text)
        self.assertEqual(len(text.splitlines()), 2)
        self.assertNotIn('Type                Name', text)
        win = next(w for w in self.evaluate('getwininfo()') if w['bufnr'] == variables)
        self.assertEqual(self.evaluate(f'getwinvar({win["winid"]}, "&wrap")'), 1)
        ns = self.evaluate('nvim_get_namespaces()["ndb-variables"]')
        highlights = self.evaluate(
            f'nvim_buf_get_extmarks({variables}, {ns}, 0, -1, {{"details": 1}})')
        self.assertGreaterEqual(sum(mark[3]['hl_group'] == 'NdbVariableName'
                                    for mark in highlights), 5)
        self.send('up')
        self.wait(lambda: 'loc storage = ' in self.lines(variables))
        self.assertNotIn('arg size', self.lines(variables))
        self.send('down')
        self.wait(lambda: 'arg size = 12' in self.lines(variables))
        self.send('set var size = 99')
        self.wait(lambda: 'arg size = 99' in self.lines(variables))
        self.send('set var block = (struct Block *) 0x1')
        self.wait(lambda: 'block = 0x1: <unavailable>' in self.lines(variables))
        self.assertNotIn('Traceback', self.lines(self.gdb))
        self.quit()

    def test_loads_user_theme_and_navigation(self):
        config = self.home / '.config/nvim'
        config.mkdir(parents=True)
        (config / 'init.lua').write_text(
            'vim.cmd.colorscheme("morning")\n'
            'vim.keymap.set("n", "H", "gg")\n')
        self.start()
        self.assertEqual(self.evaluate('g:colors_name'), 'morning')
        self.assertEqual(self.evaluate('&background'), 'light')
        self.assertEqual(self.evaluate('maparg("H", "n")'), 'gg')
        self.quit()

    def test_navigation_without_user_config(self):
        (self.home / '.gdbinit').unlink()
        (self.work / '.gdbinit').unlink()
        self.start()
        self.assertEqual(self.evaluate('maparg("H", "n")'), '')
        self.assertIn('NdbPrefix', self.evaluate('maparg("<C-Space>", "n")'))
        self.assertIn('NdbPrefix', self.evaluate('maparg("<C-Space>", "t")'))
        self.send('break main')
        self.send('run')
        self.wait(lambda: 'Breakpoint 1, main' in self.lines(self.gdb))
        self.wait(lambda: '<+0>:' in self.lines(self.named_buffer('Ndb-assembly')))
        for view, name in [('s', str(self.source)), ('a', 'Ndb-assembly')]:
            self.prefix(view)
            self.wait(lambda: self.evaluate('mode()') == 'n'
                      and self.evaluate('bufname()').endswith(name))
            self.tmux('send-keys', '-t', self.pane, '-l', 'gg+')
            self.wait(lambda: self.evaluate('line(".")') == 2)
            self.tmux('send-keys', '-t', self.pane, '-l', '-')
            self.wait(lambda: self.evaluate('line(".")') == 1)
        self.prefix('g')
        self.wait(lambda: self.evaluate('mode()') == 't')
        self.quit()

    def assert_console_navigation(self):
        """Send real keys, not :normal! (which would bypass the mappings)."""
        console = self.evaluate('bufnr()')
        self.prefix('b')
        self.wait(lambda: self.evaluate('mode()') == 'n')
        self.assertEqual(self.evaluate('bufnr()'), console)
        before = self.lines(console)

        def keys(text, expression, expected):
            self.tmux('send-keys', '-t', self.pane, '-l', text)
            self.wait(lambda: self.evaluate(expression) == expected)

        self.send('/^    NAV_070 alpha beta$')
        self.wait(lambda: self.evaluate('getline(".")') == '    NAV_070 alpha beta')
        row = self.evaluate('line(".")')
        keys('$', 'col(".")', 22)
        keys('^', 'col(".")', 5)
        keys('h', 'col(".")', 4)
        keys('l', 'col(".")', 5)
        keys('w', 'col(".")', 13)
        keys('e', 'col(".")', 17)
        keys('b', 'col(".")', 13)
        keys('j', 'line(".")', row + 1)
        keys('k', 'line(".")', row)
        keys('3j', 'line(".")', row + 3)
        keys('3k', 'line(".")', row)
        keys('0', 'col(".")', 1)
        # Visual $ includes the newline, one column past the final character.
        keys('v$', '[mode(), col(".")]', ['v', 23])
        keys('^', '[mode(), col(".")]', ['v', 5])
        self.tmux('send-keys', '-t', self.pane, 'Escape')
        self.wait(lambda: self.evaluate('mode()') == 'n')

        self.send('/alpha')
        self.wait(lambda: self.evaluate('[line("."), col(".")]') == [row, 13])
        keys('n', 'line(".")', row + 1)
        keys('N', 'line(".")', row)
        keys('*', 'line(".")', row + 1)
        keys('#', 'line(".")', row)
        keys('g*', 'line(".")', row + 1)
        self.send('?^    NAV_070')
        self.wait(lambda: self.evaluate('line(".")') == row)
        self.assertEqual(self.evaluate('@/'), '^    NAV_070')

        for key, direction in [('C-d', 1), ('C-u', -1)]:
            previous = self.evaluate('line(".")')
            self.tmux('send-keys', '-t', self.pane, key)
            self.wait(lambda: (self.evaluate('line(".")') - previous) * direction > 0)
        keys('gg', 'line(".")', 1)
        last = self.evaluate('line("$")')
        keys('G', 'line(".")', last)
        self.assertEqual(self.evaluate('mode()'), 'n')
        self.assertEqual(self.lines(console), before)

    def test_gdb_console_navigation_keystrokes(self):
        self.start()
        self.send('python [print("    NAV_%03d alpha beta" % i) for i in range(150)]')
        self.wait(lambda: '    NAV_149 alpha beta' in self.lines(self.gdb))
        # Leave a partial command: browsing must neither submit nor corrupt it.
        self.tmux('send-keys', '-t', self.pane, '-l', 'python print("INPUT_')
        self.wait(lambda: 'python print("INPUT_' in self.lines(self.gdb))
        self.assert_console_navigation()
        self.prefix('g')
        self.wait(lambda: self.evaluate('mode()') == 't')
        # H/L are literal input here, not motions.
        self.send('HL_OK")')
        self.wait(lambda: 'INPUT_HL_OK' in self.lines(self.gdb).splitlines())
        self.quit()

    def test_program_console_navigation_keystrokes(self):
        self.source.write_text(
            '#include <stdio.h>\n'
            'int main(void) { char input[64]; '
            'for (int i = 0; i < 150; ++i) printf("    NAV_%03d alpha beta\\n", i); '
            'fflush(stdout); '
            'if (fgets(input, sizeof input, stdin)) printf("ECHO:%s", input); '
            'return 0; }\n')
        subprocess.run(['gcc', '-g', '-O0', '-o', str(self.program), str(self.source)],
                       check=True, capture_output=True)
        self.start()
        self.send('run')
        self.prefix('p')
        self.wait(lambda: self.evaluate('mode()') == 't'
                  and self.evaluate('bufnr()') != self.gdb)
        program = self.evaluate('bufnr()')
        self.wait(lambda: '    NAV_149 alpha beta' in self.lines(program))
        self.tmux('send-keys', '-t', self.pane, '-l', 'INPUT_')
        self.wait(lambda: 'INPUT_' in self.lines(program))
        self.assert_console_navigation()
        self.prefix('p')
        self.wait(lambda: self.evaluate('mode()') == 't')
        self.send('HL_OK')
        self.wait(lambda: 'ECHO:INPUT_HL_OK' in self.lines(program).splitlines())
        self.prefix('g')
        self.wait(lambda: self.evaluate('mode()') == 't')
        self.quit()

    def test_startup_chatter_hidden_but_diagnostics_visible(self):
        with (self.home / '.gdbinit').open('a') as config:
            config.write('echo STARTUP_WARNING_MUST_STAY_VISIBLE\\n\n')
        self.start()
        for chatter in ['startupdone', 'server new-ui mi', 'New UI allocated']:
            self.assertNotIn(chatter, self.capture())
        self.assertIn('STARTUP_WARNING_MUST_STAY_VISIBLE', self.capture())
        self.assertIn('(gdb)', self.capture())
        self.send('print 6789')
        self.wait(lambda: '$1 = 6789' in self.capture())
        self.send('python [print("VISIBLE_%d" % i) for i in range(80)]')
        self.wait(lambda: 'VISIBLE_79' in self.capture())
        self.tmux('resize-window', '-t', 'test:0', '-x', '140', '-y', '42')
        self.wait(lambda: self.evaluate('[&columns, &lines]') == [140, 42])
        self.prefix('b')
        self.wait(lambda: self.evaluate('mode()') == 'n')
        self.tmux('send-keys', '-t', self.pane, '-l', 'gg')
        self.wait(lambda: 'STARTUP_WARNING_MUST_STAY_VISIBLE' in self.capture())
        for chatter in ['startupdone', 'server new-ui mi', 'New UI allocated']:
            self.assertNotIn(chatter, self.capture())
        self.prefix('g')
        self.wait(lambda: self.evaluate('mode()') == 't')
        self.quit()

    def test_program_io_accepts_stdin(self):
        self.source.write_text(
            '#include <stdio.h>\n#include <unistd.h>\n#include <fcntl.h>\n#include <termios.h>\n'
            'int main(void) { char input[64]; '
            'int tty = open("/dev/tty", O_RDWR); '
            'printf("CONTROLLING_TTY=%d\\n", tty >= 0 && tcgetsid(tty) == getsid(0)); '
            'if (tty >= 0) close(tty); puts("INPUT_READY"); '
            'if (fgets(input, sizeof input, stdin)) printf("ECHO:%s", input); '
            'return 0; }\n')
        subprocess.run(['gcc', '-g', '-O0', '-o', str(self.program), str(self.source)],
                       check=True, capture_output=True)
        self.start()
        self.send('run')
        self.prefix('p')
        self.wait(lambda: self.evaluate('mode()') == 't'
                  and self.evaluate('bufnr()') != self.gdb)
        program = self.evaluate('bufnr()')
        self.wait(lambda: 'INPUT_READY' in self.lines(program))
        self.assertIn('CONTROLLING_TTY=1', self.lines(program))
        self.assertNotIn('Failed to set controlling terminal', self.lines(program))
        self.send('hello ndb')
        self.wait(lambda: 'ECHO:hello ndb' in self.lines(program))
        self.prefix('g')
        self.wait(lambda: self.evaluate('mode()') == 't'
                  and self.evaluate('bufnr()') == self.gdb)
        # A second inferior must be able to acquire the same PTY after exit.
        self.send('run')
        self.prefix('p')
        self.wait(lambda: self.evaluate('mode()') == 't'
                  and self.evaluate('bufnr()') == program)
        self.wait(lambda: self.lines(program).count('INPUT_READY') == 2)
        self.assertEqual(self.lines(program).count('CONTROLLING_TTY=1'), 2)
        self.assertNotIn('Failed to set controlling terminal', self.lines(program))
        self.send('second run')
        self.wait(lambda: 'ECHO:second run' in self.lines(program))
        self.prefix('g')
        self.wait(lambda: self.evaluate('mode()') == 't'
                  and self.evaluate('bufnr()') == self.gdb)
        self.quit()

    def test_program_terminal_interrupt(self):
        self.source.write_text(
            '#include <stdio.h>\n#include <unistd.h>\n'
            'int main(void) { puts("INTERRUPT_READY"); for (;;) pause(); }\n')
        subprocess.run(['gcc', '-g', '-O0', '-o', str(self.program), str(self.source)],
                       check=True, capture_output=True)
        self.start()
        self.send('run')
        self.prefix('p')
        self.wait(lambda: self.evaluate('mode()') == 't'
                  and self.evaluate('bufnr()') != self.gdb)
        program = self.evaluate('bufnr()')
        self.wait(lambda: 'INTERRUPT_READY' in self.lines(program))
        self.tmux('send-keys', '-t', self.pane, 'C-c')
        self.wait(lambda: 'received signal SIGINT' in self.lines(self.gdb))
        self.assertNotIn('Failed to set controlling terminal', self.lines(program))
        self.prefix('g')
        self.wait(lambda: self.evaluate('mode()') == 't'
                  and self.evaluate('bufnr()') == self.gdb)
        self.quit()

    def test_source_reloads_without_readonly_warning(self):
        self.start()
        self.send('break main')
        self.send('run')
        self.wait(lambda: 'Breakpoint 1, main' in self.lines(self.gdb))
        self.prefix('s')
        self.wait(lambda: self.evaluate('mode()') == 'n'
                  and self.evaluate('bufname()') == str(self.source))
        self.source.write_text(self.source.read_text() + '// EXTERNAL_UPDATE\n')
        self.send(':checktime')
        self.wait(lambda: 'EXTERNAL_UPDATE' in self.lines(self.evaluate('bufnr()')))
        self.assertEqual(self.evaluate('&readonly'), 1)
        self.assertEqual(self.evaluate('&modifiable'), 0)
        self.assertNotIn('W10:', self.evaluate('execute("messages")'))
        self.prefix('g')
        self.wait(lambda: self.evaluate('mode()') == 't')
        self.quit()

    def test_snapshots_removed_on_quit(self):
        self.start()
        self.send('python print("STATE_PATH=" + _state_path)')
        self.wait(lambda: any(line.startswith('STATE_PATH=')
                              for line in self.lines(self.gdb).splitlines()))
        path = next(line.split('=', 1)[1] for line in self.lines(self.gdb).splitlines()
                    if line.startswith('STATE_PATH='))
        self.assertTrue(Path(path).exists())
        self.assertNotIn("stack", json.loads(Path(path).read_text()))
        terminal_pids = [self.evaluate(f'jobpid(getbufvar({b["bufnr"]}, "terminal_job_id"))')
                         for b in self.buffers() if b['name'].startswith('term://')]
        self.quit()
        self.assertFalse(Path(path).parent.exists())
        self.wait(lambda: all(not Path(f'/proc/{pid}').exists() for pid in terminal_pids))

    def test_argument_boundaries_and_literals(self):
        arguments = ['two words', '', "a'b", '"quoted"', '$HOME', '*.c', '-flag', '-a', '--assembly',
                     ';touch SHOULD_NOT_EXIST', 'line1\nline2']
        self.start(*arguments)
        self.send('run')
        self.wait(lambda: 'exited with code' in self.lines(self.gdb))
        terminal_buffers = [b for b in self.buffers()
                            if b['bufnr'] != self.gdb and b['name'].startswith('term://')]
        output = '\n'.join(self.lines(b['bufnr']) for b in terminal_buffers)
        for i, argument in enumerate(arguments, 1):
            self.assertIn(f'ARG[{i}]=<{argument}>', output)
        self.assertFalse((self.work / 'SHOULD_NOT_EXIST').exists())
        self.quit()

    def test_session_history_removed_on_quit(self):
        self.send("printf 'BEFORE_DEBUG_%s\\n' {1..70}")
        self.start(program=False)
        self.send('python [print("DEBUG_ONLY_%d" % i) for i in range(150)]')
        self.wait(lambda: 'DEBUG_ONLY_149' in self.lines(self.gdb))
        self.assertIn('DEBUG_ONLY_0', self.lines(self.gdb))
        self.quit()
        screen = self.capture()
        self.assertIn('BEFORE_DEBUG_1', screen)
        self.assertIn('BEFORE_DEBUG_70', screen)
        self.assertNotIn('DEBUG_ONLY_', screen)
