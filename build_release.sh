# windows builds
zig build --release=fast -Dcpu=i386 -Dtarget=x86-windows && mv zig-out/bin/pawnocchio.exe builds/pawnocchio_x86_windows.exe
zig build --release=fast -Dcpu=x86_64 -Dtarget=x86_64-windows && mv zig-out/bin/pawnocchio.exe builds/pawnocchio_x86_64_windows.exe
zig build --release=fast -Dcpu=x86_64_v2 -Dtarget=x86_64-windows && mv zig-out/bin/pawnocchio.exe builds/pawnocchio_x86_64_v2_windows.exe
zig build --release=fast -Dcpu=x86_64_v3 -Dtarget=x86_64-windows && mv zig-out/bin/pawnocchio.exe builds/pawnocchio_x86_64_v3_windows.exe
zig build --release=fast -Dcpu=x86_64_v4 -Dtarget=x86_64-windows && mv zig-out/bin/pawnocchio.exe builds/pawnocchio_x86_64_v4_windows.exe
zig build --release=fast -Dcpu=znver1 -Dtarget=x86_64-windows && mv zig-out/bin/pawnocchio.exe builds/pawnocchio_zen1_windows.exe
zig build --release=fast -Dcpu=znver2 -Dtarget=x86_64-windows && mv zig-out/bin/pawnocchio.exe builds/pawnocchio_zen2_windows.exe
zig build --release=fast -Dcpu=znver3 -Dtarget=x86_64-windows && mv zig-out/bin/pawnocchio.exe builds/pawnocchio_zen3_windows.exe
zig build --release=fast -Dcpu=znver4 -Dtarget=x86_64-windows && mv zig-out/bin/pawnocchio.exe builds/pawnocchio_zen4_windows.exe
zig build --release=fast -Dcpu=znver5 -Dtarget=x86_64-windows && mv zig-out/bin/pawnocchio.exe builds/pawnocchio_zen5_windows.exe
zig build --release=fast -Dtarget=aarch64-windows && mv zig-out/bin/pawnocchio.exe builds/pawnocchio_aarch_windows.exe

# linux builds
zig build --release=fast -Dcpu=i386 -Dtarget=x86-linux && mv zig-out/bin/pawnocchio builds/pawnocchio_x86_linux
zig build --release=fast -Dcpu=x86_64 -Dtarget=x86_64-linux && mv zig-out/bin/pawnocchio builds/pawnocchio_x86_64_linux
zig build --release=fast -Dcpu=x86_64_v2 -Dtarget=x86_64-linux && mv zig-out/bin/pawnocchio builds/pawnocchio_x86_64_v2_linux
zig build --release=fast -Dcpu=x86_64_v3 -Dtarget=x86_64-linux && mv zig-out/bin/pawnocchio builds/pawnocchio_x86_64_v3_linux
zig build --release=fast -Dcpu=x86_64_v4 -Dtarget=x86_64-linux && mv zig-out/bin/pawnocchio builds/pawnocchio_x86_64_v4_linux
zig build --release=fast -Dcpu=znver1 -Dtarget=x86_64-linux && mv zig-out/bin/pawnocchio builds/pawnocchio_zen1_linux
zig build --release=fast -Dcpu=znver2 -Dtarget=x86_64-linux && mv zig-out/bin/pawnocchio builds/pawnocchio_zen2_linux
zig build --release=fast -Dcpu=znver3 -Dtarget=x86_64-linux && mv zig-out/bin/pawnocchio builds/pawnocchio_zen3_linux
zig build --release=fast -Dcpu=znver4 -Dtarget=x86_64-linux && mv zig-out/bin/pawnocchio builds/pawnocchio_zen4_linux
zig build --release=fast -Dcpu=znver5 -Dtarget=x86_64-linux && mv zig-out/bin/pawnocchio builds/pawnocchio_zen5_linux
zig build --release=fast -Dtarget=aarch64-linux && mv zig-out/bin/pawnocchio builds/pawnocchio_aarch_linux

# mac builds
zig build --release=fast -Dcpu=x86_64 -Dtarget=x86_64-macos && mv zig-out/bin/pawnocchio builds/pawnocchio_x86_64_macos
zig build --release=fast -Dtarget=aarch64-macos && mv zig-out/bin/pawnocchio builds/pawnocchio_aarch_macos
