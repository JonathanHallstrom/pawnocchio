import os

VERSION = "1.8.0"


builds = [
    ("x86_64", "windows", "x86_64", None),
    ("x86_64", "windows", "x86_64", "x86_64_v2"),
    ("x86_64", "windows", "x86_64", "x86_64_v3"),
    ("x86_64", "windows", "x86_64", "x86_64_v4"),
    ("x86_64", "windows", "x86_64", "znver1"),
    ("x86_64", "windows", "x86_64", "znver2"),
    ("x86_64", "windows", "x86_64", "znver3"),
    ("x86_64", "windows", "x86_64", "znver4"),
    ("x86_64", "windows", "x86_64", "znver5"),
    ("aarch64", "windows", "aarch64", None),

    ("x86_64", "linux", "x86_64", None),
    ("x86_64", "linux", "x86_64", "x86_64_v2"),
    ("x86_64", "linux", "x86_64", "x86_64_v3"),
    ("x86_64", "linux", "x86_64", "x86_64_v4"),
    ("x86_64", "linux", "x86_64", "znver1"),
    ("x86_64", "linux", "x86_64", "znver2"),
    ("x86_64", "linux", "x86_64", "znver3"),
    ("x86_64", "linux", "x86_64", "znver4"),
    ("x86_64", "linux", "x86_64", "znver5"),
    ("aarch64", "linux", "aarch64", None),

    ("x86_64", "macos", "x86_64", None),
    ("aarch64", "macos", "aarch64", None),
]

commands = []
for arch, os_name, zig_arch, cpu in builds:
    cpu_flag = f"-Dcpu={cpu} " if cpu else ""
    if cpu is not None:
        if cpu.startswith(arch):
            output_name_base = f"pawnocchio-{VERSION}-{os_name}-{cpu}"
        else:
            output_name_base = f"pawnocchio-{VERSION}-{os_name}-{arch}_{cpu}"
    else:
        output_name_base = f"pawnocchio-{VERSION}-{os_name}-{arch}"
    output_name = output_name_base + (".exe" if os_name == "windows" else "")
    build_cmd = f"zig build --release=fast {cpu_flag}-Dtarget={arch}-{os_name} -Dname={output_name_base}"
    move_cmd = f"cp zig-out/bin/{output_name} builds/{output_name}"
    commands.append(build_cmd + " && " + move_cmd)

# for command in commands:
#     os.system(command + "&")
# os.system("wait")


for command in commands:
    os.system(command)
