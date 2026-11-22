import AppKit
import SwiftUI
import WebKit

/// Custom `WKWebView` subclass that intercepts macOS `⌘C` / `⌘V` shortcuts while focused
/// so native clipboard synchronization fires immediately alongside web desktop events.
final class ClipboardAwareWebView: WKWebView {
    var onCmdPaste: (() -> Void)?
    var onCmdCopy: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() {
            if key == "v" {
                onCmdPaste?()
            } else if key == "c" {
                onCmdCopy?()
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Embedded Remote Desktop `WKWebView` with a native macOS `NSPasteboard` bidirectional bridge:
/// - Shims `navigator.clipboard.readText / writeText / read / write` directly to `NSPasteboard.general`
/// - Grants `navigator.permissions.query({ name: 'clipboard-read' | 'clipboard-write' })`
/// - Bridges DOM `copy` events and exposes instant Mac ⇄ Remote hooks.
struct RemoteDesktopWebView: NSViewRepresentable {
    let url: URL
    var clipboardEnabled: Bool = true
    var incomingMacText: String? = nil
    var incomingMacRevision: Int = 0
    var onRemoteCopiedText: ((String) -> Void)? = nil
    var onCmdPasteTriggered: (() -> Void)? = nil
    var onCmdCopyTriggered: (() -> Void)? = nil

    static let messageHandlerName = "instaboxClipboard"

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ClipboardAwareWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: Self.messageHandlerName)
        let bridgeScript = WKUserScript(
            source: Self.clipboardBridgeJavaScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        userContentController.addUserScript(bridgeScript)
        config.userContentController = userContentController

        let webView = ClipboardAwareWebView(frame: .zero, configuration: config)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.onCmdPaste = { [weak coordinator = context.coordinator] in
            coordinator?.handleCmdPaste()
        }
        webView.onCmdCopy = { [weak coordinator = context.coordinator] in
            coordinator?.handleCmdCopy()
        }

        context.coordinator.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: ClipboardAwareWebView, context: Context) {
        context.coordinator.parent = self
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
        if clipboardEnabled,
           incomingMacRevision != context.coordinator.lastPushedRevision,
           let text = incomingMacText {
            context.coordinator.lastPushedRevision = incomingMacRevision
            context.coordinator.pushHostClipboardToWebView(text)
        }
    }

    static func dismantleNSView(_ nsView: ClipboardAwareWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: Self.messageHandlerName)
        nsView.onCmdPaste = nil
        nsView.onCmdCopy = nil
        coordinator.webView = nil
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
        var parent: RemoteDesktopWebView
        weak var webView: ClipboardAwareWebView?
        var lastPushedRevision: Int = -1

        init(parent: RemoteDesktopWebView) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == RemoteDesktopWebView.messageHandlerName,
                  let body = message.body as? [String: Any],
                  let action = body["action"] as? String else {
                return
            }

            Task { @MainActor [weak self] in
                guard let self, self.parent.clipboardEnabled else { return }
                switch action {
                case "write":
                    if let text = body["text"] as? String, !text.isEmpty {
                        _ = SandboxClipboardSync.writeLocalText(text)
                        self.parent.onRemoteCopiedText?(text)
                    }
                case "read":
                    let requestId = body["id"] as? String ?? ""
                    let text = SandboxClipboardSync.readLocalText() ?? ""
                    let jsId = SandboxClipboardSync.jsStringLiteral(requestId)
                    let jsText = SandboxClipboardSync.jsStringLiteral(text)
                    self.webView?.evaluateJavaScript("window.__instaboxResolveClipboardRead && window.__instaboxResolveClipboardRead(\(jsId), \(jsText));", completionHandler: nil)
                default:
                    break
                }
            }
        }

        @MainActor
        func pushHostClipboardToWebView(_ text: String) {
            let jsText = SandboxClipboardSync.jsStringLiteral(text)
            webView?.evaluateJavaScript("window.__instaboxReceiveHostClipboard && window.__instaboxReceiveHostClipboard(\(jsText));", completionHandler: nil)
        }

        @MainActor
        func handleCmdPaste() {
            guard parent.clipboardEnabled else { return }
            if let text = SandboxClipboardSync.readLocalText(), !text.isEmpty {
                pushHostClipboardToWebView(text)
            }
            parent.onCmdPasteTriggered?()
        }

        @MainActor
        func handleCmdCopy() {
            guard parent.clipboardEnabled else { return }
            parent.onCmdCopyTriggered?()
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let targetURL = navigationAction.request.url {
                NSWorkspace.shared.open(targetURL)
            }
            return nil
        }
    }

    // MARK: - Injected Native Clipboard Bridge Script

    private static let clipboardBridgeJavaScript = #"""
    (function() {
      if (window.__instaboxClipboardBridged) return;
      window.__instaboxClipboardBridged = true;

      const handler = () => window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.instaboxClipboard;
      const pendingReads = new Map();
      let reqCounter = 0;
      let cachedHostText = "";

      window.__instaboxResolveClipboardRead = function(id, text) {
        const value = typeof text === "string" ? text : "";
        cachedHostText = value;
        const resolver = pendingReads.get(id);
        if (resolver) {
          pendingReads.delete(id);
          resolver(value);
        }
      };

      window.__instaboxReceiveHostClipboard = function(text) {
        if (typeof text !== "string") return;
        cachedHostText = text;
        try {
          window.dispatchEvent(new CustomEvent("instabox-host-clipboard", { detail: { text } }));
        } catch (_) {}
      };

      function nativeWriteText(text) {
        const str = String(text == null ? "" : text);
        cachedHostText = str;
        const h = handler();
        if (h) {
          h.postMessage({ action: "write", text: str });
        }
        return Promise.resolve();
      }

      function nativeReadText() {
        const h = handler();
        if (!h) return Promise.resolve(cachedHostText);
        return new Promise((resolve) => {
          const id = "clip_" + (++reqCounter) + "_" + Date.now();
          pendingReads.set(id, resolve);
          h.postMessage({ action: "read", id: id });
          setTimeout(() => {
            if (pendingReads.has(id)) {
              pendingReads.delete(id);
              resolve(cachedHostText);
            }
          }, 1500);
        });
      }

      const bridgedClipboard = {
        writeText: nativeWriteText,
        readText: nativeReadText,
        write: async function(items) {
          if (!Array.isArray(items)) return;
          for (const item of items) {
            if (item && typeof item.getType === "function" && Array.isArray(item.types) && item.types.includes("text/plain")) {
              const blob = await item.getType("text/plain");
              const txt = await blob.text();
              await nativeWriteText(txt);
              return;
            }
          }
        },
        read: async function() {
          const txt = await nativeReadText();
          if (typeof ClipboardItem !== "undefined") {
            return [new ClipboardItem({ "text/plain": new Blob([txt], { type: "text/plain" }) })];
          }
          return [];
        },
        addEventListener: function() {},
        removeEventListener: function() {},
        dispatchEvent: function() { return true; }
      };

      try {
        Object.defineProperty(navigator, "clipboard", {
          get: () => bridgedClipboard,
          configurable: true
        });
      } catch (_) {
        try {
          if (navigator.clipboard) {
            navigator.clipboard.writeText = nativeWriteText;
            navigator.clipboard.readText = nativeReadText;
            navigator.clipboard.write = bridgedClipboard.write;
            navigator.clipboard.read = bridgedClipboard.read;
          }
        } catch (__) {}
      }

      if (navigator.permissions && typeof navigator.permissions.query === "function") {
        const origQuery = navigator.permissions.query.bind(navigator.permissions);
        navigator.permissions.query = function(desc) {
          if (desc && (desc.name === "clipboard-read" || desc.name === "clipboard-write")) {
            return Promise.resolve({
              state: "granted",
              onchange: null,
              addEventListener: function() {},
              removeEventListener: function() {},
              dispatchEvent: function() { return true; }
            });
          }
          return origQuery(desc);
        };
      }

      document.addEventListener("copy", function(e) {
        try {
          const dt = e.clipboardData && e.clipboardData.getData ? e.clipboardData.getData("text/plain") : "";
          const sel = window.getSelection ? window.getSelection().toString() : "";
          const text = dt || sel;
          if (text) nativeWriteText(text);
        } catch (_) {}
      }, false);
    })();
    """#
}
