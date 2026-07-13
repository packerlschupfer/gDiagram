import * as vscode from 'vscode';
import {
    LanguageClient,
    LanguageClientOptions,
    ServerOptions,
} from 'vscode-languageclient/node';
import { PreviewPanel } from './PreviewPanel';
import { TemplateProvider } from './TemplateProvider';

let client: LanguageClient;

export function activate(context: vscode.ExtensionContext) {
    const config = vscode.workspace.getConfiguration('gdiagram');
    const lspPath = config.get<string>('lspPath', 'gdiagram-lsp');

    const serverOptions: ServerOptions = {
        command: lspPath,
        args: [],
    };

    const clientOptions: LanguageClientOptions = {
        documentSelector: [
            { scheme: 'file', language: 'plantuml' },
            { scheme: 'file', language: 'mermaid' },
        ],
    };

    client = new LanguageClient(
        'gdiagram',
        'gDiagram Language Server',
        serverOptions,
        clientOptions
    );

    client.onNotification(
        'gdiagram/svgUpdate',
        (params: { uri: string; svg: string }) => {
            PreviewPanel.updateSvg(params.uri, params.svg);
        }
    );

    client.onNotification(
        'gdiagram/renderError',
        (params: { uri: string; message: string }) => {
            PreviewPanel.showError(params.uri, params.message);
        }
    );

    client.start();

    context.subscriptions.push(
        vscode.commands.registerCommand('gdiagram.showPreview', () => {
            const editor = vscode.window.activeTextEditor;
            if (editor) {
                PreviewPanel.createOrShow(
                    context.extensionUri,
                    editor.document,
                    client
                );
            }
        }),

        vscode.commands.registerCommand('gdiagram.exportPng', () =>
            exportDiagram('png')
        ),
        vscode.commands.registerCommand('gdiagram.exportSvg', () =>
            exportDiagram('svg')
        ),
        vscode.commands.registerCommand('gdiagram.exportPdf', () =>
            exportDiagram('pdf')
        ),
        vscode.commands.registerCommand('gdiagram.newFromTemplate', () =>
            TemplateProvider.showTemplatePicker(client)
        )
    );

    if (config.get<boolean>('autoPreview', true)) {
        context.subscriptions.push(
            vscode.window.onDidChangeActiveTextEditor((editor) => {
                if (editor && isSupported(editor.document)) {
                    PreviewPanel.createOrShow(
                        context.extensionUri,
                        editor.document,
                        client
                    );
                }
            })
        );
    }

    context.subscriptions.push(
        vscode.workspace.onDidChangeTextDocument((e) => {
            if (isSupported(e.document)) {
                PreviewPanel.requestRender(e.document.uri.toString(), client);
            }
        })
    );
}

function isSupported(doc: vscode.TextDocument): boolean {
    return doc.languageId === 'plantuml' || doc.languageId === 'mermaid';
}

async function exportDiagram(format: string) {
    const editor = vscode.window.activeTextEditor;
    if (!editor || !isSupported(editor.document)) {
        vscode.window.showWarningMessage(
            'Open a PlantUML or Mermaid file to export.'
        );
        return;
    }

    const uri = await vscode.window.showSaveDialog({
        filters: { [format.toUpperCase()]: [format] },
        defaultUri: vscode.Uri.file(
            editor.document.fileName.replace(/\.[^.]+$/, '.' + format)
        ),
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
    } catch (err: unknown) {
        const message =
            err instanceof Error ? err.message : 'Unknown export error';
        vscode.window.showErrorMessage(`Export failed: ${message}`);
    }
}

export function deactivate(): Thenable<void> | undefined {
    return client?.stop();
}
