from __future__ import annotations

import json
import plistlib
import subprocess
import sys
import threading
from pathlib import Path

from PySide6.QtCore import QEasingCurve, QObject, QPropertyAnimation, QTimer, Qt, QUrl, Slot
from PySide6.QtGui import QDesktopServices, QImageReader, QKeySequence, QShortcut
from PySide6.QtWebChannel import QWebChannel
from PySide6.QtWebEngineCore import QWebEngineScript, QWebEngineSettings
from PySide6.QtWebEngineWidgets import QWebEngineView
from PySide6.QtWidgets import QApplication, QGraphicsOpacityEffect, QLabel, QMessageBox
from preferences import PreferenceStore, build_preloaded_prefs_script

PROJECT_ROOT = Path(__file__).resolve().parent
WIDGET_DIR = PROJECT_ROOT / "." / "widget_export"
INFO_PLIST = WIDGET_DIR / "Info.plist"
JS_DIR = PROJECT_ROOT / "js"
PREFS_PATH = PROJECT_ROOT / "prefs.json"


def parse_dimension_optional(value: object) -> int | None:
    if isinstance(value, (int, float)):
        parsed = int(round(float(value)))
        return parsed if parsed > 0 else None
    if isinstance(value, str):
        cleaned = value.strip().lower().replace("px", "")
        if not cleaned:
            return None
        try:
            parsed = int(round(float(cleaned)))
            return parsed if parsed > 0 else None
        except ValueError:
            return None
    return None


def read_default_image_size(widget_dir: Path) -> tuple[int, int] | None:
    default_png = widget_dir / "Default.png"
    if not default_png.exists():
        return None

    reader = QImageReader(str(default_png))
    size = reader.size()
    if not size.isValid():
        return None

    width = size.width()
    height = size.height()
    if width <= 0 or height <= 0:
        return None
    return (width, height)


def load_widget_config() -> tuple[Path, int, int, str]:
    if not INFO_PLIST.exists():
        raise FileNotFoundError(f"Missing Info.plist at {INFO_PLIST}")

    with INFO_PLIST.open("rb") as f:
        info = plistlib.load(f)

    entry = str(info.get("MainHTML", "index.html"))
    width = parse_dimension_optional(info.get("Width"))
    height = parse_dimension_optional(info.get("Height"))

    if width is None or height is None:
        default_image_size = read_default_image_size(WIDGET_DIR)
        if default_image_size is not None:
            if width is None:
                width = default_image_size[0]
            if height is None:
                height = default_image_size[1]

    width = width if width is not None else 800
    height = height if height is not None else 600
    widget_name = str(
        info.get("CFBundleDisplayName")
        or info.get("CFBundleName")
        or info.get("CFBundleIdentifier")
        or "Widget"
    )
    entry_path = (WIDGET_DIR / entry).resolve()
    if not entry_path.exists():
        raise FileNotFoundError(f"Widget entrypoint not found: {entry_path}")

    return entry_path, width, height, widget_name


class NativeBridge(QObject):
    def __init__(self, preference_store: PreferenceStore, web_view: QWebEngineView, widget_name: str) -> None:
        super().__init__()
        self.preference_store = preference_store
        self.web_view = web_view
        self.widget_name = widget_name
        self.transition_direction: str | None = None
        self.transition_overlay: QLabel | None = None
        self.transition_fade_animation: QPropertyAnimation | None = None
        self.pending_resize_target: tuple[int, int] | None = None
        self.last_applied_resize_target: tuple[int, int] | None = None
        self.resize_settle_timer = QTimer(self)
        self.resize_settle_timer.setSingleShot(True)
        self.resize_settle_timer.timeout.connect(self._reapply_pending_resize)
        self.system_processes: dict[str, subprocess.Popen[str]] = {}
        self.system_lock = threading.Lock()

    @Slot(str, str, result=str)
    def postMessage(self, handler: str, payload: str) -> str:
        try:
            data = json.loads(payload) if payload else None
        except json.JSONDecodeError:
            data = payload

        if handler == "openURL":
            url = data if isinstance(data, str) else (data or {}).get("url")
            if url:
                opened = QDesktopServices.openUrl(QUrl(str(url)))
                return json.dumps({"ok": bool(opened)})
            return json.dumps({"ok": False, "error": "missing URL"})

        if handler == "setPreferenceForKey":
            if not isinstance(data, dict):
                return json.dumps({"ok": False, "error": "invalid payload"})
            key = data.get("key")
            if not isinstance(key, str) or not key:
                return json.dumps({"ok": False, "error": "missing key"})
            value = data.get("value")
            self.preference_store.set(key, value)
            return json.dumps({"ok": True})

        if handler == "getAllPreferences":
            prefs = self.preference_store.get_all()
            return json.dumps({"ok": True, "preferences": prefs})

        if handler == "prepareForTransition":
            self.transition_direction = data if isinstance(data, str) else None
            self._freeze_view_for_transition()
            self.web_view.setEnabled(False)
            return json.dumps({"ok": True})

        if handler == "performTransition":
            self.web_view.setEnabled(True)
            self._run_flip_transition()
            self._unfreeze_view_with_fade()
            self.transition_direction = None
            return json.dumps({"ok": True})

        if handler == "resizeTo":
            if not isinstance(data, dict):
                return json.dumps({"ok": False, "error": "invalid payload"})
            width = parse_dimension_optional(data.get("width"))
            height = parse_dimension_optional(data.get("height"))
            if width is None or height is None:
                return json.dumps({"ok": False, "error": "missing width or height"})
            self._request_resize(width, height)
            return json.dumps({"ok": True, "width": width, "height": height})

        if handler == "systemCommand":
            return self._handle_system_command(data)

        return json.dumps(
            {
                "ok": False,
                "error": f"'{handler}' is not implemented in this runner yet",
            }
        )

    def _ensure_transition_overlay(self) -> QLabel:
        if self.transition_overlay is None:
            overlay = QLabel(self.web_view)
            overlay.setObjectName("widgetTransitionOverlay")
            overlay.setAttribute(Qt.WidgetAttribute.WA_TransparentForMouseEvents, True)
            overlay.hide()

            effect = QGraphicsOpacityEffect(overlay)
            effect.setOpacity(1.0)
            overlay.setGraphicsEffect(effect)
            self.transition_overlay = overlay

        return self.transition_overlay

    def _freeze_view_for_transition(self) -> None:
        overlay = self._ensure_transition_overlay()
        overlay.setGeometry(self.web_view.rect())
        overlay.setPixmap(self.web_view.grab())
        effect = overlay.graphicsEffect()
        if isinstance(effect, QGraphicsOpacityEffect):
            effect.setOpacity(1.0)
        overlay.show()
        overlay.raise_()

    def _unfreeze_view_with_fade(self) -> None:
        overlay = self.transition_overlay
        if overlay is None or not overlay.isVisible():
            return

        effect = overlay.graphicsEffect()
        if not isinstance(effect, QGraphicsOpacityEffect):
            overlay.hide()
            return

        animation = QPropertyAnimation(effect, b"opacity", self)
        animation.setDuration(480)
        animation.setStartValue(1.0)
        animation.setEndValue(0.0)
        animation.setEasingCurve(QEasingCurve.Type.OutCubic)

        def finish() -> None:
            overlay.hide()

        animation.finished.connect(finish)
        self.transition_fade_animation = animation
        animation.start()

    def _run_flip_transition(self) -> None:
        direction = (self.transition_direction or "").strip().lower()
        start_angle = -90
        if direction in {"toback", "to_back", "back", "to back"}:
            start_angle = 90

        animation_js = f"""
(function () {{
  function done() {{
    try {{
      if (typeof window.onshow === "function") window.onshow();
    }} catch (e) {{}}
  }}

  try {{
    var root = document.body || document.documentElement;
    if (!root) {{
      done();
      return;
    }}

    var from = "perspective(1200px) rotateY({start_angle}deg)";
    var to = "perspective(1200px) rotateY(0deg)";

    if (typeof root.animate === "function") {{
      var anim = root.animate(
        [
          {{ transform: from, filter: "brightness(0.9)" }},
          {{ transform: to, filter: "brightness(1)" }}
        ],
        {{
          duration: 560,
          easing: "cubic-bezier(0.22, 0.61, 0.36, 1)",
          fill: "none"
        }}
      );
      anim.onfinish = done;
      anim.oncancel = done;
      return;
    }}

    done();
  }} catch (error) {{
    done();
  }}
}})();
"""
        self.web_view.page().runJavaScript(animation_js)

    def _request_resize(self, width: int, height: int) -> None:
        target = (max(1, width), max(1, height))
        self.pending_resize_target = target

        if self.last_applied_resize_target == target and self.web_view.size().width() == target[0] and self.web_view.size().height() == target[1]:
            self.resize_settle_timer.start(120)
            return

        self._apply_resize_target(target)
        self.resize_settle_timer.start(120)

    def _reapply_pending_resize(self) -> None:
        if self.pending_resize_target is None:
            return
        self._apply_resize_target(self.pending_resize_target)

    def _apply_resize_target(self, target: tuple[int, int]) -> None:
        width, height = target
        self.web_view.setMinimumSize(1, 1)
        self.web_view.setMaximumSize(16777215, 16777215)
        self.web_view.resize(width, height)
        self.web_view.setMinimumSize(width, height)
        self.web_view.setMaximumSize(width, height)
        self.web_view.updateGeometry()
        self.last_applied_resize_target = target

    def _handle_system_command(self, data: object) -> str:
        if not isinstance(data, dict):
            return json.dumps({"ok": False, "error": "invalid payload"})

        action = data.get("action")
        token = data.get("token")
        if not isinstance(action, str) or not isinstance(token, str) or not token:
            return json.dumps({"ok": False, "error": "missing action or token"})

        if action == "cancel":
            canceled = self._cancel_system_command(token)
            return json.dumps({"ok": bool(canceled)})

        if action != "start":
            return json.dumps({"ok": False, "error": f"unsupported action: {action}"})

        command = data.get("command")
        if not isinstance(command, str) or not command.strip():
            return json.dumps({"ok": False, "error": "missing command"})

        if not self._prompt_allow_system_command(command):
            self._emit_system_output(
                token=token,
                text="Command denied by user.",
                done=True,
                status=126,
            )
            return json.dumps({"ok": False, "denied": True})

        self._start_system_command(token, command)
        return json.dumps({"ok": True})

    def _prompt_allow_system_command(self, command: str) -> bool:
        prompt = QMessageBox(self.web_view)
        prompt.setWindowTitle("Allow System Command")
        prompt.setIcon(QMessageBox.Icon.Warning)
        prompt.setText(f"'{self.widget_name}' wants to run a system command.")
        informative = command
        if sys.platform != "darwin":
            informative += (
                "\n\nNote: This command may not work as Dashboard widgets were originally designed for OS X."
            )
        prompt.setInformativeText(informative)
        prompt.setStandardButtons(QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
        prompt.setDefaultButton(QMessageBox.StandardButton.No)
        choice = prompt.exec()
        return choice == int(QMessageBox.StandardButton.Yes)

    def _start_system_command(self, token: str, command: str) -> None:
        with self.system_lock:
            existing = self.system_processes.pop(token, None)
            if existing is not None and existing.poll() is None:
                existing.terminate()

        try:
            if sys.platform.startswith("win"):
                process = subprocess.Popen(
                    command,
                    shell=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                )
            else:
                process = subprocess.Popen(
                    ["/bin/zsh", "-lc", command],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1,
                )
        except Exception as error:
            self._emit_system_output(token=token, text=str(error), done=True, status=127)
            return

        with self.system_lock:
            self.system_processes[token] = process

        worker = threading.Thread(
            target=self._stream_system_command,
            args=(token, process),
            daemon=True,
        )
        worker.start()

    def _stream_system_command(self, token: str, process: subprocess.Popen[str]) -> None:
        chunks: list[str] = []

        try:
            if process.stdout is not None:
                for line in process.stdout:
                    chunks.append(line)
                    self._emit_system_output(token=token, text=line, done=False, status=0)
        finally:
            return_code = process.wait()
            with self.system_lock:
                current = self.system_processes.get(token)
                if current is process:
                    self.system_processes.pop(token, None)

            final_output = "".join(chunks)
            self._emit_system_output(
                token=token,
                text=final_output,
                done=True,
                status=return_code,
            )

    def _cancel_system_command(self, token: str) -> bool:
        with self.system_lock:
            process = self.system_processes.get(token)
        if process is None:
            return False

        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
        return True

    def _emit_system_output(self, token: str, text: str, done: bool, status: int) -> None:
        token_js = json.dumps(token)
        text_js = json.dumps(text)
        done_js = "true" if done else "false"
        status_js = json.dumps(int(status))
        js = f"window.__handleSystemOutput({token_js}, {text_js}, {done_js}, {status_js});"
        QTimer.singleShot(0, lambda: self.web_view.page().runJavaScript(js))


def load_script_source(filename: str) -> str:
    script_path = JS_DIR / filename
    if not script_path.exists():
        raise FileNotFoundError(f"Missing script file: {script_path}")
    return script_path.read_text(encoding="utf-8")


def add_bootstrap_script(view: QWebEngineView, preferences: dict[str, object]) -> None:
    bridge_bootstrap_js = load_script_source("bridge_bootstrap.js")
    drag_guard_js = load_script_source("drag_guard.js")
    prefs_sync_js = load_script_source("prefs_sync.js")
    preloaded_prefs_js = build_preloaded_prefs_script(preferences)

    preload_script = QWebEngineScript()
    preload_script.setName("widget_python_runner_preloaded_prefs")
    preload_script.setInjectionPoint(QWebEngineScript.InjectionPoint.DocumentCreation)
    preload_script.setRunsOnSubFrames(True)
    preload_script.setWorldId(QWebEngineScript.ScriptWorldId.MainWorld)
    preload_script.setSourceCode(preloaded_prefs_js)
    view.page().scripts().insert(preload_script)

    script = QWebEngineScript()
    script.setName("widget_python_runner_bridge")
    script.setInjectionPoint(QWebEngineScript.InjectionPoint.DocumentCreation)
    script.setRunsOnSubFrames(True)
    script.setWorldId(QWebEngineScript.ScriptWorldId.MainWorld)
    script.setSourceCode(bridge_bootstrap_js)
    view.page().scripts().insert(script)

    drag_script = QWebEngineScript()
    drag_script.setName("widget_python_runner_drag_guard")
    drag_script.setInjectionPoint(QWebEngineScript.InjectionPoint.DocumentReady)
    drag_script.setRunsOnSubFrames(True)
    drag_script.setWorldId(QWebEngineScript.ScriptWorldId.MainWorld)
    drag_script.setSourceCode(drag_guard_js)
    view.page().scripts().insert(drag_script)

    prefs_script = QWebEngineScript()
    prefs_script.setName("widget_python_runner_prefs_sync")
    prefs_script.setInjectionPoint(QWebEngineScript.InjectionPoint.DocumentReady)
    prefs_script.setRunsOnSubFrames(True)
    prefs_script.setWorldId(QWebEngineScript.ScriptWorldId.MainWorld)
    prefs_script.setSourceCode(prefs_sync_js)
    view.page().scripts().insert(prefs_script)


def attach_devtools(view: QWebEngineView) -> None:
    devtools_view = QWebEngineView()
    devtools_view.setWindowTitle("DevTools")
    devtools_view.resize(1200, 800)
    view.page().setDevToolsPage(devtools_view.page())

    def toggle_devtools() -> None:
        if devtools_view.isVisible():
            devtools_view.hide()
            return
        devtools_view.show()
        devtools_view.raise_()
        devtools_view.activateWindow()

    shortcuts: list[QShortcut] = []
    for sequence in ("F12", "Ctrl+Shift+I", "Meta+Alt+I"):
        shortcut = QShortcut(QKeySequence(sequence), view)
        shortcut.activated.connect(toggle_devtools)
        shortcuts.append(shortcut)

    view._devtools_view = devtools_view
    view._devtools_shortcuts = shortcuts


def main() -> int:
    entry_path, width, height, widget_name = load_widget_config()
    preference_store = PreferenceStore(PREFS_PATH)

    app = QApplication(sys.argv)
    view = QWebEngineView()
    view.setWindowTitle(f"{widget_name} - WPT")
    view.resize(width, height)
    view.setMinimumSize(width, height)
    view.setMaximumSize(width, height)
    view.setAcceptDrops(False)

    settings = view.settings()
    settings.setAttribute(
        QWebEngineSettings.WebAttribute.LocalContentCanAccessFileUrls, True
    )
    settings.setAttribute(
        QWebEngineSettings.WebAttribute.LocalContentCanAccessRemoteUrls, True
    )

    channel = QWebChannel(view.page())
    bridge = NativeBridge(preference_store, view, widget_name)
    channel.registerObject("qtBridge", bridge)
    view.page().setWebChannel(channel)
    add_bootstrap_script(view, preference_store.get_all())
    attach_devtools(view)

    view.load(QUrl.fromLocalFile(str(entry_path)))
    view.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())