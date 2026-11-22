import AppKit
import Foundation

public enum SandboxClipboardError: LocalizedError, Sendable {
    case emptyLocalClipboard
    case clipboardToolUnavailable
    case emptyRemoteClipboard

    public var errorDescription: String? {
        switch self {
        case .emptyLocalClipboard:
            return "本机剪贴板当前没有可发送的文本内容。"
        case .clipboardToolUnavailable:
            return "沙盒内未检测到 X11/Wayland 剪贴板工具（xclip / xsel / wl-clipboard），远程桌面网页桥接仍可直接同步。"
        case .emptyRemoteClipboard:
            return "云端沙盒剪贴板当前为空。"
        }
    }
}

/// Handles bidirectional clipboard synchronization between macOS `NSPasteboard`
/// and remote InstaBox Linux (X11 / Wayland) desktop sessions.
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

    /// Pushes arbitrary UTF-8 text from macOS into the remote sandbox's X11/Wayland clipboard via `stdin`
    /// (zero shell-escaping hazards, `noHistory: true` so it never pollutes command history).
    public static func pushToSandbox(client: InstaBoxClient, machineId: String, text: String) async throws {
        let script = """
        set -e
        tmpf="$(mktemp /tmp/.instabox_clip.XXXXXX)"
        trap 'rm -f "$tmpf"' EXIT
        cat > "$tmpf"

        synced=0

        if command -v wl-copy >/dev/null 2>&1; then
          for sock in /run/user/*/wayland-* /tmp/wayland-*; do
            if [ -S "$sock" ]; then
              XDG_RUNTIME_DIR="$(dirname "$sock")" WAYLAND_DISPLAY="$(basename "$sock")" wl-copy < "$tmpf" >/dev/null 2>&1 && synced=1 && break
            fi
          done
        fi

        if [ -z "${XAUTHORITY:-}" ]; then
          for xa in "$HOME/.Xauthority" /home/*/.Xauthority /root/.Xauthority; do
            if [ -r "$xa" ]; then
              export XAUTHORITY="$xa"
              break
            fi
          done
        fi

        disp=""
        for xs in /tmp/.X11-unix/X*; do
          if [ -S "$xs" ]; then
            disp=":$(basename "$xs" | sed 's/^X//')"
            break
          fi
        done
        [ -z "$disp" ] && disp="${DISPLAY:-:0}"

        if command -v xclip >/dev/null 2>&1; then
          DISPLAY="$disp" xclip -selection clipboard -i < "$tmpf" >/dev/null 2>&1 && synced=1
          DISPLAY="$disp" xclip -selection primary -i < "$tmpf" >/dev/null 2>&1 || true
        elif command -v xsel >/dev/null 2>&1; then
          DISPLAY="$disp" xsel --clipboard --input < "$tmpf" >/dev/null 2>&1 && synced=1
        fi

        if [ "$synced" -eq 1 ]; then
          exit 0
        fi
        exit 42
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

        if result.exitCode == 42 {
            throw SandboxClipboardError.clipboardToolUnavailable
        }
        if result.exitCode != 0 {
            let msg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw InstaBoxError.networkError(msg.isEmpty ? "写入云端剪贴板失败 (Exit \(result.exitCode))" : msg)
        }
    }

    /// Reads the current UTF-8 text from the remote sandbox's X11/Wayland clipboard.
    public static func pullFromSandbox(client: InstaBoxClient, machineId: String) async throws -> String {
        let script = """
        if command -v wl-paste >/dev/null 2>&1; then
          for sock in /run/user/*/wayland-* /tmp/wayland-*; do
            if [ -S "$sock" ]; then
              if XDG_RUNTIME_DIR="$(dirname "$sock")" WAYLAND_DISPLAY="$(basename "$sock")" wl-paste --no-newline 2>/dev/null; then
                exit 0
              fi
            fi
          done
        fi

        if [ -z "${XAUTHORITY:-}" ]; then
          for xa in "$HOME/.Xauthority" /home/*/.Xauthority /root/.Xauthority; do
            if [ -r "$xa" ]; then
              export XAUTHORITY="$xa"
              break
            fi
          done
        fi

        disp=""
        for xs in /tmp/.X11-unix/X*; do
          if [ -S "$xs" ]; then
            disp=":$(basename "$xs" | sed 's/^X//')"
            break
          fi
        done
        [ -z "$disp" ] && disp="${DISPLAY:-:0}"

        if command -v xclip >/dev/null 2>&1; then
          DISPLAY="$disp" xclip -o -selection clipboard 2>/dev/null && exit 0
          exit 43
        elif command -v xsel >/dev/null 2>&1; then
          DISPLAY="$disp" xsel --clipboard --output 2>/dev/null && exit 0
          exit 43
        fi
        exit 42
        """

        let result = try await client.execCommand(
            machineId: machineId,
            request: ExecRequest(
                cmd: script,
                timeoutSeconds: 6,
                noHistory: true
            )
        )

        if result.exitCode == 42 {
            throw SandboxClipboardError.clipboardToolUnavailable
        }
        if result.exitCode == 43 || result.stdout.isEmpty {
            throw SandboxClipboardError.emptyRemoteClipboard
        }
        if result.exitCode != 0 {
            let msg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw InstaBoxError.networkError(msg.isEmpty ? "读取云端剪贴板失败 (Exit \(result.exitCode))" : msg)
        }
        return result.stdout
    }

    /// Encodes a Swift string into a valid JS string literal (including quotes) for `evaluateJavaScript`.
    public static func jsStringLiteral(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [text], options: []),
              let arr = String(data: data, encoding: .utf8),
              arr.count >= 2 else {
            return "\"\""
        }
        // Strip outer '[' and ']' to obtain a properly escaped JSON string literal
        return String(arr.dropFirst().dropLast())
    }
}
