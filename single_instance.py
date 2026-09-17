"""
Single Instance Controller & Win32 Window Focus Management for Overwatch.
Ensures only one instance of Overwatch runs at a time and handles
forcing windows (such as shared screen streams) to pop up in the foreground
so the user sees them first.
"""

import sys
import os
from PyQt6.QtCore import QObject, pyqtSignal
from PyQt6.QtNetwork import QLocalServer, QLocalSocket

IPC_SERVER_NAME = "Overwatch_SingleInstance_IPC"


class SingleInstanceController(QObject):
    """Manages single-instance enforcement via local named pipe IPC."""
    activated = pyqtSignal(str)  # emitted when another launch asks this instance to activate

    def __init__(self, server_name=IPC_SERVER_NAME, parent=None):
        super().__init__(parent)
        self.server_name = server_name
        self.server = None

    def is_already_running(self) -> bool:
        """
        Attempts to connect to an existing Overwatch instance.
        If found, sends 'ACTIVATE' command, waits for server ACK, and returns True.
        If not found, creates the IPC server and returns False.
        """
        socket = QLocalSocket()
        socket.connectToServer(self.server_name)
        if socket.waitForConnected(500):
            try:
                socket.write(b"ACTIVATE\n")
                socket.waitForBytesWritten(500)
                # Wait up to 500ms for server to receive and ACK
                socket.waitForReadyRead(500)
                socket.disconnectFromServer()
            except Exception:
                pass
            return True

        # No running instance found - bind this process as the primary server
        QLocalServer.removeServer(self.server_name)
        self.server = QLocalServer(self)
        self.server.newConnection.connect(self._on_new_connection)
        self.server.listen(self.server_name)
        return False

    def _on_new_connection(self):
        while self.server and self.server.hasPendingConnections():
            client_socket = self.server.nextPendingConnection()
            if not client_socket:
                continue
            if client_socket.bytesAvailable() > 0:
                self._read_socket_data(client_socket)
            else:
                client_socket.readyRead.connect(lambda sock=client_socket: self._read_socket_data(sock))

    def _read_socket_data(self, socket):
        try:
            data = bytes(socket.readAll()).decode("utf-8", errors="ignore").strip()
            if "ACTIVATE" in data:
                self.activated.emit("ACTIVATE")
                try:
                    socket.write(b"ACK\n")
                    socket.flush()
                except Exception:
                    pass
        except Exception:
            pass

    def cleanup(self):
        if self.server:
            self.server.close()
            QLocalServer.removeServer(self.server_name)
            self.server = None


def bring_window_to_front(widget_or_hwnd, momentary_topmost=True):
    """
    Forces a window to pop up directly in the user's foreground on Windows,
    bypassing Windows Foreground Lock Timeout so the user sees it first.
    
    If momentary_topmost=True:
    Temporarily brings the window over all background windows, then releases
    the topmost lock so the user can freely interact with other windows normally.
    """
    try:
        # Determine HWND
        if hasattr(widget_or_hwnd, 'winId'):
            hwnd = int(widget_or_hwnd.winId())
        else:
            hwnd = int(widget_or_hwnd)

        if sys.platform == "win32" and hwnd:
            import ctypes
            user32 = ctypes.windll.user32

            SW_RESTORE = 9
            HWND_TOPMOST = -1
            HWND_NOTOPMOST = -2
            SWP_NOMOVE = 0x0002
            SWP_NOSIZE = 0x0001
            SWP_SHOWWINDOW = 0x0040

            # 1. Restore window if minimized
            user32.ShowWindow(hwnd, SW_RESTORE)

            # 2. Attach thread input to bypass Windows Foreground Lock
            current_tid = user32.GetCurrentThreadId()
            fg_hwnd = user32.GetForegroundWindow()
            fg_tid = user32.GetWindowThreadProcessId(fg_hwnd, None) if fg_hwnd else 0

            attached = False
            if fg_tid and fg_tid != current_tid:
                attached = bool(user32.AttachThreadInput(current_tid, fg_tid, True))

            try:
                # 3. Bring directly to top
                if momentary_topmost:
                    user32.SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW)
                
                user32.SetForegroundWindow(hwnd)
                user32.BringWindowToTop(hwnd)

                # 4. Release topmost lock so other windows can normally stack over it if user clicks them
                if momentary_topmost:
                    user32.SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW)

            finally:
                if attached:
                    user32.AttachThreadInput(current_tid, fg_tid, False)

    except Exception as e:
        print(f"[Focus Helper] Error bringing window to front: {e}")
