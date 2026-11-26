"""Read-only GDB snapshots for variables, breakpoints, registers, and stack.

Termdebug still owns execution, source, assembly, and its MI channel.
This bridge never sends commands to that channel or parses terminal output.
"""
import json
import os

import gdb
from gdb.FrameDecorator import FrameDecorator


_state_path = os.environ.pop("NDB_STATE")
_assembly_mode = os.environ.pop("NDB_ASSEMBLY", "0") == "1"
_previous = None
_pending = False
_stop_serial = 0
_register_sample = None
_register_changes = set()


def _value_text(value):
    # Bound expensive/large values, keep structs on one line, and never call
    # inferior functions to obtain a value. Dereference struct pointers once,
    # like Dashboard's compact pointer-plus-pointee presentation.
    options = dict(pretty_arrays=False, pretty_structs=False, max_elements=16,
                   max_depth=3)
    value_type = value.type.strip_typedefs()
    if value_type.code in (gdb.TYPE_CODE_REF, gdb.TYPE_CODE_RVALUE_REF):
        value = value.referenced_value()
        value_type = value.type.strip_typedefs()
    text = value.format_string(**options)
    if not value.is_optimized_out and value_type.code == gdb.TYPE_CODE_PTR:
        target = value_type.target().strip_typedefs()
        if target.code in (gdb.TYPE_CODE_STRUCT, gdb.TYPE_CODE_UNION):
            try:
                text += ": " + value.dereference().format_string(**options)
            except gdb.error:
                text += ": <unavailable>"
    text = " ".join(text.splitlines())
    return text if len(text) <= 1024 else text[:1024] + "..."


def _variables():
    thread = gdb.selected_thread()
    if thread is None:
        return [], "No variables (program not running)."
    if thread.is_running():
        return [], "Running..."
    try:
        frame = gdb.selected_frame()
        decorator = FrameDecorator(frame)
        records = []
        for kind, symbols in (("arg", decorator.frame_args()),
                              ("loc", decorator.frame_locals())):
            for entry in symbols or ():
                try:
                    value = _value_text(entry.sym.value(frame))
                except (gdb.error, RuntimeError) as error:
                    value = "<unavailable: {}>".format(error)
                records.append({"kind": kind, "name": str(entry.sym),
                                "value": " ".join(value.splitlines())})
        return records, "No arguments or locals." if not records else ""
    except (gdb.error, RuntimeError) as error:
        return [], "Variables unavailable: " + str(error)


def _symbol(address):
    """Bounded, read-only lookup; no inferior calls or pointer chasing."""
    try:
        text = gdb.execute("info symbol {:#x}".format(address), to_string=True).strip()
        if text.startswith("No symbol"):
            return ""
        return text.split(" in section ", 1)[0].replace(" + ", "+")
    except gdb.error:
        return ""


def _machine_state():
    global _register_sample, _register_changes
    state = {"registers": [], "registers_note": "Program not running.",
             "stack": ["Program not running."], "stack_title": "Stack — following $sp"}
    thread = gdb.selected_thread()
    if thread is None:
        _register_sample = None
        _register_changes = set()
        return state
    if not thread.is_stopped():
        state.update(registers_note="Running...", stack=["Running..."])
        return state
    try:
        frame = gdb.selected_frame()
        arch = frame.architecture()
        # GDB supplies the target's general registers. Segment registers aren't
        # useful in the compact x86 view; SIMD/FPU registers are not requested.
        omitted = {"cs", "ss", "ds", "es", "fs", "gs", "fs_base", "gs_base"}
        flag_names = {"eflags", "rflags", "cpsr", "pstate", "psr"}
        descriptors = list(arch.registers("general"))
        names = {r.name for r in descriptors}
        descriptors += [r for r in arch.registers()
                        if r.name in flag_names and r.name not in names]
        for reg in descriptors:
            if arch.name().startswith("i386") and reg.name in omitted:
                continue
            entry = {"name": reg.name, "value": "<unavailable>"}
            try:
                value = frame.read_register(reg)
                if not value.is_optimized_out:
                    entry["value"] = value.format_string(format="x")
                    if reg.name in flag_names:
                        decoded = value.format_string()
                        if "[" in decoded:
                            entry["flags"] = decoded[decoded.index("["):]
            except (gdb.error, RuntimeError):
                pass
            state["registers"].append(entry)
        key = (gdb.selected_inferior().num, thread.global_num, frame.level())
        values = {r["name"]: r["value"] for r in state["registers"]}
        if _register_sample is None or _register_sample[0] != key:
            _register_changes = set()
        elif (_register_sample[1] != _stop_serial or _register_sample[2] != values):
            _register_changes = {name for name, value in values.items()
                                 if name in _register_sample[2]
                                 and _register_sample[2][name] != value}
        _register_sample = (key, _stop_serial, values)
        for entry in state["registers"]:
            entry["changed"] = entry["name"] in _register_changes
        state["registers_note"] = "No general registers available."
    except (gdb.error, RuntimeError) as error:
        state["registers_note"] = "Registers unavailable: " + str(error)

    try:
        # Typed reads use the target's pointer width AND endianness, not Python's
        # host architecture. Each word fails independently at mapping boundaries.
        sp = int(gdb.selected_frame().read_register("sp"))
        pointer = gdb.lookup_type("void").pointer()
        size = pointer.sizeof
        mask = (1 << (size * 8)) - 1
        state["stack_title"] = "Stack — $sp={:#x} — {}-byte words".format(sp, size)
        lines = ["Offset  Address             Value               Symbol"]
        for index in range(16):
            offset = index * size
            address = (sp + offset) & mask
            prefix = "+0x{:02x}   0x{:0{}x}  ".format(offset, address, size * 2)
            try:
                value = int(gdb.Value(address).cast(pointer.pointer()).dereference())
                hint = _symbol(value) if value else ""
                lines.append(prefix + "0x{:0{}x}  {}".format(value, size * 2, hint).rstrip())
            except (gdb.error, RuntimeError):
                lines.append(prefix + "<unavailable>")
        state["stack"] = lines
    except (gdb.error, RuntimeError) as error:
        state["stack"] = ["Stack unavailable: " + str(error)]
    return state


def _breakpoint_locations():
    return [{"address": hex(loc.address), "enabled": bp.enabled and loc.enabled}
            for bp in gdb.breakpoints() or () if bp.is_valid() and bp.visible
            and bp.type in (gdb.BP_BREAKPOINT, gdb.BP_HARDWARE_BREAKPOINT)
            for loc in bp.locations if loc.address is not None]


def _breakpoints():
    kinds = {
        gdb.BP_BREAKPOINT: "break",
        gdb.BP_HARDWARE_BREAKPOINT: "hbreak",
        gdb.BP_WATCHPOINT: "watch",
        gdb.BP_HARDWARE_WATCHPOINT: "watch",
        gdb.BP_READ_WATCHPOINT: "rwatch",
        gdb.BP_ACCESS_WATCHPOINT: "awatch",
    }
    lines = []
    for bp in gdb.breakpoints() or ():
        if not bp.is_valid() or not bp.visible:
            continue
        state = "enabled" if bp.enabled else "disabled"
        if bp.pending:
            state += ", pending"
        if bp.temporary:
            state += ", temporary"
        location = bp.location or bp.expression or ""
        locations = bp.locations
        if _assembly_mode and len(locations) == 1 and locations[0].address is not None:
            address = locations[0].address
            location = "{:#x} {}".format(address, _symbol(address) or location)
        elif len(locations) == 1 and locations[0].source:
            filename, line = locations[0].source
            location += " at {}:{}".format(os.path.basename(filename), line)
        lines.append("[{}] {} {}  ({}, hits {})".format(
            bp.number, kinds.get(bp.type, "breakpoint"), location, state, bp.hit_count))
        if bp.condition:
            lines.append("    if " + bp.condition)
        if bp.thread is not None:
            lines.append("    thread " + str(bp.thread))
        if len(locations) > 1:
            for index, loc in enumerate(locations, 1):
                source = ""
                if loc.source:
                    filename, line = loc.source
                    source = " {}:{}".format(os.path.basename(filename), line)
                address = "{:#x}".format(loc.address) if loc.address is not None else "?"
                lines.append("    {}.{} {}{}{}".format(
                    bp.number, index, address, source, "" if loc.enabled else " (disabled)"))
    # A condition/expression may contain newlines; each UI entry must be one line.
    return "\n".join(lines).splitlines() or ["No breakpoints."]


def _publish(*_):
    global _previous
    try:
        thread = gdb.selected_thread()
        snapshot = {
            "stopped": thread is not None and thread.is_stopped(),
            "breakpoints": _breakpoints(),
        }
        if _assembly_mode:
            snapshot.update(_machine_state())
            snapshot["breakpoint_locations"] = _breakpoint_locations()
        else:
            snapshot["variables"], snapshot["variables_note"] = _variables()
        state = json.dumps(snapshot)
        if state != _previous:
            # Readers see either complete snapshot, never a partially written file.
            with open(_state_path + ".tmp", "w", encoding="utf-8") as output:
                output.write(state)
            os.replace(_state_path + ".tmp", _state_path)
            _previous = state
    except (OSError, gdb.error):
        # Closing the viewer or an unavailable target must not break GDB commands.
        pass


def _flush():
    global _pending
    _pending = False
    _publish()


def _changed(*_):
    global _pending
    if not _pending:
        _pending = True
        # Breakpoint notifications may fire before GDB finishes changing its list.
        gdb.post_event(_flush)


def _stopped(*_):
    global _stop_serial
    _stop_serial += 1
    _changed()


gdb.events.stop.connect(_stopped)
gdb.events.before_prompt.connect(_publish)
for _event in (gdb.events.cont, gdb.events.exited,
               gdb.events.breakpoint_created, gdb.events.breakpoint_modified,
               gdb.events.breakpoint_deleted):
    _event.connect(_changed)
_publish()
