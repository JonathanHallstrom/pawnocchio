import os

VERSION = "1.9"


builds = [
    ("x86_64", "windows", "x86_64", None, None),
    ("x86_64", "windows", "x86_64", "x86_64_v2", "x86_64_v2"),
    ("x86_64", "windows", "x86_64", "x86_64_v3", "x86_64_v3"),
    ("x86_64", "windows", "x86_64", "x86_64_v4", "x86_64_v4"),
    ("x86_64", "windows", "x86_64", "znver1", None),
    ("x86_64", "windows", "x86_64", "znver2", None),
    ("x86_64", "windows", "x86_64", "znver3", None),
    ("x86_64", "windows", "x86_64", "znver4", None),
    ("x86_64", "windows", "x86_64", "znver5", None),
    ("aarch64", "windows", "aarch64", None, None),

    ("x86_64", "linux", "x86_64", None, None),
    ("x86_64", "linux", "x86_64", "x86_64_v2", "x86_64_v2"),
    ("x86_64", "linux", "x86_64", "x86_64_v3", "x86_64_v3"),
    ("x86_64", "linux", "x86_64", "x86_64_v4", "x86_64_v4"),
    ("x86_64", "linux", "x86_64", "znver1", None),
    ("x86_64", "linux", "x86_64", "znver2", None),
    ("x86_64", "linux", "x86_64", "znver3", None),
    ("x86_64", "linux", "x86_64", "znver4", None),
    ("x86_64", "linux", "x86_64", "znver5", None),
    ("aarch64", "linux", "aarch64", None, None),
    ("aarch64", "linux", "aarch64", "baseline+dotprod", "aarch64-dotprod"),

    ("x86_64", "macos", "x86_64", None, None),
    ("aarch64", "macos", "aarch64", None, None),
]

commands = []
for arch, os_name, zig_arch, cpu, arch_cpu in builds:
    cpu_flag = f"-Dcpu={cpu} " if cpu else ""
    arch_name = str(arch)
    if cpu is not None:
        if arch_cpu is None:
            arch_cpu = f"{arch}_{cpu}"
        output_name_base = f"pawnocchio-{VERSION}-{os_name}-{arch_cpu}"
    else:
        output_name_base = f"pawnocchio-{VERSION}-{os_name}-{arch}"
    output_name = output_name_base + (".exe" if os_name == "windows" else "")
    build_cmd = f"zig build --release=fast {cpu_flag}-Dtarget={arch}-{os_name} -Dname={output_name_base}"
    move_cmd = f"cp zig-out/bin/{output_name} builds/{output_name}"
    full_cmd = build_cmd + " && " + move_cmd
    # print(output_name_base)
    commands.append(full_cmd)

for command in commands:
    os.system(command + "&")
os.system("wait")


# for command in commands:
#     os.system(command)
