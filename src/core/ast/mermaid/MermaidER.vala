namespace GDiagram {

    // ==================== MERMAID ER DIAGRAM ====================

    public enum MermaidERCardinality {
        ZERO_OR_ONE,     // o|
        EXACTLY_ONE,     // ||
        ZERO_OR_MORE,    // o{
        ONE_OR_MORE      // |{
    }

    public class MermaidEREntity : Object {
        public string name { get; set; }
        public int source_line { get; set; }
        public Gee.ArrayList<MermaidERAttribute> attributes { get; private set; }

        public MermaidEREntity(string name, int line = 0) {
            this.name = name;
            this.source_line = line;
            this.attributes = new Gee.ArrayList<MermaidERAttribute>();
        }

        public void add_attribute(MermaidERAttribute attr) {
            attributes.add(attr);
        }
    }

    public class MermaidERAttribute : Object {
        public string name { get; set; }
        public string? type_name { get; set; }
        public bool is_primary_key { get; set; }
        public bool is_foreign_key { get; set; }

        public MermaidERAttribute(string name) {
            this.name = name;
            this.type_name = null;
            this.is_primary_key = false;
            this.is_foreign_key = false;
        }
    }

    public class MermaidERRelationship : Object {
        public MermaidEREntity from { get; set; }
        public MermaidEREntity to { get; set; }
        public MermaidERCardinality from_cardinality { get; set; }
        public MermaidERCardinality to_cardinality { get; set; }
        public string? label { get; set; }

        public MermaidERRelationship(MermaidEREntity from, MermaidEREntity to) {
            this.from = from;
            this.to = to;
            this.from_cardinality = MermaidERCardinality.ZERO_OR_MORE;
            this.to_cardinality = MermaidERCardinality.ZERO_OR_MORE;
            this.label = null;
        }
    }

    public class MermaidERDiagram : Object {
        public MermaidDiagramType diagram_type { get; private set; }
        public Gee.ArrayList<MermaidEREntity> entities { get; private set; }
        public Gee.ArrayList<MermaidERRelationship> relationships { get; private set; }
        public Gee.ArrayList<ParseError> errors { get; private set; }
        public string? title { get; set; }

        private Gee.HashMap<string, MermaidEREntity> entity_map;

        public MermaidERDiagram() {
            this.diagram_type = MermaidDiagramType.ER_DIAGRAM;
            this.entities = new Gee.ArrayList<MermaidEREntity>();
            this.relationships = new Gee.ArrayList<MermaidERRelationship>();
            this.errors = new Gee.ArrayList<ParseError>();
            this.entity_map = new Gee.HashMap<string, MermaidEREntity>();
            this.title = null;
        }

        public void add_entity(MermaidEREntity entity) {
            if (!entity_map.has_key(entity.name)) {
                entities.add(entity);
                entity_map.set(entity.name, entity);
            }
        }

        public MermaidEREntity? find_entity(string name) {
            return entity_map.get(name);
        }

        public MermaidEREntity get_or_create_entity(string name) {
            var existing = find_entity(name);
            if (existing != null) {
                return existing;
            }

            var entity = new MermaidEREntity(name);
            add_entity(entity);
            return entity;
        }

        public bool has_errors() {
            return errors.size > 0;
        }
    }

}
