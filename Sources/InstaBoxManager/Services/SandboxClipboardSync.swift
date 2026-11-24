import AppKit
import Foundation

public enum SandboxClipboardError: LocalizedError, Sendable {
    case emptyLocalClipboard
    case clipboardToolUnavailable
    case displayUnavailable(String)
    case emptyRemoteClipboard
    case installFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyLocalClipboard:
            return "本机剪贴板当前没有可发送的文本内容。"
        case .clipboardToolUnavailable:
            return "沙盒内尚未安装剪贴板工具（xclip / xsel / wl-clipboard），点击「一键安装剪贴板工具」即可自动补齐。"
        case .displayUnavailable(let detail):
            return detail.isEmpty
                ? "剪贴板工具已存在，但当前未检测到运行中的图形桌面（请先点击「启动并连接桌面」）。"
                : "无法连接沙盒图形桌面剪贴板：\(detail)"
        case .emptyRemoteClipboard:
            return "云端沙盒剪贴板当前为空。"
        case .installFailed(let detail):
            return "自动安装剪贴板工具失败：\(detail)"
        }
    }
}

/// Handles bidirectional clipboard synchronization between macOS `NSPasteboard`
/// and remote InstaBox Linux (X11 / Wayland) desktop sessions, including
/// automatic desktop environment discovery and one-click/auto-heal tool installation.
public enum SandboxClipboardSync {
    @MainActor
    public static func readLocalText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    @MainActor
    public static func localChangeCount() -> Int {
        NSPasteboard.general.changeCount
    }

    @MainActor
    @discardableResult
    public static func writeLocalText(_ text: String) -> Int {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        return pb.changeCount
    }

    /// Automatically installs `xclip` (and `wl-clipboard` if Wayland is present) inside the sandbox
    /// across Debian/Ubuntu (`apt-get`), Arch/Omarchy (`pacman`), Alpine (`apk`), and Fedora/RHEL (`dnf`/`yum`).
    public static func installClipboardTools(client: InstaBoxClient, machineId: String) async throws -> String {
        let script = """
        set -e
        SUDO=""
        if [ "$(id -u)" -ne 0 ]; then
          if command -v sudo >/dev/null 2>&1; then
            SUDO="sudo -n"
          fi
        fi

        has_wayland=0
        for sock in /run/user/*/wayland-* /tmp/wayland-* /tmp/runtime-*/wayland-*; do
          if [ -S "$sock" ]; then has_wayland=1; break; fi
        done

        if command -v apt-get >/dev/null 2>&1; then
          export DEBIAN_FRONTEND=noninteractive
          $SUDO apt-get update -qq >/dev/null 2>&1 || true
          if [ "$has_wayland" -eq 1 ]; then
            $SUDO apt-get install -y -qq xclip wl-clipboard >/dev/null 2>&1 || $SUDO apt-get install -y -qq xclip >/dev/null 2>&1
          else
            $SUDO apt-get install -y -qq xclip >/dev/null 2>&1
          fi
          echo "installed:apt"
        elif command -v pacman >/dev/null 2>&1; then
          if [ "$has_wayland" -eq 1 ]; then
            $SUDO pacman -Sy --noconfirm --needed xclip wl-clipboard >/dev/null 2>&1
          else
            $SUDO pacman -Sy --noconfirm --needed xclip >/dev/null 2>&1
          fi
          echo "installed:pacman"
        elif command -v apk >/dev/null 2>&1; then
          $SUDO apk add --no-cache xclip >/dev/null 2>&1
          [ "$has_wayland" -eq 1 ] && $SUDO apk add --no-cache wl-clipboard >/dev/null 2>&1 || true
          echo "installed:apk"
        elif command -v dnf >/dev/null 2>&1; then
          $SUDO dnf install -y -q xclip >/dev/null 2>&1
          [ "$has_wayland" -eq 1 ] && $SUDO dnf install -y -q wl-clipboard >/dev/null 2>&1 || true
          echo "installed:dnf"
        elif command -v yum >/dev/null 2>&1; then
          $SUDO yum install -y -q xclip >/dev/null 2>&1
          echo "installed:yum"
        else
          echo "unsupported_pkg_manager" >&2
          exit 45
        fi
        """

        let result = try await client.execCommand(
            machineId: machineId,
            request: ExecRequest(
                cmd: script,
                timeoutSeconds: 60,
                noHistory: true
            )
        )

        if result.exitCode != 0 {
            let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SandboxClipboardError.installFailed(err.isEmpty ? "Exit \(result.exitCode)" : err)
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Shared shell prelude that auto-discovers active X11 (`DISPLAY`, `XAUTHORITY`)
    /// and Wayland (`XDG_RUNTIME_DIR`, `WAYLAND_DISPLAY`) sessions from sockets and `/proc/*/environ`.
    private static let discoveryPrelude = """
    discover_env() {
      FOUND_DISPLAYS=""
      FOUND_WAYLAND=""
      FOUND_XAUTH=""

      # 1. Inspect running processes for active DISPLAY / WAYLAND_DISPLAY / XAUTHORITY
      for envf in /proc/[0-9]*/environ; do
        [ -r "$envf" ] || continue
        envtxt="$(tr '\\0' '\\n' < "$envf" 2>/dev/null || true)"
        case "$envtxt" in
          *DISPLAY=*|*WAYLAND_DISPLAY=*)
            d="$(printf '%s\\n' "$envtxt" | sed -n 's/^DISPLAY=//p' | head -n 1)"
            xa="$(printf '%s\\n' "$envtxt" | sed -n 's/^XAUTHORITY=//p' | head -n 1)"
            wd="$(printf '%s\\n' "$envtxt" | sed -n 's/^WAYLAND_DISPLAY=//p' | head -n 1)"
            xrd="$(printf '%s\\n' "$envtxt" | sed -n 's/^XDG_RUNTIME_DIR=//p' | head -n 1)"
            if [ -n "$d" ]; then
              case " $FOUND_DISPLAYS " in *" $d "*) ;; *) FOUND_DISPLAYS="$FOUND_DISPLAYS $d" ;; esac
            fi
            if [ -n "$xa" ] && [ -r "$xa" ] && [ -z "$FOUND_XAUTH" ]; then
              FOUND_XAUTH="$xa"
            fi
            if [ -n "$wd" ] && [ -n "$xrd" ] && [ -S "$xrd/$wd" ]; then
              pair="$xrd|$wd"
              case " $FOUND_WAYLAND " in *" $pair "*) ;; *) FOUND_WAYLAND="$FOUND_WAYLAND $pair" ;; esac
            fi
            ;;
        esac
      done

      # 2. Scan standard Wayland socket directories
      for sock in /run/user/*/wayland-* /tmp/wayland-* /tmp/runtime-*/wayland-*; do
        if [ -S "$sock" ]; then
          pair="$(dirname "$sock")|$(basename "$sock")"
          case " $FOUND_WAYLAND " in *" $pair "*) ;; *) FOUND_WAYLAND="$FOUND_WAYLAND $pair" ;; esac
        fi
      done

      # 3. Scan /tmp/.X11-unix/X* sockets
      for xs in /tmp/.X11-unix/X*; do
        if [ -S "$xs" ]; then
          d=":$(basename "$xs" | sed 's/^X//')"
          case " $FOUND_DISPLAYS " in *" $d "*) ;; *) FOUND_DISPLAYS="$FOUND_DISPLAYS $d" ;; esac
        fi
      done
      if [ -n "${DISPLAY:-}" ]; then
        case " $FOUND_DISPLAYS " in *" $DISPLAY "*) ;; *) FOUND_DISPLAYS="$FOUND_DISPLAYS $DISPLAY" ;; esac
      fi

      # 4. Discover XAUTHORITY if not already set
      if [ -z "$FOUND_XAUTH" ]; then
        for xa in "${XAUTHORITY:-}" "$HOME/.Xauthority" /home/*/.Xauthority /root/.Xauthority /tmp/.Xauthority* /run/user/*/Xauthority; do
          if [ -n "$xa" ] && [ -r "$xa" ]; then
            FOUND_XAUTH="$xa"
            break
          fi
        done
      fi
      [ -n "$FOUND_XAUTH" ] && export XAUTHORITY="$FOUND_XAUTH"
    }
    """

    /// Pushes arbitrary UTF-8 text from macOS into the remote sandbox's X11/Wayland clipboard via `stdin`.
    /// When `autoInstallIfMissing` is true, automatically installs `xclip` / `wl-clipboard` and retries once.
    public static func pushToSandbox(
        client: InstaBoxClient,
        machineId: String,
        text: String,
        autoInstallIfMissing: Bool = false
    ) async throws {
        do {
            try await pushToSandboxOnce(client: client, machineId: machineId, text: text)
        } catch SandboxClipboardError.clipboardToolUnavailable where autoInstallIfMissing {
            _ = try await installClipboardTools(client: client, machineId: machineId)
            try await pushToSandboxOnce(client: client, machineId: machineId, text: text)
        }
    }

    private static func pushToSandboxOnce(client: InstaBoxClient, machineId: String, text: String) async throws {
        let script = """
        tmpf="$(mktemp /tmp/.instabox_clip.XXXXXX)"
        trap 'rm -f "$tmpf"' EXIT
        cat > "$tmpf"

        \(discoveryPrelude)
        discover_env

        has_tool=0
        synced=0
        has_display=0

        # 1. Wayland (wl-copy)
        if command -v wl-copy >/dev/null 2>&1; then
          has_tool=1
          for pair in $FOUND_WAYLAND; do
            has_display=1
            xrd="${pair%%|*}"
            wd="${pair#*|}"
            if XDG_RUNTIME_DIR="$xrd" WAYLAND_DISPLAY="$wd" wl-copy < "$tmpf" >/dev/null 2>&1; then
              synced=1
            fi
          done
        fi

        # 2. X11 (xclip / xsel)
        if command -v xclip >/dev/null 2>&1; then
          has_tool=1
          for disp in $FOUND_DISPLAYS; do
            has_display=1
            if DISPLAY="$disp" xclip -selection clipboard -i < "$tmpf" >/dev/null 2>&1; then
              DISPLAY="$disp" xclip -selection primary -i < "$tmpf" >/dev/null 2>&1 || true
              synced=1
            fi
          done
        elif command -v xsel >/dev/null 2>&1; then
          has_tool=1
          for disp in $FOUND_DISPLAYS; do
            has_display=1
            if DISPLAY="$disp" xsel --clipboard --input < "$tmpf" >/dev/null 2>&1; then
              synced=1
            fi
          done
        fi

        if [ "$synced" -eq 1 ]; then
          exit 0
        fi
        if [ "$has_tool" -eq 0 ]; then
          exit 42
        fi
        if [ "$has_display" -eq 0 ]; then
          echo "未发现活跃的 X11/Wayland 显示会话" >&2
          exit 44
        fi
        echo "已检测到工具与显示端($FOUND_DISPLAYS $FOUND_WAYLAND)，但写入剪贴板被拒绝" >&2
        exit 44
        """

        let result = try await client.execCommand(
            machineId: machineId,
            request: ExecRequest(
                cmd: script,
                stdin: text,
                timeoutSeconds: 8,
                noHistory: true
            )
        )

        switch result.exitCode {
        case 0:
            return
        case 42:
            throw SandboxClipboardError.clipboardToolUnavailable
        case 44:
            throw SandboxClipboardError.displayUnavailable(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            let msg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw InstaBoxError.networkError(msg.isEmpty ? "写入云端剪贴板失败 (Exit \(result.exitCode))" : msg)
        }
    }

    /// Reads the current UTF-8 text from the remote sandbox's X11/Wayland clipboard.
    /// When `autoInstallIfMissing` is true, automatically installs `xclip` / `wl-clipboard` and retries once.
    public static func pullFromSandbox(
        client: InstaBoxClient,
        machineId: String,
        autoInstallIfMissing: Bool = false
    ) async throws -> String {
        do {
            return try await pullFromSandboxOnce(client: client, machineId: machineId)
        } catch SandboxClipboardError.clipboardToolUnavailable where autoInstallIfMissing {
            _ = try await installClipboardTools(client: client, machineId: machineId)
            return try await pullFromSandboxOnce(client: client, machineId: machineId)
        }
    }

    private static func pullFromSandboxOnce(client: InstaBoxClient, machineId: String) async throws -> String {
        let script = """
        \(discoveryPrelude)
        discover_env

        has_tool=0
        has_display=0

        # 1. Wayland (wl-paste)
        if command -v wl-paste >/dev/null 2>&1; then
          has_tool=1
          for pair in $FOUND_WAYLAND; do
            has_display=1
            xrd="${pair%%|*}"
            wd="${pair#*|}"
            if XDG_RUNTIME_DIR="$xrd" WAYLAND_DISPLAY="$wd" wl-paste --no-newline 2>/dev/null; then
              exit 0
            fi
          done
        fi

        # 2. X11 (xclip / xsel)
        if command -v xclip >/dev/null 2>&1; then
          has_tool=1
          for disp in $FOUND_DISPLAYS; do
            has_display=1
            if DISPLAY="$disp" xclip -o -selection clipboard 2>/dev/null; then
              exit 0
            fi
          done
        elif command -v xsel >/dev/null 2>&1; then
          has_tool=1
          for disp in $FOUND_DISPLAYS; do
            has_display=1
            if DISPLAY="$disp" xsel --clipboard --output 2>/dev/null; then
              exit 0
            fi
          done
        fi

        if [ "$has_tool" -eq 0 ]; then
          exit 42
        fi
        if [ "$has_display" -eq 0 ]; then
          echo "未发现活跃的 X11/Wayland 显示会话" >&2
          exit 44
        fi
        exit 43
        """

        let result = try await client.execCommand(
            machineId: machineId,
            request: ExecRequest(
                cmd: script,
                timeoutSeconds: 6,
                noHistory: true
            )
        )

        switch result.exitCode {
        case 0:
            if result.stdout.isEmpty {
                throw SandboxClipboardError.emptyRemoteClipboard
            }
            return result.stdout
        case 42:
            throw SandboxClipboardError.clipboardToolUnavailable
        case 43:
            throw SandboxClipboardError.emptyRemoteClipboard
        case 44:
            throw SandboxClipboardError.displayUnavailable(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            let msg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw InstaBoxError.networkError(msg.isEmpty ? "读取云端剪贴板失败 (Exit \(result.exitCode))" : msg)
        }
    }

    /// Encodes a Swift string into a valid JS string literal (including quotes) for `evaluateJavaScript`.
    public static func jsStringLiteral(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [text], options: []),
              let arr = String(data: data, encoding: .utf8),
              arr.count >= 2 else {
            return "\"\""
        }
        return String(arr.dropFirst().dropLast())
    }
}
