"""
Overwatch - GitHub Silent Auto-Updater & License Manager
Checks for new releases once daily in the background from GitHub releases,
prompts the user to update, downloads the installer, and executes a clean upgrade.
"""

import sys
import os
import time
import json
import re
import tempfile
import urllib.request
import urllib.error
import subprocess
import threading

from PyQt6.QtWidgets import (QDialog, QVBoxLayout, QHBoxLayout, QLabel,
                             QPushButton, QProgressBar, QTextEdit, QFrame,
                             QApplication, QMessageBox, QGraphicsDropShadowEffect)
from PyQt6.QtCore import Qt, QThread, pyqtSignal, QObject
from PyQt6.QtGui import QIcon, QColor

from config import Config


def parse_version(v_str):
    """Parse version string like 'v4.6.2' or '4.6.2' into a tuple of ints for accurate comparison."""
    if not v_str:
        return (0, 0, 0)
    cleaned = re.sub(r'^[vV]', '', str(v_str).strip())
    parts = []
    for p in cleaned.split('.'):
        try:
            parts.append(int(re.search(r'\d+', p).group()))
        except Exception:
            parts.append(0)
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts[:3])


def get_update_cache_path():
    return os.path.join(os.path.expanduser("~"), ".overwatch_update_cache.json")


def should_check_daily():
    cache_path = get_update_cache_path()
    if not os.path.exists(cache_path):
        return True
    try:
        with open(cache_path, "r", encoding="utf-8") as f:
            data = json.load(f)
            last_check = data.get("last_check_timestamp", 0)
            return (time.time() - last_check) >= (Config.UPDATE_CHECK_INTERVAL_HOURS * 3600)
    except Exception:
        return True


def record_check_timestamp():
    cache_path = get_update_cache_path()
    try:
        with open(cache_path, "w", encoding="utf-8") as f:
            json.dump({"last_check_timestamp": time.time()}, f)
    except Exception:
        pass


def check_github_release_sync():
    """Synchronously queries GitHub releases API. Returns (has_update, new_version, release_notes, download_url, asset_name)."""
    headers = {
        "User-Agent": "Overwatch-Monitor-Client",
        "Accept": "application/vnd.github.v3+json"
    }
    req = urllib.request.Request(Config.GITHUB_RELEASES_API, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=6.0) as resp:
            if resp.status != 200:
                return False, None, None, None, None
            data = json.loads(resp.read().decode('utf-8'))
            tag_name = data.get("tag_name", "")
            release_notes = data.get("body", "No release notes provided.")
            
            latest_v = parse_version(tag_name)
            current_v = parse_version(Config.VERSION)

            if latest_v > current_v:
                # Find suitable asset (prefer .msi or .exe)
                assets = data.get("assets", [])
                download_url = None
                asset_name = None

                for a in assets:
                    name = a.get("name", "").lower()
                    if name.endswith(".msi"):
                        download_url = a.get("browser_download_url")
                        asset_name = a.get("name")
                        break

                if not download_url:
                    for a in assets:
                        name = a.get("name", "").lower()
                        if name.endswith(".exe"):
                            download_url = a.get("browser_download_url")
                            asset_name = a.get("name")
                            break

                # Fallback to html_url if no binary asset uploaded
                if not download_url:
                    download_url = data.get("html_url")
                    asset_name = None

                return True, tag_name, release_notes, download_url, asset_name
    except Exception:
        pass

    return False, None, None, None, None


class DownloadWorker(QThread):
    progress_changed = pyqtSignal(int, str)  # percent, status_text
    download_finished = pyqtSignal(str)     # local_file_path
    download_error = pyqtSignal(str)        # error message

    def __init__(self, url, asset_name):
        super().__init__()
        self.url = url
        self.asset_name = asset_name or "Overwatch-Update.msi"
        self._cancelled = False

    def cancel(self):
        self._cancelled = True

    def run(self):
        try:
            target_path = os.path.join(tempfile.gettempdir(), self.asset_name)
            req = urllib.request.Request(self.url, headers={"User-Agent": "Overwatch-Monitor-Client"})
            
            with urllib.request.urlopen(req, timeout=30.0) as resp:
                total_size = int(resp.headers.get('Content-Length', 0))
                downloaded = 0
                chunk_size = 64 * 1024

                with open(target_path, 'wb') as f:
                    while not self._cancelled:
                        chunk = resp.read(chunk_size)
                        if not chunk:
                            break
                        f.write(chunk)
                        downloaded += len(chunk)
                        if total_size > 0:
                            pct = int((downloaded / total_size) * 100)
                            mb_down = downloaded / (1024 * 1024)
                            mb_tot = total_size / (1024 * 1024)
                            self.progress_changed.emit(pct, f"Downloading: {mb_down:.1f} MB / {mb_tot:.1f} MB ({pct}%)")
                        else:
                            mb_down = downloaded / (1024 * 1024)
                            self.progress_changed.emit(50, f"Downloaded: {mb_down:.1f} MB")

            if self._cancelled:
                try:
                    os.remove(target_path)
                except Exception:
                    pass
                return

            self.download_finished.emit(target_path)
        except Exception as e:
            self.download_error.emit(str(e))


class DownloadProgressModal(QDialog):
    def __init__(self, url, asset_name, parent=None):
        super().__init__(parent)
        self.url = url
        self.asset_name = asset_name
        self.downloaded_file = None

        self.setWindowTitle("Downloading Overwatch Update")
        self.setFixedSize(460, 200)
        self.setStyleSheet("background-color: #0F172A; color: #F8FAFC;")

        layout = QVBoxLayout(self)
        layout.setContentsMargins(24, 24, 24, 24)
        layout.setSpacing(14)

        title = QLabel("📥 Downloading Latest Version...", self)
        title.setStyleSheet("font-size: 16px; font-weight: 700; color: #00F3FF;")
        layout.addWidget(title)

        self.status_lbl = QLabel("Connecting to GitHub release server...", self)
        self.status_lbl.setStyleSheet("color: #94A3B8; font-size: 13px;")
        layout.addWidget(self.status_lbl)

        self.pbar = QProgressBar(self)
        self.pbar.setRange(0, 100)
        self.pbar.setValue(0)
        self.pbar.setStyleSheet("""
            QProgressBar {
                background-color: rgba(255, 255, 255, 0.08);
                border: 1px solid rgba(255, 255, 255, 0.15);
                border-radius: 8px;
                text-align: center;
                color: #FFFFFF;
                font-weight: 700;
                height: 22px;
            }
            QProgressBar::chunk {
                background: qlineargradient(x1:0, y1:0, x2:1, y2:0, stop:0 #00F3FF, stop:1 #10B981);
                border-radius: 7px;
            }
        """)
        layout.addWidget(self.pbar)

        btn_layout = QHBoxLayout()
        btn_layout.addStretch()
        self.cancel_btn = QPushButton("Cancel", self)
        self.cancel_btn.setStyleSheet("background-color: rgba(239, 68, 68, 0.2); border: 1px solid #EF4444; color: #EF4444; padding: 6px 16px; border-radius: 6px;")
        self.cancel_btn.clicked.connect(self.on_cancel)
        btn_layout.addWidget(self.cancel_btn)
        layout.addLayout(btn_layout)

        self.worker = DownloadWorker(self.url, self.asset_name)
        self.worker.progress_changed.connect(self.on_progress)
        self.worker.download_finished.connect(self.on_finished)
        self.worker.download_error.connect(self.on_error)
        self.worker.start()

    def on_progress(self, pct, text):
        self.pbar.setValue(pct)
        self.status_lbl.setText(text)

    def on_finished(self, local_path):
        self.downloaded_file = local_path
        self.status_lbl.setText("Download complete! Launching installer...")
        self.accept()

    def on_error(self, err):
        QMessageBox.critical(self, "Download Error", f"Failed to download update:\n{err}")
        self.reject()

    def on_cancel(self):
        if self.worker.isRunning():
            self.worker.cancel()
            self.worker.wait()
        self.reject()


class UpdatePromptModal(QDialog):
    def __init__(self, new_version, release_notes, download_url, asset_name, parent=None):
        super().__init__(parent)
        self.new_version = new_version
        self.release_notes = release_notes
        self.download_url = download_url
        self.asset_name = asset_name
        self.accepted_update = False

        self.setWindowTitle("Update Available - Overwatch")
        self.setFixedSize(520, 420)
        self.setStyleSheet("background-color: #0F172A; color: #F8FAFC;")

        layout = QVBoxLayout(self)
        layout.setContentsMargins(24, 24, 24, 24)
        layout.setSpacing(14)

        # Header
        hdr_layout = QHBoxLayout()
        title = QLabel("🚀 New Version Available!", self)
        title.setStyleSheet("font-size: 18px; font-weight: 800; color: #00F3FF;")
        hdr_layout.addWidget(title)
        hdr_layout.addStretch()

        ver_badge = QLabel(f"v{Config.VERSION}  ➜  {self.new_version}", self)
        ver_badge.setStyleSheet("background: rgba(16, 185, 129, 0.2); border: 1px solid #10B981; color: #10B981; font-weight: 700; padding: 4px 10px; border-radius: 8px;")
        hdr_layout.addWidget(ver_badge)
        layout.addLayout(hdr_layout)

        desc = QLabel("An updated release is ready for installation. Upgrading replaces older files cleanly with zero residue.", self)
        desc.setWordWrap(True)
        desc.setStyleSheet("color: #94A3B8; font-size: 13px;")
        layout.addWidget(desc)

        # Changelog preview
        layout.addWidget(QLabel("Release Notes:", self))
        notes_box = QTextEdit(self)
        notes_box.setReadOnly(True)
        notes_box.setPlainText(self.release_notes or "Bug fixes and performance enhancements.")
        notes_box.setStyleSheet("""
            QTextEdit {
                background-color: rgba(15, 23, 42, 0.6);
                border: 1px solid rgba(255, 255, 255, 0.12);
                border-radius: 8px;
                color: #CBD5E1;
                font-family: 'Consolas', 'Segoe UI', sans-serif;
                font-size: 12px;
                padding: 8px;
            }
        """)
        layout.addWidget(notes_box, stretch=1)

        # Buttons
        btn_layout = QHBoxLayout()
        btn_layout.setSpacing(12)

        later_btn = QPushButton("Remind Me Later", self)
        later_btn.setStyleSheet("""
            QPushButton {
                background-color: rgba(255, 255, 255, 0.08);
                border: 1px solid rgba(255, 255, 255, 0.15);
                color: #CBD5E1;
                font-weight: 600;
                padding: 8px 16px;
                border-radius: 6px;
            }
            QPushButton:hover {
                background-color: rgba(255, 255, 255, 0.15);
            }
        """)
        later_btn.clicked.connect(self.reject)
        btn_layout.addWidget(later_btn)

        btn_layout.addStretch()

        install_btn = QPushButton("⚡ Download & Install Update", self)
        install_btn.setStyleSheet("""
            QPushButton {
                background: qlineargradient(x1:0, y1:0, x2:1, y2:0, stop:0 #00F3FF, stop:1 #0088FF);
                color: #0A0F1D;
                font-weight: 700;
                padding: 8px 20px;
                border: none;
                border-radius: 6px;
            }
            QPushButton:hover {
                background: #00F3FF;
            }
        """)
        install_btn.clicked.connect(self.on_install_clicked)
        btn_layout.addWidget(install_btn)

        layout.addLayout(btn_layout)

    def on_install_clicked(self):
        self.accepted_update = True
        self.accept()


def execute_clean_installer(installer_path):
    """Executes the downloaded installer and terminates current application so files are not locked."""
    try:
        lower_path = installer_path.lower()
        if lower_path.endswith(".msi"):
            # Launch msiexec in interactive mode (or with /qb) to let user complete upgrade
            subprocess.Popen(["msiexec", "/i", installer_path], close_fds=True)
        else:
            subprocess.Popen([installer_path], close_fds=True)
        
        # Exit current running Overwatch instance cleanly
        app = QApplication.instance()
        if app:
            app.quit()
        sys.exit(0)
    except Exception as e:
        QMessageBox.critical(None, "Launch Error", f"Could not launch installer:\n{e}")


class UpdateBridge(QObject):
    update_found = pyqtSignal(str, str, str, str)  # new_v, notes, url, asset_name
    no_update_found = pyqtSignal()
    check_error = pyqtSignal(str)


_GLOBAL_UPDATE_BRIDGE = None

def get_update_bridge():
    global _GLOBAL_UPDATE_BRIDGE
    if _GLOBAL_UPDATE_BRIDGE is None:
        _GLOBAL_UPDATE_BRIDGE = UpdateBridge()
    return _GLOBAL_UPDATE_BRIDGE


def start_silent_daily_update_check(parent_widget=None):
    """Runs a background check once every 24 hours. Does not prompt if no update is available."""
    if not should_check_daily():
        return

    bridge = get_update_bridge()

    def _worker():
        record_check_timestamp()
        has_upd, new_v, notes, url, asset = check_github_release_sync()
        if has_upd and url:
            bridge.update_found.emit(new_v, notes, url, asset or "Overwatch-Setup.msi")

    t = threading.Thread(target=_worker, daemon=True)
    t.start()


def manual_check_for_updates(parent_widget):
    """User-triggered update check (from Settings or menu). Provides explicit visual feedback."""
    bridge = get_update_bridge()
    
    def _worker():
        record_check_timestamp()
        has_upd, new_v, notes, url, asset = check_github_release_sync()
        if has_upd and url:
            bridge.update_found.emit(new_v, notes, url, asset or "Overwatch-Setup.msi")
        else:
            bridge.no_update_found.emit()

    t = threading.Thread(target=_worker, daemon=True)
    t.start()


def prompt_and_install_update(parent_widget, new_v, notes, url, asset_name):
    """Shows the update prompt dialog and handles downloading/installing if accepted."""
    dlg = UpdatePromptModal(new_v, notes, url, asset_name, parent_widget)
    if dlg.exec() == QDialog.DialogCode.Accepted and dlg.accepted_update:
        if url.startswith("http") and asset_name:
            p_dlg = DownloadProgressModal(url, asset_name, parent_widget)
            if p_dlg.exec() == QDialog.DialogCode.Accepted and p_dlg.downloaded_file:
                execute_clean_installer(p_dlg.downloaded_file)
        else:
            # Fallback: open release page in browser
            import webbrowser
            webbrowser.open(url)


def show_license_dialog(parent_widget):
    """Displays the Apache 2.0 license text in a sleek modal dialog."""
    bundle_dir = getattr(sys, '_MEIPASS', os.path.dirname(os.path.abspath(__file__)))
    lic_path = os.path.join(bundle_dir, "LICENSE")
    lic_text = ""

    if os.path.exists(lic_path):
        try:
            with open(lic_path, "r", encoding="utf-8") as f:
                lic_text = f.read()
        except Exception:
            pass

    if not lic_text:
        lic_text = (
            "Apache License, Version 2.0\n"
            "Copyright 2026 Jimhpar / Blackbox THC\n\n"
            "Licensed under the Apache License, Version 2.0 (the 'License');\n"
            "you may not use this file except in compliance with the License.\n"
            "You may obtain a copy of the License at:\n\n"
            "    http://www.apache.org/licenses/LICENSE-2.0\n\n"
            "Unless required by applicable law or agreed to in writing, software\n"
            "distributed under the License is distributed on an 'AS IS' BASIS,\n"
            "WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.\n"
            "See the License for the specific language governing permissions and\n"
            "limitations under the License."
        )

    dlg = QDialog(parent_widget)
    dlg.setWindowTitle("Overwatch - Apache 2.0 Open Source License")
    dlg.setFixedSize(620, 500)
    dlg.setStyleSheet("background-color: #0F172A; color: #F8FAFC;")

    layout = QVBoxLayout(dlg)
    layout.setContentsMargins(24, 24, 24, 24)
    layout.setSpacing(14)

    title = QLabel("📜 Apache License 2.0", dlg)
    title.setStyleSheet("font-size: 18px; font-weight: 800; color: #00F3FF;")
    layout.addWidget(title)

    txt = QTextEdit(dlg)
    txt.setReadOnly(True)
    txt.setPlainText(lic_text)
    txt.setStyleSheet("""
        QTextEdit {
            background-color: rgba(15, 23, 42, 0.7);
            border: 1px solid rgba(255, 255, 255, 0.12);
            border-radius: 8px;
            color: #E2E8F0;
            font-family: 'Consolas', monospace;
            font-size: 11px;
            padding: 8px;
        }
    """)
    layout.addWidget(txt, stretch=1)

    btn_layout = QHBoxLayout()
    btn_layout.addStretch()
    close_btn = QPushButton("Close", dlg)
    close_btn.setStyleSheet("""
        QPushButton {
            background-color: rgba(255, 255, 255, 0.1);
            border: 1px solid rgba(255, 255, 255, 0.2);
            color: #FFFFFF;
            padding: 6px 20px;
            border-radius: 6px;
            font-weight: 600;
        }
        QPushButton:hover {
            background-color: rgba(255, 255, 255, 0.2);
        }
    """)
    close_btn.clicked.connect(dlg.accept)
    btn_layout.addWidget(close_btn)
    layout.addLayout(btn_layout)

    dlg.exec()
