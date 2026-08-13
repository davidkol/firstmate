#!/usr/bin/env bash
# Verify that a signed live Codex process was launched with the exact primary
# policy prefix owned by fm-codex-primary.sh and no later policy layer.
#
# Usage:
#   fm-codex-primary-argv-check.sh <signed-codex-pid>
#
# Process-signature authentication belongs to the caller. This checker only
# judges the immutable, NUL-delimited live argv read from macOS KERN_PROCARGS2.
# Keeping the kernel's argument boundaries prevents prompt text that mentions
# -c or --sandbox from being mistaken for an actual policy option.
set -u

[ "$#" -eq 1 ] || { echo "usage: fm-codex-primary-argv-check.sh <signed-codex-pid>" >&2; exit 2; }
case "$1" in
  ''|*[!0-9]*) echo "error: signed Codex pid must be a positive integer" >&2; exit 2 ;;
esac
[ "$1" -gt 1 ] || { echo "error: signed Codex pid must be a positive integer" >&2; exit 2; }
[ -x /usr/bin/python3 ] || { echo "error: protected macOS Python is unavailable" >&2; exit 1; }

# Keep xcode-select and Python startup behavior independent of caller input.
unset DEVELOPER_DIR PYTHONHOME PYTHONPATH PYTHONSTARTUP
exec /usr/bin/python3 -I -S - "$1" <<'PY'
import ctypes
import os
import struct
import sys

CTL_KERN = 1
KERN_PROCARGS2 = 49


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def process_argv(pid):
    libc = ctypes.CDLL(None, use_errno=True)
    mib = (ctypes.c_int * 3)(CTL_KERN, KERN_PROCARGS2, pid)
    size = ctypes.c_size_t()
    if libc.sysctl(mib, 3, None, ctypes.byref(size), None, 0) != 0 or size.value == 0:
        fail("could not read the signed live Codex argv")
    buffer = ctypes.create_string_buffer(size.value)
    if libc.sysctl(mib, 3, buffer, ctypes.byref(size), None, 0) != 0:
        fail("could not read the signed live Codex argv")

    data = buffer.raw[:size.value]
    if len(data) < ctypes.sizeof(ctypes.c_int):
        fail("signed live Codex argv is malformed")
    argc = struct.unpack_from("=i", data)[0]
    if argc < 1:
        fail("signed live Codex argv is malformed")

    position = ctypes.sizeof(ctypes.c_int)
    executable_end = data.find(b"\0", position)
    if executable_end < 0:
        fail("signed live Codex argv is malformed")
    position = executable_end + 1
    while position < len(data) and data[position] == 0:
        position += 1

    arguments = []
    for _ in range(argc):
        argument_end = data.find(b"\0", position)
        if argument_end < 0:
            fail("signed live Codex argv is malformed")
        arguments.append(data[position:argument_end].decode("utf-8", "surrogateescape"))
        position = argument_end + 1
    return arguments


arguments = process_argv(int(sys.argv[1]))
prefix = [
    "--dangerously-bypass-hook-trust",
    "-c",
    'approval_policy="never"',
    "-c",
    'sandbox_mode="danger-full-access"',
    "--enable",
    "hooks",
]
if os.path.basename(arguments[0]) != "codex" or arguments[1:1 + len(prefix)] != prefix:
    fail("live Codex argv does not carry the supported primary policy prefix")

short_policy_options = ("-a", "-s", "-c", "-p")
long_policy_options = (
    "--ask-for-approval",
    "--sandbox",
    "--config",
    "--profile",
    "--enable",
    "--disable",
)
exact_policy_options = (
    "--approve-for-me",
    "--full-auto",
    "--dangerously-bypass-approvals-and-sandbox",
)
for argument in arguments[1 + len(prefix):]:
    if argument == "--":
        break
    if any(argument.startswith(option) for option in short_policy_options):
        fail("live Codex argv carries a later unsupported policy layer")
    if any(argument == option or argument.startswith(option + "=") for option in long_policy_options):
        fail("live Codex argv carries a later unsupported policy layer")
    if argument in exact_policy_options:
        fail("live Codex argv carries a later unsupported policy layer")
PY
