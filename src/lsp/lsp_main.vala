namespace GDiagram {
    int main(string[] args) {
        // The server re-runs itself as the render worker (see LspServer)
        if (args.length > 1 && args[1] == "--render-worker") {
            return LspRenderWorker.run(args);
        }
        var server = new LspServer();
        return server.run();
    }
}
