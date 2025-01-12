# windows builds
zig build --release=fast -Dcpu=i386 -Dtarget=x86-windows && mv zig-out/bin/pawnocchio.exe builds/pawnocchio_windows_x86.exe
zig build --release=fast -Dcpu=x86_64 -Dtarget=x86_64-windows && mv zig-out/bin/pawnocchio.exe builds/pawnocchio_windows_x86_64.exe
zig build --release=fast -Dcpu=x86_64_v2 -Dtarget=x86_64-windows && mv zig-out/bin/pawnocchio.exe builds/pawnocchio_windows_x86_64_v2.exe
zig build --release=fast -Dcpu=x86_64_v3 -Dtarget=x86_64-windows && mv zig-out/bin/pawnocchio.exe builds/pawnocchio_windows_x86_64_v3.exe
zig build --release=fast -Dcpu=x86_64_v4 -Dtarget=x86_64-windows && mv zig-out/bin/pawnocchio.exe builds/pawnocchio_windows_x86_64_v4.exe
zig build --release=fast -Dcpu=znver1 -Dtarget=x86_64-windows && mv zig-out/bin/pawnocchio.exe builds/pawnocchio_windows_zen1.exe
zig build --release=fast -Dcpu=znver2 -Dtarget=x86_64-windows && mv zig-out/bin/pawnocchio.exe builds/pawnocchio_windows_zen2.exe
zig build --release=fast -Dcpu=znver3 -Dtarget=x86_64-windows && mv zig-out/bin/pawnocchio.exe builds/pawnocchio_windows_zen3.exe
zig build --release=fast -Dcpu=znver4 -Dtarget=x86_64-windows && mv zig-out/bin/pawnocchio.exe builds/pawnocchio_windows_zen4.exe
zig build --release=fast -Dcpu=znver5 -Dtarget=x86_64-windows && mv zig-out/bin/pawnocchio.exe builds/pawnocchio_windows_zen5.exe
zig build --release=fast -Dtarget=aarch64-windows && mv zig-out/bin/pawnocchio.exe builds/pawnocchio_windows_aarch.exe

# linux builds
zig build --release=fast -Dcpu=i386 -Dtarget=x86-linux && mv zig-out/bin/pawnocchio builds/pawnocchio_linux_x86
zig build --release=fast -Dcpu=x86_64 -Dtarget=x86_64-linux && mv zig-out/bin/pawnocchio builds/pawnocchio_linux_x86_64
zig build --release=fast -Dcpu=x86_64_v2 -Dtarget=x86_64-linux && mv zig-out/bin/pawnocchio builds/pawnocchio_linux_x86_64_v2
zig build --release=fast -Dcpu=x86_64_v3 -Dtarget=x86_64-linux && mv zig-out/bin/pawnocchio builds/pawnocchio_linux_x86_64_v3
zig build --release=fast -Dcpu=x86_64_v4 -Dtarget=x86_64-linux && mv zig-out/bin/pawnocchio builds/pawnocchio_linux_x86_64_v4
zig build --release=fast -Dcpu=znver1 -Dtarget=x86_64-linux && mv zig-out/bin/pawnocchio builds/pawnocchio_linux_zen1
zig build --release=fast -Dcpu=znver2 -Dtarget=x86_64-linux && mv zig-out/bin/pawnocchio builds/pawnocchio_linux_zen2
zig build --release=fast -Dcpu=znver3 -Dtarget=x86_64-linux && mv zig-out/bin/pawnocchio builds/pawnocchio_linux_zen3
zig build --release=fast -Dcpu=znver4 -Dtarget=x86_64-linux && mv zig-out/bin/pawnocchio builds/pawnocchio_linux_zen4
zig build --release=fast -Dcpu=znver5 -Dtarget=x86_64-linux && mv zig-out/bin/pawnocchio builds/pawnocchio_linux_zen5
zig build --release=fast -Dtarget=aarch64-linux && mv zig-out/bin/pawnocchio builds/pawnocchio_linux_aarch

# mac builds
zig build --release=fast -Dcpu=x86_64 -Dtarget=x86_64-macos && mv zig-out/bin/pawnocchio builds/pawnocchio_macos_x86_64
zig build --release=fast -Dtarget=aarch64-macos && mv zig-out/bin/pawnocchio builds/pawnocchio_macos_aarch
