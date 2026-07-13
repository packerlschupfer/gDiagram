namespace GDiagram {
    public class DiagramTemplates : Object {

        // =====================================================================
        // Mermaid Templates
        // =====================================================================

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

        public static string USER_JOURNEY_BASIC = """journey
    title My working day
    section Go to work
      Make tea: 5: Me
      Go upstairs: 3: Me, Cat
      Do work: 1: Me, Cat
    section Lunch
      Eat lunch: 5: Me
      Take a walk: 4: Me
    section Go home
      Watch TV: 5: Me, Cat
      Sleep: 5: Me, Cat
""";

        public static string GIT_GRAPH_BASIC = """gitGraph
    commit id: "Initial commit"
    commit id: "Add README"
    branch develop
    checkout develop
    commit id: "Feature A"
    commit id: "Feature B"
    checkout main
    merge develop id: "Merge develop"
    commit id: "Release" tag: "v1.0"
""";

        public static string MINDMAP_BASIC = """mindmap
  root((Tech Stack))
    Frontend
      React
      TypeScript
      CSS
    Backend
      Node.js
      REST API
      PostgreSQL
    DevOps
      Docker
      CI/CD
      Monitoring
""";

        public static string TIMELINE_BASIC = """timeline
    title History of the Web
    section 1990s
        1991 : World Wide Web
        1994 : Netscape Navigator
        1995 : JavaScript invented
    section 2000s
        2004 : Ajax and Web 2.0
        2007 : iPhone — mobile web
    section 2010s
        2012 : Responsive design
        2015 : React released
        2017 : Progressive Web Apps
    2020 : WebAssembly mainstream
""";

        public static string QUADRANT_BASIC = """quadrantChart
    title Feature Prioritization
    x-axis Low Effort --> High Effort
    y-axis Low Impact --> High Impact
    quadrant-1 Quick Wins
    quadrant-2 Major Projects
    quadrant-3 Fill-ins
    quadrant-4 Thankless Tasks
    Fix Auth Bug: [0.15, 0.85]
    New Dashboard: [0.75, 0.90]
    Update Docs: [0.25, 0.30]
    Redesign Logo: [0.80, 0.35]
    Add Dark Mode: [0.45, 0.65]
    Search Feature: [0.60, 0.75]
""";

        public static string XYCHART_BASIC = """xychart-beta
    title "Monthly Sales"
    x-axis [Jan, Feb, Mar, Apr, May, Jun]
    y-axis "Revenue ($k)" 0 --> 60
    bar [38, 42, 35, 51, 58, 47]
    line [38, 42, 35, 51, 58, 47]
""";

        public static string KANBAN_BASIC = """kanban
todo[To Do]
    t1[Write unit tests]
    t2[Update documentation]
    t3[Fix login edge case]
inprogress[In Progress]
    t4[Implement dark mode]
    t5[API rate limiting]
done[Done]
    t6[User authentication]
    t7[Database migrations]
    t8[CI/CD pipeline setup]
""";

        public static string SANKEY_BASIC = """sankey-beta
    Energy Input,Solar,100
    Energy Input,Wind,80
    Energy Input,Gas,200
    Solar,Grid,90
    Solar,Storage,10
    Wind,Grid,75
    Wind,Storage,5
    Gas,Grid,180
    Gas,Loss,20
    Grid,Homes,200
    Grid,Industry,100
    Grid,Loss,45
    Storage,Grid,15
""";

        public static string REQUIREMENT_BASIC = """requirementDiagram

requirement auth_req {
    id: 1
    text: Users shall authenticate with email and password
    risk: low
    verifymethod: test
}

functionalRequirement perf_req {
    id: 2
    text: API responses must be under 200ms at p99
    risk: medium
    verifymethod: inspection
}

performanceRequirement scale_req {
    id: 3
    text: System shall support 10,000 concurrent users
    risk: high
    verifymethod: demonstration
}

element frontend {
    type: component
}

element backend {
    type: component
}

frontend - satisfies -> auth_req
backend - satisfies -> perf_req
backend - satisfies -> scale_req
""";

        public static string BLOCK_BASIC = """block-beta
    columns 3
    browser["Browser"] api["API Gateway"] db[("Database")]
    browser --> api --> db
    block:cache
      redis["Redis Cache"]
    end
    api --> redis
""";

        public static string PACKET_BASIC = """packet-beta
    0-15: "Source Port"
    16-31: "Destination Port"
    32-63: "Sequence Number"
    64-95: "Acknowledgment Number"
    96-99: "Data Offset"
    100-105: "Reserved"
    106-111: "Control Bits"
    112-127: "Window Size"
    128-143: "Checksum"
    144-159: "Urgent Pointer"
""";

        public static string C4_BASIC = """c4context
    title System Context — Online Shop
    Person(customer, "Customer", "Shops online")
    Person(admin, "Admin", "Manages products")
    System(shop, "Shopping App", "Web and mobile front-end")
    System_Ext(payment, "Payment Gateway", "Processes payments")
    System_Ext(email, "Email Service", "Sends notifications")
    Rel(customer, shop, "Browses and orders")
    Rel(admin, shop, "Manages catalogue")
    Rel(shop, payment, "Charges via")
    Rel(shop, email, "Sends emails via")
""";

        public static string ARCHITECTURE_BASIC = """architecture-beta
    group cloud[Cloud]
    service api(internet)[API Gateway] in cloud
    service app(server)[App Server] in cloud
    service db(database)[Database] in cloud

    group clients[Clients]
    service browser(internet)[Browser]
    service mobile(internet)[Mobile App]

    browser:R --> L:api
    mobile:R --> L:api
    api:R --> L:app
    app:B --> T:db
""";

        public static string ZENUML_BASIC = """zenuml
    title Order Checkout
    @Actor Customer
    @OrderService OrderService
    @Database Database
    @EmailService EmailService

    Customer -> OrderService.checkout(cart) {
        OrderService -> Database.saveOrder(cart) {
            return orderId
        }
        OrderService -> EmailService.sendConfirmation(orderId) {
            return
        }
        return confirmation
    }
""";

        public static string RADAR_BASIC = """radar-beta
    title Skills Assessment
    max 10
    axis Frontend["Frontend"]
    axis Backend["Backend"]
    axis DevOps["DevOps"]
    axis Testing["Testing"]
    axis Architecture["Architecture"]
    curve Alice["Alice"] {
        Frontend: 8, Backend: 6, DevOps: 5, Testing: 7, Architecture: 7
    }
    curve Bob["Bob"] {
        Frontend: 5, Backend: 9, DevOps: 7, Testing: 6, Architecture: 8
    }
""";

        public static string TREEMAP_BASIC = """treemap-beta
    title Software Project Budget
    "Engineering"
      "Frontend": 150000
      "Backend": 200000
      "Infrastructure": 150000
    "Marketing"
      "Digital Ads": 120000
      "Events": 80000
    "Operations": 100000
""";

        // =====================================================================
        // PlantUML Templates
        // =====================================================================

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

        public static string PLANTUML_MINDMAP = """@startmindmap
* Project
** Planning
*** Requirements
*** Timeline
** Development
*** Frontend
**** UI Components
**** State Management
*** Backend
**** REST API
**** Database
** Delivery
*** Testing
*** Deployment
@endmindmap
""";

        public static string PLANTUML_WBS = """@startwbs
* Project Deliverables
** Planning Phase
*** Project Charter
*** Risk Register
*** Stakeholder List
** Development Phase
*** Backend API
**** Authentication Module
**** Data Layer
*** Frontend UI
**** Dashboard
**** Settings
** Launch Phase
*** QA Testing
*** Production Deploy
@endwbs
""";

        public static string PLANTUML_CHRONOLOGY = """@startchronology
title Product Roadmap 2025
[Kickoff] happens on 2025-01-01
[Design Complete] happens on 2025-02-15
[Alpha Release] happens on 2025-04-01
[Beta Testing] happens on 2025-05-15
[Public Launch] happens on 2025-07-01
[Version 2.0] happens on 2025-12-01
@endchronology
""";

        public static string PLANTUML_TIMING = """@startuml
title Network Signal Timing

binary "Clock" as CLK
binary "Data Valid" as DV
concise "Bus State" as BUS

@0
CLK is HIGH
DV is LOW
BUS is Idle

@5
CLK is LOW

@10
CLK is HIGH
DV is HIGH
BUS is Active

@15
CLK is LOW

@20
CLK is HIGH

@25
CLK is LOW
DV is LOW
BUS is Idle
@enduml
""";

        public static string PLANTUML_NWDIAG = """@startuml
nwdiag {
  network Internet {
    address = "203.0.0.x/24"
    LoadBalancer [address = "203.0.0.1"]
  }
  network DMZ {
    address = "10.0.1.x/24"
    LoadBalancer [address = "10.0.1.1"]
    WebServer1 [address = "10.0.1.2"]
    WebServer2 [address = "10.0.1.3"]
  }
  network Internal {
    address = "10.0.2.x/24"
    WebServer1 [address = "10.0.2.1"]
    WebServer2 [address = "10.0.2.2"]
    Database [address = "10.0.2.10"]
  }
}
@enduml
""";

        public static string PLANTUML_ARCHIMATE = """@startuml
archimate #Business "Customer" as customer <<Actor>>
archimate #Business "Order Management" as order_mgmt <<Function>>
archimate #Application "Order App" as order_app <<Application>>
archimate #Technology "App Server" as server <<Node>>
archimate #Technology "Database" as db <<Artifact>>

customer -up-> order_mgmt : Uses
order_mgmt --> order_app : Realized by
order_app -down-> server : Runs on
server --> db : Stores in
@enduml
""";

        public static string PLANTUML_C4_KUBERNETES = """@startuml
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
@enduml
""";

        public static string PLANTUML_JSON = """@startjson
{
  "user": {
    "name": "Alice",
    "age": 30,
    "email": "alice@example.com"
  },
  "address": {
    "street": "123 Main St",
    "city": "Springfield",
    "country": "US"
  },
  "hobbies": [
    "reading",
    "cycling",
    "photography"
  ],
  "active": true,
  "score": 9.5
}
@endjson
""";

        public static string PLANTUML_YAML = """@startyaml
name: Alice
age: 30
email: alice@example.com
address:
  street: 123 Main St
  city: Springfield
  country: US
hobbies:
  - reading
  - cycling
  - photography
active: true
database:
  host: localhost
  port: 5432
  name: myapp
  pool_size: 10
@endyaml
""";

        // =====================================================================
        // Lookup helpers
        // =====================================================================

        public static string? get_template(string name) {
            switch (name.down()) {
                // Mermaid
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
                case "mermaid-user-journey":
                case "user-journey-basic":
                    return USER_JOURNEY_BASIC;
                case "mermaid-git-graph":
                case "git-graph-basic":
                    return GIT_GRAPH_BASIC;
                case "mermaid-mindmap":
                    return MINDMAP_BASIC;
                case "mermaid-timeline":
                    return TIMELINE_BASIC;
                case "mermaid-quadrant":
                    return QUADRANT_BASIC;
                case "mermaid-xychart":
                    return XYCHART_BASIC;
                case "mermaid-kanban":
                    return KANBAN_BASIC;
                case "mermaid-sankey":
                    return SANKEY_BASIC;
                case "mermaid-requirement":
                    return REQUIREMENT_BASIC;
                case "mermaid-block":
                    return BLOCK_BASIC;
                case "mermaid-packet":
                    return PACKET_BASIC;
                case "mermaid-c4":
                    return C4_BASIC;
                case "mermaid-architecture":
                    return ARCHITECTURE_BASIC;
                case "mermaid-zenuml":
                    return ZENUML_BASIC;
                case "mermaid-radar":
                    return RADAR_BASIC;
                case "mermaid-treemap":
                    return TREEMAP_BASIC;
                // PlantUML
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
                case "plantuml-mindmap":
                    return PLANTUML_MINDMAP;
                case "plantuml-wbs":
                    return PLANTUML_WBS;
                case "plantuml-chronology":
                    return PLANTUML_CHRONOLOGY;
                case "plantuml-timing":
                    return PLANTUML_TIMING;
                case "plantuml-nwdiag":
                    return PLANTUML_NWDIAG;
                case "plantuml-archimate":
                    return PLANTUML_ARCHIMATE;
                case "plantuml-c4-kubernetes":
                    return PLANTUML_C4_KUBERNETES;
                case "plantuml-json":
                    return PLANTUML_JSON;
                case "plantuml-yaml":
                    return PLANTUML_YAML;
                default:
                    return null;
            }
        }

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
                "mermaid-pie",
                "mermaid-user-journey",
                "mermaid-git-graph",
                "mermaid-mindmap",
                "mermaid-timeline",
                "mermaid-quadrant",
                "mermaid-xychart",
                "mermaid-kanban",
                "mermaid-sankey",
                "mermaid-requirement",
                "mermaid-block",
                "mermaid-packet",
                "mermaid-c4",
                "mermaid-architecture",
                "mermaid-zenuml",
                "mermaid-radar",
                "mermaid-treemap"
            };
        }

        public static string[] get_plantuml_template_names() {
            return {
                "plantuml-sequence",
                "plantuml-class",
                "plantuml-activity",
                "plantuml-state",
                "plantuml-usecase",
                "plantuml-component",
                "plantuml-er",
                "plantuml-mindmap",
                "plantuml-wbs",
                "plantuml-chronology",
                "plantuml-timing",
                "plantuml-nwdiag",
                "plantuml-archimate",
                "plantuml-c4-kubernetes",
                "plantuml-json",
                "plantuml-yaml"
            };
        }

        public static string[] get_template_names() {
            var mermaid = get_mermaid_template_names();
            var plantuml = get_plantuml_template_names();
            var all = new string[mermaid.length + plantuml.length];
            int i = 0;
            foreach (var name in mermaid) all[i++] = name;
            foreach (var name in plantuml) all[i++] = name;
            return all;
        }

        public static string get_template_description(string name) {
            switch (name) {
                // Mermaid
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
                case "mermaid-user-journey":
                case "user-journey-basic":
                    return "Mermaid: User journey map with scores and actors";
                case "mermaid-git-graph":
                case "git-graph-basic":
                    return "Mermaid: Git commit graph with branches and merges";
                case "mermaid-mindmap":
                    return "Mermaid: Radial mind map";
                case "mermaid-timeline":
                    return "Mermaid: Historical timeline with sections";
                case "mermaid-quadrant":
                    return "Mermaid: 2×2 quadrant prioritization chart";
                case "mermaid-xychart":
                    return "Mermaid: Bar and line XY chart";
                case "mermaid-kanban":
                    return "Mermaid: Kanban board with columns and cards";
                case "mermaid-sankey":
                    return "Mermaid: Sankey energy flow diagram";
                case "mermaid-requirement":
                    return "Mermaid: Requirements traceability diagram";
                case "mermaid-block":
                    return "Mermaid: Block architecture diagram";
                case "mermaid-packet":
                    return "Mermaid: Network packet / bit-field layout";
                case "mermaid-c4":
                    return "Mermaid: C4 system context diagram";
                case "mermaid-architecture":
                    return "Mermaid: Cloud architecture with groups and services";
                case "mermaid-zenuml":
                    return "Mermaid: ZenUML sequence with nesting";
                case "mermaid-radar":
                    return "Mermaid: Radar / spider chart for comparisons";
                case "mermaid-treemap":
                    return "Mermaid: Treemap for proportional data";
                // PlantUML
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
                case "plantuml-mindmap":
                    return "PlantUML: Mind map with branches";
                case "plantuml-wbs":
                    return "PlantUML: Work breakdown structure";
                case "plantuml-chronology":
                    return "PlantUML: Project chronology / milestone timeline";
                case "plantuml-timing":
                    return "PlantUML: Signal timing diagram";
                case "plantuml-nwdiag":
                    return "PlantUML: Network topology with subnets";
                case "plantuml-archimate":
                    return "PlantUML: ArchiMate enterprise architecture";
                case "plantuml-c4-kubernetes":
                    return "PlantUML: C4 Kubernetes cluster (context / drill-down)";
                case "plantuml-json":
                    return "PlantUML: JSON data visualisation";
                case "plantuml-yaml":
                    return "PlantUML: YAML data visualisation";
                default:
                    return "Diagram template";
            }
        }

        public static string get_template_format(string name) {
            if (name.has_prefix("plantuml-")) return "PlantUML";
            if (name.has_prefix("mermaid-"))  return "Mermaid";
            return "Unknown";
        }
    }
}
