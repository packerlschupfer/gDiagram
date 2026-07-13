namespace GDiagram {
    // One outline entry; its children are listed indented under it.
    // Display-free: tests/review_ui_test.vala checks the collapse keys.
    internal class OutlineNode : Object {
        public string text;
        public string icon_name;
        public weak OutlineNode? parent;
        public Gee.ArrayList<OutlineNode> children = new Gee.ArrayList<OutlineNode>();
        // How many earlier siblings carry the same text (two gantt "section Dev" entries)
        public int occurrence;

        public OutlineNode(string text, string icon_name, OutlineNode? parent) {
            this.text = text;
            this.icon_name = icon_name;
            this.parent = parent;
        }

        // Adds a new entry at the end of `siblings` (the children of `parent`, or the top level)
        public static OutlineNode append(Gee.List<OutlineNode> siblings, string text, string icon_name,
                                         OutlineNode? parent) {
            var node = new OutlineNode(text, icon_name, parent);
            foreach (var sibling in siblings) {
                if (sibling.text == text) node.occurrence++;
            }
            siblings.add(node);
            return node;
        }

        // Keys the collapsed state, which survives the rebuild after every render. The label
        // path alone made same-label siblings share it; their position among each other
        // tells them apart and stays stable while the source above them doesn't change.
        public string key() {
            string own = "%s\x1f%d".printf(text, occurrence);
            return parent != null ? parent.key() + "\n" + own : own;
        }
    }
}
