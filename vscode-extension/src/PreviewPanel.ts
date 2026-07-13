import * as vscode from 'vscode';
import { LanguageClient } from 'vscode-languageclient/node';

export class PreviewPanel {
    public static readonly viewType = 'gdiagram.preview';

    private static panels: Map<string, PreviewPanel> = new Map();
    private static renderTimers: Map<string, NodeJS.Timeout> = new Map();

    private readonly panel: vscode.WebviewPanel;
    private readonly extensionUri: vscode.Uri;
    private documentUri: string;
    private disposables: vscode.Disposable[] = [];

    public static createOrShow(
        extensionUri: vscode.Uri,
        document: vscode.TextDocument,
        client: LanguageClient
    ) {
        const uri = document.uri.toString();
        const existing = PreviewPanel.panels.get(uri);
        if (existing) {
            existing.panel.reveal(vscode.ViewColumn.Beside);
            return;
        }

        const panel = vscode.window.createWebviewPanel(
            PreviewPanel.viewType,
            `Preview: ${getFileName(document.fileName)}`,
            vscode.ViewColumn.Beside,
            {
                enableScripts: true,
                retainContextWhenHidden: true,
                localResourceRoots: [
                    vscode.Uri.joinPath(extensionUri, 'media'),
                ],
            }
        );

        const previewPanel = new PreviewPanel(panel, extensionUri, uri);
        PreviewPanel.panels.set(uri, previewPanel);

        PreviewPanel.requestRender(uri, client);
    }

    public static updateSvg(uri: string, svg: string) {
        const panel = PreviewPanel.panels.get(uri);
        if (panel) {
            panel.panel.webview.postMessage({ type: 'svgUpdate', svg });
        }
    }

    public static showError(uri: string, message: string) {
        const panel = PreviewPanel.panels.get(uri);
        if (panel) {
            panel.panel.webview.postMessage({ type: 'error', message });
        }
    }

    public static requestRender(uri: string, client: LanguageClient) {
        const existing = PreviewPanel.renderTimers.get(uri);
        if (existing) {
            clearTimeout(existing);
        }

        const timer = setTimeout(() => {
            PreviewPanel.renderTimers.delete(uri);
            const panel = PreviewPanel.panels.get(uri);
            if (panel) {
                panel.panel.webview.postMessage({ type: 'loading' });
            }
            client
                .sendRequest('gdiagram/renderSvg', { uri })
                .then((result: unknown) => {
                    const res = result as { svg?: string; error?: string };
                    if (res && res.svg) {
                        PreviewPanel.updateSvg(uri, res.svg);
                    } else if (res && res.error) {
                        PreviewPanel.showError(uri, res.error);
                    }
                })
                .catch((err: Error) => {
                    PreviewPanel.showError(uri, err.message);
                });
        }, 300);

        PreviewPanel.renderTimers.set(uri, timer);
    }

    private constructor(
        panel: vscode.WebviewPanel,
        extensionUri: vscode.Uri,
        documentUri: string
    ) {
        this.panel = panel;
        this.extensionUri = extensionUri;
        this.documentUri = documentUri;

        this.panel.webview.html = this.getHtmlContent();

        this.panel.webview.onDidReceiveMessage(
            (message) => {
                if (message.type === 'clickElement' && message.line) {
                    this.navigateToSource(message.line);
                }
            },
            null,
            this.disposables
        );

        this.panel.onDidDispose(() => this.dispose(), null, this.disposables);
    }

    private navigateToSource(line: number) {
        const uri = vscode.Uri.parse(this.documentUri);
        vscode.workspace.openTextDocument(uri).then((doc) => {
            vscode.window.showTextDocument(doc, vscode.ViewColumn.One).then(
                (editor) => {
                    const lineIndex = Math.max(0, line - 1);
                    const range = new vscode.Range(lineIndex, 0, lineIndex, 0);
                    editor.selection = new vscode.Selection(
                        range.start,
                        range.start
                    );
                    editor.revealRange(
                        range,
                        vscode.TextEditorRevealType.InCenter
                    );
                }
            );
        });
    }

    private dispose() {
        PreviewPanel.panels.delete(this.documentUri);
        const timer = PreviewPanel.renderTimers.get(this.documentUri);
        if (timer) {
            clearTimeout(timer);
            PreviewPanel.renderTimers.delete(this.documentUri);
        }
        this.panel.dispose();
        while (this.disposables.length) {
            const d = this.disposables.pop();
            if (d) {
                d.dispose();
            }
        }
    }

    private getHtmlContent(): string {
        const nonce = getNonce();
        return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="Content-Security-Policy"
          content="default-src 'none'; img-src data: vscode-resource:; style-src 'nonce-${nonce}'; script-src 'nonce-${nonce}';">
    <style nonce="${nonce}">
        :root {
            --bg: var(--vscode-editor-background, #1e1e1e);
            --fg: var(--vscode-editor-foreground, #cccccc);
            --border: var(--vscode-panel-border, #444);
            --accent: var(--vscode-focusBorder, #007acc);
            --error-bg: var(--vscode-inputValidation-errorBackground, #5a1d1d);
            --error-fg: var(--vscode-errorForeground, #f48771);
            --badge-bg: var(--vscode-badge-background, #4d4d4d);
            --badge-fg: var(--vscode-badge-foreground, #ffffff);
        }

        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            background: var(--bg);
            color: var(--fg);
            font-family: var(--vscode-font-family, sans-serif);
            font-size: var(--vscode-font-size, 13px);
            overflow: hidden;
            width: 100vw;
            height: 100vh;
        }

        #toolbar {
            position: fixed;
            top: 8px;
            right: 8px;
            z-index: 100;
            display: flex;
            gap: 4px;
            background: var(--badge-bg);
            border-radius: 4px;
            padding: 2px;
            opacity: 0.7;
            transition: opacity 0.2s;
        }

        #toolbar:hover {
            opacity: 1;
        }

        #toolbar button {
            background: transparent;
            border: none;
            color: var(--badge-fg);
            cursor: pointer;
            padding: 4px 8px;
            border-radius: 3px;
            font-size: 13px;
            line-height: 1;
        }

        #toolbar button:hover {
            background: var(--accent);
        }

        #zoom-label {
            color: var(--badge-fg);
            padding: 4px 6px;
            font-size: 11px;
            min-width: 40px;
            text-align: center;
            line-height: 1.4;
        }

        #viewport {
            width: 100%;
            height: 100%;
            overflow: hidden;
            cursor: grab;
            position: relative;
        }

        #viewport.dragging {
            cursor: grabbing;
        }

        #svg-container {
            transform-origin: 0 0;
            position: absolute;
            top: 0;
            left: 0;
        }

        #svg-container svg {
            display: block;
        }

        #svg-container svg .node,
        #svg-container svg .cluster,
        #svg-container svg .edge {
            cursor: pointer;
        }

        #svg-container svg .node:hover,
        #svg-container svg .cluster:hover {
            filter: brightness(1.2);
        }

        #loading {
            display: none;
            position: fixed;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            text-align: center;
        }

        #loading.visible {
            display: block;
        }

        .spinner {
            width: 32px;
            height: 32px;
            border: 3px solid var(--border);
            border-top-color: var(--accent);
            border-radius: 50%;
            animation: spin 0.8s linear infinite;
            margin: 0 auto 8px;
        }

        @keyframes spin {
            to { transform: rotate(360deg); }
        }

        #error-banner {
            display: none;
            position: fixed;
            bottom: 0;
            left: 0;
            right: 0;
            background: var(--error-bg);
            color: var(--error-fg);
            padding: 10px 16px;
            font-size: 12px;
            z-index: 200;
            max-height: 120px;
            overflow-y: auto;
            border-top: 1px solid var(--error-fg);
        }

        #error-banner.visible {
            display: block;
        }

        #error-banner .close-btn {
            float: right;
            background: none;
            border: none;
            color: var(--error-fg);
            cursor: pointer;
            font-size: 16px;
            line-height: 1;
            padding: 0 4px;
        }

        #minimap {
            display: none;
            position: fixed;
            bottom: 8px;
            right: 8px;
            width: 150px;
            height: 100px;
            border: 1px solid var(--border);
            background: var(--bg);
            opacity: 0.8;
            z-index: 90;
            overflow: hidden;
        }

        #minimap.visible {
            display: block;
        }

        #minimap svg {
            width: 100%;
            height: 100%;
        }

        #minimap-viewport {
            position: absolute;
            border: 1.5px solid var(--accent);
            background: rgba(0, 122, 204, 0.1);
            pointer-events: none;
        }

        #empty-state {
            display: none;
            position: fixed;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            text-align: center;
            color: var(--fg);
            opacity: 0.5;
        }

        #empty-state.visible {
            display: block;
        }

        #empty-state .icon {
            font-size: 48px;
            margin-bottom: 12px;
        }
    </style>
</head>
<body>
    <div id="toolbar">
        <button id="btn-zoom-in" title="Zoom in">+</button>
        <span id="zoom-label">100%</span>
        <button id="btn-zoom-out" title="Zoom out">&minus;</button>
        <button id="btn-zoom-fit" title="Zoom to fit">Fit</button>
        <button id="btn-zoom-reset" title="Reset zoom">1:1</button>
    </div>

    <div id="viewport">
        <div id="svg-container"></div>
    </div>

    <div id="loading">
        <div class="spinner"></div>
        <div>Rendering...</div>
    </div>

    <div id="empty-state" class="visible">
        <div class="icon">&#9697;</div>
        <div>Waiting for diagram...</div>
    </div>

    <div id="error-banner">
        <button class="close-btn" id="error-close">&times;</button>
        <pre id="error-text"></pre>
    </div>

    <div id="minimap">
        <div id="minimap-viewport"></div>
    </div>

    <script nonce="${nonce}">
    (function() {
        const vscodeApi = acquireVsCodeApi();
        const viewport = document.getElementById('viewport');
        const container = document.getElementById('svg-container');
        const loading = document.getElementById('loading');
        const emptyState = document.getElementById('empty-state');
        const errorBanner = document.getElementById('error-banner');
        const errorText = document.getElementById('error-text');
        const errorClose = document.getElementById('error-close');
        const minimap = document.getElementById('minimap');
        const minimapViewport = document.getElementById('minimap-viewport');
        const zoomLabel = document.getElementById('zoom-label');
        const btnZoomIn = document.getElementById('btn-zoom-in');
        const btnZoomOut = document.getElementById('btn-zoom-out');
        const btnZoomFit = document.getElementById('btn-zoom-fit');
        const btnZoomReset = document.getElementById('btn-zoom-reset');

        let scale = 1;
        let panX = 0;
        let panY = 0;
        let isDragging = false;
        let dragStartX = 0;
        let dragStartY = 0;
        let dragStartPanX = 0;
        let dragStartPanY = 0;
        let svgWidth = 0;
        let svgHeight = 0;
        let hasSvg = false;

        function applyTransform() {
            container.style.transform =
                'translate(' + panX + 'px, ' + panY + 'px) scale(' + scale + ')';
            zoomLabel.textContent = Math.round(scale * 100) + '%';
            updateMinimap();
        }

        function clampPan() {
            const vw = viewport.clientWidth;
            const vh = viewport.clientHeight;
            const sw = svgWidth * scale;
            const sh = svgHeight * scale;

            // When diagram exceeds viewport, clamp so it doesn't
            // scroll past the edges. When it fits, allow free movement.
            if (sw > vw) {
                panX = Math.min(0, Math.max(vw - sw, panX));
            }
            if (sh > vh) {
                panY = Math.min(0, Math.max(vh - sh, panY));
            }
        }

        function zoomTo(newScale, cx, cy) {
            if (cx === undefined) cx = viewport.clientWidth / 2;
            if (cy === undefined) cy = viewport.clientHeight / 2;

            newScale = Math.max(0.1, Math.min(10, newScale));

            const worldX = (cx - panX) / scale;
            const worldY = (cy - panY) / scale;

            scale = newScale;
            panX = cx - worldX * scale;
            panY = cy - worldY * scale;

            clampPan();
            applyTransform();
        }

        function zoomToFit() {
            if (!hasSvg || svgWidth === 0 || svgHeight === 0) return;
            const vw = viewport.clientWidth;
            const vh = viewport.clientHeight;
            const padding = 20;
            const fitScale = Math.min(
                (vw - padding * 2) / svgWidth,
                (vh - padding * 2) / svgHeight
            );
            scale = Math.min(fitScale, 2);
            panX = (vw - svgWidth * scale) / 2;
            panY = (vh - svgHeight * scale) / 2;
            applyTransform();
        }

        function updateMinimap() {
            if (!hasSvg) {
                minimap.classList.remove('visible');
                return;
            }

            const vw = viewport.clientWidth;
            const vh = viewport.clientHeight;
            const sw = svgWidth * scale;
            const sh = svgHeight * scale;

            const showMinimap = sw > vw * 1.2 || sh > vh * 1.2;
            minimap.classList.toggle('visible', showMinimap);

            if (!showMinimap) return;

            const mw = minimap.clientWidth;
            const mh = minimap.clientHeight;
            const minimapScale = Math.min(mw / svgWidth, mh / svgHeight);

            const vpLeft = (-panX / scale) * minimapScale;
            const vpTop = (-panY / scale) * minimapScale;
            const vpWidth = (vw / scale) * minimapScale;
            const vpHeight = (vh / scale) * minimapScale;

            minimapViewport.style.left = Math.max(0, vpLeft) + 'px';
            minimapViewport.style.top = Math.max(0, vpTop) + 'px';
            minimapViewport.style.width = Math.min(mw, vpWidth) + 'px';
            minimapViewport.style.height = Math.min(mh, vpHeight) + 'px';
        }

        function setSvg(svgData) {
            // LSP returns base64-encoded SVG — decode it
            let svgText;
            try {
                svgText = atob(svgData);
            } catch (e) {
                // If not base64, assume raw SVG
                svgText = svgData;
            }
            container.innerHTML = svgText;
            loading.classList.remove('visible');
            emptyState.classList.remove('visible');
            errorBanner.classList.remove('visible');
            hasSvg = true;

            const svgEl = container.querySelector('svg');
            if (svgEl) {
                svgWidth = svgEl.width.baseVal.value || svgEl.viewBox.baseVal.width || svgEl.getBoundingClientRect().width;
                svgHeight = svgEl.height.baseVal.value || svgEl.viewBox.baseVal.height || svgEl.getBoundingClientRect().height;

                if (svgWidth === 0 || svgHeight === 0) {
                    const bbox = svgEl.getBBox();
                    svgWidth = bbox.width || 400;
                    svgHeight = bbox.height || 300;
                }

                // Copy SVG to minimap
                const minimapSvg = svgEl.cloneNode(true);
                minimapSvg.removeAttribute('width');
                minimapSvg.removeAttribute('height');
                const existingMiniSvg = minimap.querySelector('svg');
                if (existingMiniSvg) existingMiniSvg.remove();
                minimap.insertBefore(minimapSvg, minimapViewport);

                // Attach click handlers to title-bearing elements
                svgEl.querySelectorAll('[id]').forEach(function(el) {
                    el.addEventListener('click', function(e) {
                        e.stopPropagation();
                        const titleEl = el.querySelector('title');
                        if (titleEl) {
                            const text = titleEl.textContent || '';
                            const lineMatch = text.match(/line:(\\d+)/);
                            if (lineMatch) {
                                vscodeApi.postMessage({
                                    type: 'clickElement',
                                    line: parseInt(lineMatch[1], 10)
                                });
                            }
                        }
                    });
                });
            }

            zoomToFit();
        }

        // Mouse wheel zoom
        viewport.addEventListener('wheel', function(e) {
            e.preventDefault();
            const delta = e.deltaY > 0 ? 0.9 : 1.1;
            zoomTo(scale * delta, e.clientX, e.clientY);
        }, { passive: false });

        // Pan with mouse drag
        viewport.addEventListener('mousedown', function(e) {
            if (e.button !== 0) return;
            isDragging = true;
            dragStartX = e.clientX;
            dragStartY = e.clientY;
            dragStartPanX = panX;
            dragStartPanY = panY;
            viewport.classList.add('dragging');
        });

        window.addEventListener('mousemove', function(e) {
            if (!isDragging) return;
            panX = dragStartPanX + (e.clientX - dragStartX);
            panY = dragStartPanY + (e.clientY - dragStartY);
            clampPan();
            applyTransform();
        });

        window.addEventListener('mouseup', function() {
            isDragging = false;
            viewport.classList.remove('dragging');
        });

        // Double-click to fit
        viewport.addEventListener('dblclick', function(e) {
            if (e.target === viewport || e.target === container) {
                zoomToFit();
            }
        });

        // Toolbar buttons
        btnZoomIn.addEventListener('click', function() { zoomTo(scale * 1.25); });
        btnZoomOut.addEventListener('click', function() { zoomTo(scale / 1.25); });
        btnZoomFit.addEventListener('click', zoomToFit);
        btnZoomReset.addEventListener('click', function() {
            scale = 1;
            clampPan();
            applyTransform();
        });

        errorClose.addEventListener('click', function() {
            errorBanner.classList.remove('visible');
        });

        // Handle messages from extension
        window.addEventListener('message', function(event) {
            const msg = event.data;
            switch (msg.type) {
                case 'svgUpdate':
                    setSvg(msg.svg);
                    break;
                case 'loading':
                    loading.classList.add('visible');
                    break;
                case 'error':
                    loading.classList.remove('visible');
                    errorText.textContent = msg.message;
                    errorBanner.classList.add('visible');
                    break;
            }
        });

        // Respond to window resize
        window.addEventListener('resize', function() {
            if (hasSvg) {
                clampPan();
                applyTransform();
            }
        });
    })();
    </script>
</body>
</html>`;
    }
}

function getFileName(filePath: string): string {
    return filePath.split(/[\\/]/).pop() || 'Diagram';
}

function getNonce(): string {
    let text = '';
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    for (let i = 0; i < 32; i++) {
        text += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return text;
}
