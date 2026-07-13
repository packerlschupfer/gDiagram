namespace GDiagram {
    /**
     * Template gallery dialog. Presents PlantUML and Mermaid starter
     * templates in a tabbed view; emits {@link template_chosen} with the
     * selected template's source text. The caller is responsible for
     * creating a document/tab from that content.
     */
    public class TemplateGallery : Object {
        public signal void template_chosen(string content);

        public void present(Gtk.Window parent) {
            var dialog = new Adw.Dialog();
            dialog.title = "Template Gallery";
            dialog.content_width = 650;
            dialog.content_height = 520;

            var toolbar_view = new Adw.ToolbarView();
            var header = new Adw.HeaderBar();
            toolbar_view.add_top_bar(header);

            var stack = new Adw.ViewStack();
            stack.hexpand = true;
            stack.vexpand = true;

            // ── PlantUML templates ────────────────────────────────────────────
            var puml_flow = new Gtk.FlowBox();
            puml_flow.selection_mode = Gtk.SelectionMode.SINGLE;
            puml_flow.homogeneous = true;
            puml_flow.min_children_per_line = 2;
            puml_flow.max_children_per_line = 4;
            puml_flow.column_spacing = 12;
            puml_flow.row_spacing = 12;
            puml_flow.margin_start = 12;
            puml_flow.margin_end = 12;
            puml_flow.margin_top = 12;
            puml_flow.margin_bottom = 12;
            add_template_item(puml_flow, "Class Diagram",     "class",     CLASS_DIAGRAM_TEMPLATE);
            add_template_item(puml_flow, "Sequence Diagram",  "sequence",  SEQUENCE_DIAGRAM_TEMPLATE);
            add_template_item(puml_flow, "Activity Diagram",  "activity",  ACTIVITY_DIAGRAM_TEMPLATE);
            add_template_item(puml_flow, "State Diagram",     "state",     STATE_DIAGRAM_TEMPLATE);
            add_template_item(puml_flow, "Use Case Diagram",  "usecase",   USECASE_DIAGRAM_TEMPLATE);
            add_template_item(puml_flow, "Component Diagram", "component", COMPONENT_DIAGRAM_TEMPLATE);
            add_template_item(puml_flow, "C4 Kubernetes",     "cluster",   C4_KUBERNETES_TEMPLATE);
            puml_flow.child_activated.connect((child) => {
                var box = child.child as Gtk.Box;
                if (box != null) {
                    var tmpl = box.get_data<string>("template");
                    if (tmpl != null) { template_chosen(tmpl); dialog.close(); }
                }
            });
            var puml_scroll = new Gtk.ScrolledWindow();
            puml_scroll.hexpand = true;
            puml_scroll.vexpand = true;
            puml_scroll.child = puml_flow;
            stack.add_titled(puml_scroll, "plantuml", "PlantUML");

            // ── Mermaid templates ─────────────────────────────────────────────
            var mmd_flow = new Gtk.FlowBox();
            mmd_flow.selection_mode = Gtk.SelectionMode.SINGLE;
            mmd_flow.homogeneous = true;
            mmd_flow.min_children_per_line = 2;
            mmd_flow.max_children_per_line = 4;
            mmd_flow.column_spacing = 12;
            mmd_flow.row_spacing = 12;
            mmd_flow.margin_start = 12;
            mmd_flow.margin_end = 12;
            mmd_flow.margin_top = 12;
            mmd_flow.margin_bottom = 12;
            add_template_item(mmd_flow, "Flowchart",      "flowchart", MERMAID_FLOWCHART_TEMPLATE);
            add_template_item(mmd_flow, "Sequence",        "sequence",  MERMAID_SEQUENCE_TEMPLATE);
            add_template_item(mmd_flow, "Class Diagram",   "class",     MERMAID_CLASS_TEMPLATE);
            add_template_item(mmd_flow, "State Diagram",   "state",     MERMAID_STATE_TEMPLATE);
            add_template_item(mmd_flow, "ER Diagram",      "er",        MERMAID_ER_TEMPLATE);
            add_template_item(mmd_flow, "Gantt Chart",     "gantt",     MERMAID_GANTT_TEMPLATE);
            add_template_item(mmd_flow, "Pie Chart",       "pie",       MERMAID_PIE_TEMPLATE);
            add_template_item(mmd_flow, "Git Graph",       "gitgraph",  MERMAID_GIT_GRAPH_TEMPLATE);
            add_template_item(mmd_flow, "Mindmap",         "mindmap",   MERMAID_MINDMAP_TEMPLATE);
            add_template_item(mmd_flow, "Timeline",        "timeline",  MERMAID_TIMELINE_TEMPLATE);
            add_template_item(mmd_flow, "Quadrant Chart",  "quadrant",  MERMAID_QUADRANT_TEMPLATE);
            add_template_item(mmd_flow, "XY Chart",        "xychart",   MERMAID_XYCHART_TEMPLATE);
            add_template_item(mmd_flow, "Kanban",          "kanban",    MERMAID_KANBAN_TEMPLATE);
            add_template_item(mmd_flow, "User Journey",    "journey",   MERMAID_USER_JOURNEY_TEMPLATE);
            mmd_flow.child_activated.connect((child) => {
                var box = child.child as Gtk.Box;
                if (box != null) {
                    var tmpl = box.get_data<string>("template");
                    if (tmpl != null) { template_chosen(tmpl); dialog.close(); }
                }
            });
            var mmd_scroll = new Gtk.ScrolledWindow();
            mmd_scroll.hexpand = true;
            mmd_scroll.vexpand = true;
            mmd_scroll.child = mmd_flow;
            stack.add_titled(mmd_scroll, "mermaid", "Mermaid");

            var switcher = new Adw.ViewSwitcher();
            switcher.stack = stack;
            switcher.policy = Adw.ViewSwitcherPolicy.WIDE;
            header.title_widget = switcher;

            toolbar_view.content = stack;
            dialog.child = toolbar_view;
            dialog.present(parent);
        }

        private void add_template_item(Gtk.FlowBox flowbox, string title, string id, string template) {
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
            box.width_request = 120;
            box.set_data("template", template);

            var icon = new Gtk.Image.from_icon_name("text-x-generic-symbolic");
            icon.pixel_size = 48;
            icon.margin_top = 12;
            box.append(icon);

            var label = new Gtk.Label(title);
            label.wrap = true;
            label.justify = Gtk.Justification.CENTER;
            label.margin_bottom = 12;
            box.append(label);

            flowbox.append(box);
        }

        // ==================== Templates Content ====================

        private const string CLASS_DIAGRAM_TEMPLATE = """@startuml
title Class Diagram Example

class Animal {
    +name: String
    +age: int
    +eat()
    +sleep()
}

class Dog {
    +breed: String
    +bark()
}

class Cat {
    +color: String
    +meow()
}

Animal <|-- Dog
Animal <|-- Cat
@enduml""";

        private const string SEQUENCE_DIAGRAM_TEMPLATE = """@startuml
title Sequence Diagram Example

actor User
participant "Web App" as App
participant "API Server" as API
database "Database" as DB

User -> App : Request page
App -> API : GET /data
API -> DB : Query
DB --> API : Results
API --> App : JSON response
App --> User : Rendered page
@enduml""";

        private const string ACTIVITY_DIAGRAM_TEMPLATE = """@startuml
start
:Receive order;
if (In stock?) then (yes)
    :Process order;
    :Ship order;
else (no)
    :Notify customer;
    :Reorder from supplier;
endif
:Update inventory;
stop
@enduml""";

        private const string STATE_DIAGRAM_TEMPLATE = """@startuml
title State Diagram Example

[*] --> Idle

Idle --> Processing : Start
Processing --> Completed : Success
Processing --> Failed : Error

Completed --> [*]
Failed --> Idle : Retry

state Processing {
    [*] --> Validating
    Validating --> Executing
    Executing --> [*]
}
@enduml""";

        private const string USECASE_DIAGRAM_TEMPLATE = """@startuml
title Use Case Diagram Example

left to right direction

actor Customer
actor Admin

rectangle "Online Store" {
    usecase "Browse Products" as UC1
    usecase "Add to Cart" as UC2
    usecase "Checkout" as UC3
    usecase "Manage Inventory" as UC4
    usecase "Process Orders" as UC5
}

Customer --> UC1
Customer --> UC2
Customer --> UC3
Admin --> UC4
Admin --> UC5
UC3 ..> UC2 : <<include>>
@enduml""";

        private const string COMPONENT_DIAGRAM_TEMPLATE = """@startuml
title Component Diagram Example

package "Frontend" {
    [Web App] as webapp
    [Mobile App] as mobile
}

package "Backend" {
    [API Gateway] as gateway
    [Auth Service] as auth
    [User Service] as users
    [Order Service] as orders
}

database "PostgreSQL" as db

webapp --> gateway
mobile --> gateway
gateway --> auth
gateway --> users
gateway --> orders
users --> db
orders --> db
@enduml""";

        private const string C4_KUBERNETES_TEMPLATE = """@startuml
' Kubernetes learning mindmap — Level 1: System Context
'
' Entry point of a multi-file C4 model. In gDiagram, double-clicking
' an element with stereotype <<container>> or <<system>> drills into a
' file named after that element's alias (e.g. `cluster` -> cluster.puml).

title Kubernetes — System Context

rectangle "Developer\nWrites & deploys apps"          <<person>> as dev
rectangle "Cluster Admin\nOperates the cluster"       <<person>> as admin
rectangle "End User\nConsumes services"               <<external_person>> as user

rectangle "Kubernetes Platform" <<system_boundary>> as platform {
    rectangle "Kubernetes Cluster\nControl plane + worker nodes" <<container>> as cluster
}

rectangle "Container Registry\nDocker Hub / Harbor / ECR"  <<external_system>> as registry
rectangle "Git Repository\nSource of truth (GitOps)"        <<external_system>> as git
rectangle "Identity Provider\nOIDC / LDAP / cert-based"     <<external_system>> as idp
rectangle "Cloud Provider API\nLoadBalancers, volumes, DNS" <<external_system>> as cloud
rectangle "Observability Stack\nMetrics, logs, traces"      <<external_system>> as obs

dev    --> git     : "git push"
admin  --> cluster : "kubectl / kubeadm"
user   --> cluster : "HTTPS"

git    --> cluster : "ArgoCD / Flux sync"
cluster --> registry : "Pulls images"
cluster --> idp      : "Authenticates users"
cluster --> cloud    : "Provisions LBs, PVs"
cluster --> obs      : "Pushes metrics, logs"
@enduml""";

        // ==================== Mermaid Template Content ====================

        private const string MERMAID_FLOWCHART_TEMPLATE = """flowchart TD
    A[Start] --> B{Is it correct?}
    B -->|Yes| C[Process data]
    B -->|No| D[Fix the issue]
    D --> B
    C --> E[Send result]
    E --> F[End]""";

        private const string MERMAID_SEQUENCE_TEMPLATE = """sequenceDiagram
    participant User
    participant App
    participant API
    participant DB

    User->>App: Request page
    App->>API: GET /data
    API->>DB: SELECT query
    DB-->>API: Result rows
    API-->>App: JSON response
    App-->>User: Rendered page""";

        private const string MERMAID_CLASS_TEMPLATE = """classDiagram
    class Animal {
        +String name
        +int age
        +eat() void
        +sleep() void
    }
    class Dog {
        +String breed
        +bark() void
    }
    class Cat {
        +String color
        +meow() void
    }
    Animal <|-- Dog
    Animal <|-- Cat""";

        private const string MERMAID_STATE_TEMPLATE = """stateDiagram-v2
    [*] --> Idle
    Idle --> Processing : Start
    Processing --> Completed : Success
    Processing --> Failed : Error
    Completed --> [*]
    Failed --> Idle : Retry

    state Processing {
        [*] --> Validating
        Validating --> Executing
        Executing --> [*]
    }""";

        private const string MERMAID_ER_TEMPLATE = """erDiagram
    CUSTOMER ||--o{ ORDER : places
    ORDER ||--|{ LINE-ITEM : contains
    PRODUCT ||--o{ LINE-ITEM : "included in"

    CUSTOMER {
        int id
        string name
        string email
    }
    ORDER {
        int id
        date created_at
    }
    LINE-ITEM {
        int quantity
        float price
    }
    PRODUCT {
        int id
        string name
        float price
    }""";

        private const string MERMAID_GANTT_TEMPLATE = """gantt
    title Project Timeline
    dateFormat YYYY-MM-DD

    section Planning
        Requirements    :a1, 2024-01-01, 7d
        Design          :a2, after a1, 5d

    section Development
        Backend         :b1, after a2, 14d
        Frontend        :b2, after a2, 14d

    section Testing
        QA              :c1, after b1, 7d
        UAT             :c2, after c1, 3d

    section Deployment
        Release         :d1, after c2, 1d""";

        private const string MERMAID_PIE_TEMPLATE = """pie title Browser Market Share
    "Chrome" : 65
    "Safari" : 19
    "Firefox" : 4
    "Edge" : 4
    "Other" : 8""";

        private const string MERMAID_GIT_GRAPH_TEMPLATE = """gitGraph
    commit id: "Initial commit"
    commit id: "Add README"
    branch develop
    checkout develop
    commit id: "Feature A"
    commit id: "Feature B"
    checkout main
    merge develop id: "Merge develop"
    commit id: "Hotfix"
    branch release
    checkout release
    commit id: "v1.0.0" tag: "v1.0.0"
    checkout main
    merge release""";

        private const string MERMAID_MINDMAP_TEMPLATE = """mindmap
  root((Project))
    Planning
      Requirements
      Timeline
      Budget
    Development
      Frontend
      Backend
      Database
    Testing
      Unit Tests
      Integration
      UAT
    Deployment
      Staging
      Production""";

        private const string MERMAID_TIMELINE_TEMPLATE = """timeline
    title History of Computing
    1940 : ENIAC built
    1950 : Transistor invented
    1960 : Integrated circuit
    1970 : Microprocessor
    1980 : Personal Computer
    1990 : World Wide Web
    2000 : Smartphones
    2010 : Cloud Computing
    2020 : AI revolution""";

        private const string MERMAID_QUADRANT_TEMPLATE = """quadrantChart
    title Feature Priority Matrix
    x-axis Low Effort --> High Effort
    y-axis Low Impact --> High Impact
    quadrant-1 Do First
    quadrant-2 Plan
    quadrant-3 Reconsider
    quadrant-4 Delegate
    Quick win: [0.2, 0.8]
    Big project: [0.7, 0.9]
    Minor task: [0.4, 0.3]
    Nice to have: [0.8, 0.4]
    Chore: [0.6, 0.2]""";

        private const string MERMAID_XYCHART_TEMPLATE = """xychart-beta
    title "Monthly Revenue"
    x-axis [Jan, Feb, Mar, Apr, May, Jun]
    y-axis "Revenue ($K)" 0 --> 100
    bar [45, 62, 58, 71, 83, 90]
    line [45, 62, 58, 71, 83, 90]""";

        // Kanban parser treats indent=0 as a column header and indent>0
        // as a card under the current column, so columns must be flush-left.
        private const string MERMAID_KANBAN_TEMPLATE = """kanban
Todo
    task1[Write unit tests]
    task2[Update documentation]
    task3[Design new feature]
In-Progress
    task4[Implement backend API]
    task5[Code review]
Done
    task6[Initial project setup]
    task7[CI/CD pipeline]""";

        private const string MERMAID_USER_JOURNEY_TEMPLATE = """journey
    title User Checkout Flow
    section Browse
        Find product: 5: User
        View details: 4: User
    section Cart
        Add to cart: 5: User
        Review cart: 3: User
    section Checkout
        Enter details: 2: User
        Payment: 3: User, System
        Confirm order: 5: User, System""";
    }
}
