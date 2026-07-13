namespace GDiagram {
    // Mermaid-specific diagram types
    //
    // The per-diagram AST classes live in src/core/ast/mermaid/ (one file per
    // diagram type). This file retains only what is shared across all of them:
    // the MermaidDiagramType enum below.
    public enum MermaidDiagramType {
        FLOWCHART,
        SEQUENCE,
        CLASS,
        STATE,
        ER_DIAGRAM,
        GANTT,
        PIE,
        GIT_GRAPH,
        USER_JOURNEY,
        MINDMAP,
        TIMELINE,
        QUADRANT,
        XYCHART,
        KANBAN,
        SANKEY,
        REQUIREMENT,
        BLOCK,
        PACKET,
        C4,
        ARCHITECTURE,
        ZENUML,
        RADAR,
        TREEMAP,
        UNKNOWN
    }
}
