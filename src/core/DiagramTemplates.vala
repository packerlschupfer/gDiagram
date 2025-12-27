namespace GDiagram {
    public class DiagramTemplates : Object {
        // Mermaid Flowchart Templates
        public static string FLOWCHART_BASIC = """flowchart TD
    Start[Start] --> Process[Process]
    Process --> Decision{Decision?}
    Decision -->|Yes| Success[Success]
    Decision -->|No| Error[Error]
    Success --> End[End]
    Error --> End
""";

        public static string FLOWCHART_STYLED = """flowchart LR
    classDef successStyle fill:#90EE90,stroke:#228B22,stroke-width:2
    classDef errorStyle fill:#FFB6C1,stroke:#DC143C,stroke-width:2
    classDef processStyle fill:#87CEEB,stroke:#4682B4,stroke-width:2
    classDef decisionStyle fill:#FFD700,stroke:#DAA520,stroke-width:2

    Start([🚀 Start]) --> Input{📝 Valid Input?}
    Input -->|Yes| Process[⚙️ Process Data]
    Input -->|No| Error[❌ Invalid]
    Process --> Success([✅ Success])
    Error --> Retry{🔁 Retry?}
    Retry -->|Yes| Input
    Retry -->|No| End[🏁 End]
    Success --> End

    class Start,Process processStyle
    class Success successStyle
    class Error errorStyle
    class Input,Retry decisionStyle
""";

        public static string SEQUENCE_BASIC = """sequenceDiagram
    participant User
    participant Frontend
    participant Backend

    User->>Frontend: Click button
    Frontend->>Backend: API request
    Backend-->>Frontend: Response
    Frontend-->>User: Update UI
""";

        public static string SEQUENCE_WITH_LOOPS = """sequenceDiagram
    autonumber
    participant Client
    participant Server
    participant Database

    Client->>Server: Login request
    activate Server
    Server->>Database: Query user
    Database-->>Server: User data

    alt Credentials valid
        Server-->>Client: Auth token
        Client->>Server: Fetch data
        Server->>Database: Get data
        Database-->>Server: Data
        Server-->>Client: Data response
    else Invalid credentials
        Server-->>Client: Error 401
    end

    deactivate Server
""";

        public static string STATE_BASIC = """stateDiagram-v2
    [*] --> Idle
    Idle --> Processing: start
    Processing --> Success: complete
    Processing --> Error: fail
    Success --> [*]
    Error --> Idle: retry
    Error --> [*]: abort
""";

        public static string CLASS_BASIC = """classDiagram
    class Animal {
        +string name
        +int age
        +makeSound()
        +eat()
    }

    class Dog {
        +string breed
        +bark()
        +fetch()
    }

    class Cat {
        +bool indoor
        +meow()
        +scratch()
    }

    Animal <|-- Dog
    Animal <|-- Cat
""";

        public static string ER_BASIC = """erDiagram
    CUSTOMER ||--o{ ORDER : places
    ORDER ||--|{ LINE-ITEM : contains
    PRODUCT ||--o{ LINE-ITEM : includes

    CUSTOMER {
        int customer_id PK
        string name
        string email
    }

    ORDER {
        int order_id PK
        int customer_id FK
        date order_date
    }

    LINE-ITEM {
        int line_id PK
        int order_id FK
        int product_id FK
        int quantity
    }

    PRODUCT {
        int product_id PK
        string name
        decimal price
    }
""";

        public static string GANTT_BASIC = """gantt
    title Project Schedule
    dateFormat YYYY-MM-DD

    section Planning
    Requirements : done, 2024-01-01, 5d
    Design : done, 2024-01-06, 7d

    section Development
    Backend : active, 2024-01-13, 10d
    Frontend : active, 2024-01-18, 12d

    section Testing
    QA Testing : crit, 2024-01-30, 5d

    section Deploy
    Go Live : milestone, 2024-02-05, 1d
""";

        public static string PIE_BASIC = """pie title Market Share
    "Product A" : 45
    "Product B" : 30
    "Product C" : 15
    "Other" : 10
""";

        // PlantUML Templates
        public static string PLANTUML_SEQUENCE = """@startuml
participant User
participant System
participant Database

User -> System: Request
activate System
System -> Database: Query
Database --> System: Result
System --> User: Response
deactivate System
@enduml
""";

        public static string PLANTUML_CLASS = """@startuml
class Vehicle {
  +String model
  +int year
  +start()
  +stop()
}

class Car {
  +int doors
  +drive()
}

class Motorcycle {
  +String type
  +ride()
}

Vehicle <|-- Car
Vehicle <|-- Motorcycle
@enduml
""";

        public static string PLANTUML_ACTIVITY = """@startuml
:Initialize;
:Process;
:Complete;
@enduml
""";

        public static string PLANTUML_STATE = """@startuml
[*] --> Idle

Idle --> Processing : start
Processing --> Success : complete
Processing --> Error : fail

Success --> [*]
Error --> Idle : retry
Error --> [*] : abort
@enduml
""";

        public static string PLANTUML_USECASE = """@startuml
left to right direction
actor User
actor Admin

rectangle System {
  User -- (Login)
  User -- (View Dashboard)
  User -- (Export Data)

  Admin -- (Manage Users)
  Admin -- (Configure System)
  Admin -- (View Logs)
}
@enduml
""";

        public static string PLANTUML_COMPONENT = """@startuml
package "Frontend" {
  [Web UI]
  [Mobile App]
}

package "Backend" {
  [API Gateway]
  [Business Logic]
  [Data Access]
}

database "Database" {
  [PostgreSQL]
}

[Web UI] --> [API Gateway]
[Mobile App] --> [API Gateway]
[API Gateway] --> [Business Logic]
[Business Logic] --> [Data Access]
[Data Access] --> [PostgreSQL]
@enduml
""";

        public static string PLANTUML_ER = """@startuml
entity User {
  * user_id : int <<PK>>
  --
  * email : varchar
  * username : varchar
  created_at : timestamp
}

entity Post {
  * post_id : int <<PK>>
  --
  * user_id : int <<FK>>
  * title : varchar
  content : text
  published_at : timestamp
}

User ||--o{ Post : creates
@enduml
""";

        // Helper to get template by name
        public static string? get_template(string name) {
            switch (name.down()) {
                case "mermaid-flowchart":
                case "flowchart-basic":
                    return FLOWCHART_BASIC;
                case "mermaid-flowchart-styled":
                case "flowchart-styled":
                    return FLOWCHART_STYLED;
                case "mermaid-sequence":
                case "sequence-basic":
                    return SEQUENCE_BASIC;
                case "mermaid-sequence-loops":
                case "sequence-loops":
                    return SEQUENCE_WITH_LOOPS;
                case "mermaid-state":
                case "state-basic":
                    return STATE_BASIC;
                case "mermaid-class":
                case "class-basic":
                    return CLASS_BASIC;
                case "mermaid-er":
                case "er-basic":
                    return ER_BASIC;
                case "mermaid-gantt":
                case "gantt-basic":
                    return GANTT_BASIC;
                case "mermaid-pie":
                case "pie-basic":
                    return PIE_BASIC;
                case "plantuml-sequence":
                    return PLANTUML_SEQUENCE;
                case "plantuml-class":
                    return PLANTUML_CLASS;
                case "plantuml-activity":
                    return PLANTUML_ACTIVITY;
                case "plantuml-state":
                    return PLANTUML_STATE;
                case "plantuml-usecase":
                    return PLANTUML_USECASE;
                case "plantuml-component":
                    return PLANTUML_COMPONENT;
                case "plantuml-er":
                    return PLANTUML_ER;
                default:
                    return null;
            }
        }

        // Get Mermaid templates
        public static string[] get_mermaid_template_names() {
            return {
                "mermaid-flowchart",
                "mermaid-flowchart-styled",
                "mermaid-sequence",
                "mermaid-sequence-loops",
                "mermaid-state",
                "mermaid-class",
                "mermaid-er",
                "mermaid-gantt",
                "mermaid-pie"
            };
        }

        // Get PlantUML templates
        public static string[] get_plantuml_template_names() {
            return {
                "plantuml-sequence",
                "plantuml-class",
                "plantuml-activity",  // Re-enabled - restored working parser
                "plantuml-state",
                "plantuml-usecase",
                "plantuml-component",
                "plantuml-er"
            };
        }

        // Get list of all templates (backwards compatibility)
        public static string[] get_template_names() {
            var mermaid = get_mermaid_template_names();
            var plantuml = get_plantuml_template_names();
            var all = new string[mermaid.length + plantuml.length];

            int i = 0;
            foreach (var name in mermaid) {
                all[i++] = name;
            }
            foreach (var name in plantuml) {
                all[i++] = name;
            }

            return all;
        }

        // Get template description
        public static string get_template_description(string name) {
            switch (name) {
                // Mermaid templates
                case "mermaid-flowchart":
                case "flowchart-basic":
                    return "Mermaid: Basic flowchart with decisions";
                case "mermaid-flowchart-styled":
                case "flowchart-styled":
                    return "Mermaid: Styled flowchart with colors and emojis";
                case "mermaid-sequence":
                case "sequence-basic":
                    return "Mermaid: Simple sequence diagram";
                case "mermaid-sequence-loops":
                case "sequence-loops":
                    return "Mermaid: Sequence with loops and alternatives";
                case "mermaid-state":
                case "state-basic":
                    return "Mermaid: Basic state machine";
                case "mermaid-class":
                case "class-basic":
                    return "Mermaid: Class diagram with inheritance";
                case "mermaid-er":
                case "er-basic":
                    return "Mermaid: Entity-relationship database schema";
                case "mermaid-gantt":
                case "gantt-basic":
                    return "Mermaid: Project timeline with sections";
                case "mermaid-pie":
                case "pie-basic":
                    return "Mermaid: Data visualization pie chart";

                // PlantUML templates
                case "plantuml-sequence":
                    return "PlantUML: Sequence diagram with activation";
                case "plantuml-class":
                    return "PlantUML: Class diagram with inheritance";
                case "plantuml-activity":
                    return "PlantUML: Activity diagram with decision flow";
                case "plantuml-state":
                    return "PlantUML: State machine with transitions";
                case "plantuml-usecase":
                    return "PlantUML: Use case diagram with actors";
                case "plantuml-component":
                    return "PlantUML: Component diagram with packages";
                case "plantuml-er":
                    return "PlantUML: Entity-relationship with attributes";

                default:
                    return "Diagram template";
            }
        }

        // Get format for template
        public static string get_template_format(string name) {
            if (name.has_prefix("plantuml-")) {
                return "PlantUML";
            } else if (name.has_prefix("mermaid-")) {
                return "Mermaid";
            }
            return "Unknown";
        }
    }
}
