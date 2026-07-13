"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.activate = activate;
exports.deactivate = deactivate;
const vscode = __importStar(require("vscode"));
const node_1 = require("vscode-languageclient/node");
const PreviewPanel_1 = require("./PreviewPanel");
const TemplateProvider_1 = require("./TemplateProvider");
let client;
function activate(context) {
    const config = vscode.workspace.getConfiguration('gdiagram');
    const lspPath = config.get('lspPath', 'gdiagram-lsp');
    const serverOptions = {
        command: lspPath,
        args: [],
    };
    const clientOptions = {
        documentSelector: [
            { scheme: 'file', language: 'plantuml' },
            { scheme: 'file', language: 'mermaid' },
        ],
    };
    client = new node_1.LanguageClient('gdiagram', 'gDiagram Language Server', serverOptions, clientOptions);
    client.onNotification('gdiagram/svgUpdate', (params) => {
        PreviewPanel_1.PreviewPanel.updateSvg(params.uri, params.svg);
    });
    client.onNotification('gdiagram/renderError', (params) => {
        PreviewPanel_1.PreviewPanel.showError(params.uri, params.message);
    });
    client.start();
    context.subscriptions.push(vscode.commands.registerCommand('gdiagram.showPreview', () => {
        const editor = vscode.window.activeTextEditor;
        if (editor) {
            PreviewPanel_1.PreviewPanel.createOrShow(context.extensionUri, editor.document, client);
        }
    }), vscode.commands.registerCommand('gdiagram.exportPng', () => exportDiagram('png')), vscode.commands.registerCommand('gdiagram.exportSvg', () => exportDiagram('svg')), vscode.commands.registerCommand('gdiagram.exportPdf', () => exportDiagram('pdf')), vscode.commands.registerCommand('gdiagram.newFromTemplate', () => TemplateProvider_1.TemplateProvider.showTemplatePicker(client)));
    if (config.get('autoPreview', true)) {
        context.subscriptions.push(vscode.window.onDidChangeActiveTextEditor((editor) => {
            if (editor && isSupported(editor.document)) {
                PreviewPanel_1.PreviewPanel.createOrShow(context.extensionUri, editor.document, client);
            }
        }));
    }
    context.subscriptions.push(vscode.workspace.onDidChangeTextDocument((e) => {
        if (isSupported(e.document)) {
            PreviewPanel_1.PreviewPanel.requestRender(e.document.uri.toString(), client);
        }
    }));
}
function isSupported(doc) {
    return doc.languageId === 'plantuml' || doc.languageId === 'mermaid';
}
async function exportDiagram(format) {
    const editor = vscode.window.activeTextEditor;
    if (!editor || !isSupported(editor.document)) {
        vscode.window.showWarningMessage('Open a PlantUML or Mermaid file to export.');
        return;
    }
    const uri = await vscode.window.showSaveDialog({
        filters: { [format.toUpperCase()]: [format] },
        defaultUri: vscode.Uri.file(editor.document.fileName.replace(/\.[^.]+$/, '.' + format)),
    });
    if (!uri) {
        return;
    }
    try {
        await client.sendRequest('gdiagram/exportFile', {
            uri: editor.document.uri.toString(),
            outputPath: uri.fsPath,
            format: format,
        });
        vscode.window.showInformationMessage(`Exported to ${uri.fsPath}`);
    }
    catch (err) {
        const message = err instanceof Error ? err.message : 'Unknown export error';
        vscode.window.showErrorMessage(`Export failed: ${message}`);
    }
}
function deactivate() {
    return client?.stop();
}
//# sourceMappingURL=extension.js.map