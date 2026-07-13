import * as vscode from 'vscode';
import { LanguageClient } from 'vscode-languageclient/node';
export declare class PreviewPanel {
    static readonly viewType = "gdiagram.preview";
    private static panels;
    private static renderTimers;
    private readonly panel;
    private readonly extensionUri;
    private documentUri;
    private disposables;
    static createOrShow(extensionUri: vscode.Uri, document: vscode.TextDocument, client: LanguageClient): void;
    static updateSvg(uri: string, svg: string): void;
    static showError(uri: string, message: string): void;
    static requestRender(uri: string, client: LanguageClient): void;
    private constructor();
    private navigateToSource;
    private dispose;
    private getHtmlContent;
}
//# sourceMappingURL=PreviewPanel.d.ts.map