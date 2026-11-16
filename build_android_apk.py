import os
import shutil
import subprocess
import sys

def build_apk():
    project_root = os.path.dirname(os.path.abspath(__file__))
    app_dir = os.path.join(project_root, "overwatch_app")
    
    version = "4.7.0"
    universal_apk_name = f"Overwatch-v{version}.apk"
    arm64_apk_name = f"Overwatch-v{version}-arm64.apk"

    universal_apk_target = os.path.join(project_root, universal_apk_name)
    arm64_apk_target = os.path.join(project_root, arm64_apk_name)

    print(f"[*] Building Optimized Release APKs (Version {version})...")
    
    # 1. Build Universal Release APK
    print("[*] Compiling Universal Release APK...")
    cmd_universal = ["flutter", "build", "apk", "--release"]
    res1 = subprocess.run(cmd_universal, cwd=app_dir, shell=True)
    if res1.returncode != 0:
        print("[!] Universal release build failed!")
        sys.exit(1)

    src_universal = os.path.join(app_dir, "build", "app", "outputs", "flutter-apk", "app-release.apk")
    if os.path.exists(src_universal):
        shutil.copy2(src_universal, universal_apk_target)
        size1 = os.path.getsize(universal_apk_target) / (1024 * 1024)
        print(f"[✓] Universal APK generated: {universal_apk_name} ({size1:.2f} MB)")

    # 2. Build Split ABI (Ultra-Lightweight arm64)
    print("[*] Compiling Ultra-Lightweight Split ABI APKs...")
    cmd_split = ["flutter", "build", "apk", "--release", "--split-per-abi"]
    res2 = subprocess.run(cmd_split, cwd=app_dir, shell=True)
    if res2.returncode == 0:
        src_arm64 = os.path.join(app_dir, "build", "app", "outputs", "flutter-apk", "app-arm64-v8a-release.apk")
        if os.path.exists(src_arm64):
            shutil.copy2(src_arm64, arm64_apk_target)
            size2 = os.path.getsize(arm64_apk_target) / (1024 * 1024)
            print(f"[✓] Ultra-Lightweight (arm64) APK generated: {arm64_apk_name} ({size2:.2f} MB)")

    print(f"\n[✓] All APKs are placed in the project root: {project_root}")

if __name__ == "__main__":
    build_apk()
