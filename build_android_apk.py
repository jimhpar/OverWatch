import os
import shutil
import subprocess
import sys

def build_apk():
    project_root = os.path.dirname(os.path.abspath(__file__))
    app_dir = os.path.join(project_root, "overwatch_app")
    
    version = "4.7.0"
    target_apk_name = f"Overwatch-v{version}.apk"
    target_apk_path = os.path.join(project_root, target_apk_name)

    print(f"[*] Building Overwatch APK for Android (Version {version})...")
    
    # Run flutter build apk
    cmd = ["flutter", "build", "apk", "--debug"]
    result = subprocess.run(cmd, cwd=app_dir, shell=True)
    if result.returncode != 0:
        print("[!] Flutter build failed!")
        sys.exit(1)

    built_apk_path = os.path.join(app_dir, "build", "app", "outputs", "flutter-apk", "app-debug.apk")
    if not os.path.exists(built_apk_path):
        print(f"[!] Built APK not found at {built_apk_path}")
        sys.exit(1)

    print(f"[*] Copying APK to project root folder: {target_apk_path}")
    shutil.copy2(built_apk_path, target_apk_path)

    file_size_mb = os.path.getsize(target_apk_path) / (1024 * 1024)
    print(f"[✓] Successfully generated: {target_apk_name} ({file_size_mb:.2f} MB)")
    print(f"[✓] Location: {target_apk_path}")

if __name__ == "__main__":
    build_apk()
