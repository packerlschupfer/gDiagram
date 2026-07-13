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
exports.TemplateProvider = void 0;
const vscode = __importStar(require("vscode"));
const BUILTIN_TEMPLATES = [
    // PlantUML templates
    {
        label: '$(symbol-method) PlantUML: Sequence Diagram',
        description: 'Interaction between participants over time',
        language: 'plantuml',
        template: `@startuml
title Sequence Diagram

participant "Client" as client
participant "Server" as server
participant "Database" as db

client -> server : HTTP Request
activate server

server -> db : Query
activate db
db --> server : Result
deactivate db

server --> client : HTTP Response
deactivate server

@enduml`,
    },
    {
        label: '$(symbol-class) PlantUML: Class Diagram',
        description: 'Classes, interfaces, and relationships',
        language: 'plantuml',
        template: `@startuml
title Class Diagram

abstract class Animal {
  + name : String
  + age : int
  + makeSound() : void
}

class Dog extends Animal {
  + breed : String
  + fetch() : void
}

class Cat extends Animal {
  + indoor : boolean
  + purr() : void
}

interface Trainable {
  + train(command: String) : boolean
}

Dog ..|> Trainable

@enduml`,
    },
    {
        label: '$(debug-step-into) PlantUML: Activity Diagram',
        description: 'Workflow and process flow',
        language: 'plantuml',
        template: `@startuml
title Activity Diagram

start

:Receive Order;

if (Payment valid?) then (yes)
  :Process Payment;
  :Ship Order;
  if (Domestic?) then (yes)
    :Standard Shipping;
  else (no)
    :International Shipping;
  endif
  :Send Confirmation;
else (no)
  :Reject Order;
  :Notify Customer;
endif

stop

@enduml`,
    },
    {
        label: '$(circle-outline) PlantUML: State Diagram',
        description: 'State machine transitions',
        language: 'plantuml',
        template: `@startuml
title State Diagram

[*] --> Idle

Idle --> Processing : start
Processing --> Completed : success
Processing --> Failed : error
Failed --> Idle : retry
Completed --> [*]

state Processing {
  [*] --> Validating
  Validating --> Executing : valid
  Validating --> [*] : invalid
  Executing --> [*] : done
}

@enduml`,
    },
    {
        label: '$(person) PlantUML: Use Case Diagram',
        description: 'Actor and use case relationships',
        language: 'plantuml',
        template: `@startuml
title Use Case Diagram

left to right direction

actor Customer
actor Admin

rectangle "Online Store" {
  usecase "Browse Products" as UC1
  usecase "Place Order" as UC2
  usecase "Make Payment" as UC3
  usecase "Manage Inventory" as UC4
  usecase "View Reports" as UC5
}

Customer --> UC1
Customer --> UC2
UC2 --> UC3 : <<include>>
Admin --> UC4
Admin --> UC5

@enduml`,
    },
    {
        label: '$(package) PlantUML: Component Diagram',
        description: 'Software component architecture',
        language: 'plantuml',
        template: `@startuml
title Component Diagram

package "Frontend" {
  [Web App] as webapp
  [Mobile App] as mobile
}

package "Backend" {
  [API Gateway] as gateway
  [Auth Service] as auth
  [Order Service] as orders
  [Notification Service] as notify
}

database "Data Store" {
  [PostgreSQL] as db
  [Redis Cache] as cache
}

webapp --> gateway
mobile --> gateway
gateway --> auth
gateway --> orders
orders --> db
orders --> cache
orders --> notify

@enduml`,
    },
    {
        label: '$(symbol-object) PlantUML: Object Diagram',
        description: 'Object instances and relationships',
        language: 'plantuml',
        template: `@startuml
title Object Diagram

object "john : Person" as john {
  name = "John Doe"
  age = 30
}

object "acme : Company" as acme {
  name = "Acme Corp"
  founded = 2010
}

object "dev : Department" as dev {
  name = "Engineering"
  headcount = 25
}

john --> acme : works at
john --> dev : belongs to
dev --> acme : part of

@enduml`,
    },
    {
        label: '$(server) PlantUML: Deployment Diagram',
        description: 'Infrastructure and deployment topology',
        language: 'plantuml',
        template: `@startuml
title Deployment Diagram

node "Load Balancer" as lb {
  [Nginx]
}

node "App Server 1" as app1 {
  [Web Application]
  [Background Worker]
}

node "App Server 2" as app2 {
  [Web Application] as wa2
  [Background Worker] as bw2
}

node "Database Server" as dbserver {
  database "PostgreSQL" as db
  database "Redis" as redis
}

lb --> app1
lb --> app2
app1 --> db
app1 --> redis
app2 --> db
app2 --> redis

@enduml`,
    },
    {
        label: '$(database) PlantUML: ER Diagram',
        description: 'Entity-relationship model',
        language: 'plantuml',
        template: `@startuml
title Entity Relationship Diagram

entity "Customer" {
  * customer_id : int <<PK>>
  --
  * name : varchar
  email : varchar
  phone : varchar
}

entity "Order" {
  * order_id : int <<PK>>
  --
  * customer_id : int <<FK>>
  * order_date : date
  total : decimal
}

entity "OrderItem" {
  * item_id : int <<PK>>
  --
  * order_id : int <<FK>>
  * product_id : int <<FK>>
  quantity : int
}

entity "Product" {
  * product_id : int <<PK>>
  --
  * name : varchar
  price : decimal
  category : varchar
}

Customer ||--o{ Order
Order ||--|{ OrderItem
Product ||--o{ OrderItem

@enduml`,
    },
    {
        label: '$(type-hierarchy) PlantUML: Mind Map',
        description: 'Hierarchical mind map',
        language: 'plantuml',
        template: `@startmindmap
title Project Planning

* Project
** Phase 1
*** Research
*** Requirements
*** Design
** Phase 2
*** Development
*** Testing
*** Code Review
** Phase 3
*** Deployment
*** Monitoring
*** Documentation

@endmindmap`,
    },
    {
        label: '$(list-tree) PlantUML: WBS Diagram',
        description: 'Work breakdown structure',
        language: 'plantuml',
        template: `@startwbs
title Work Breakdown Structure

* Website Redesign
** Design
*** Wireframes
*** Mockups
*** User Testing
** Development
*** Frontend
**** HTML/CSS
**** JavaScript
*** Backend
**** API
**** Database
** Deployment
*** Staging
*** Production
*** Monitoring

@endwbs`,
    },
    {
        label: '$(calendar) PlantUML: Gantt Chart',
        description: 'Project schedule and timeline',
        language: 'plantuml',
        template: `@startgantt
title Project Timeline

Project starts 2024-01-01

[Requirements] lasts 10 days
[Design] lasts 15 days
[Design] starts at [Requirements]'s end
[Development] lasts 30 days
[Development] starts at [Design]'s end
[Testing] lasts 15 days
[Testing] starts at [Development]'s end
[Deployment] lasts 5 days
[Deployment] starts at [Testing]'s end

@endgantt`,
    },
    {
        label: '$(json) PlantUML: JSON Visualization',
        description: 'Render JSON data as a tree',
        language: 'plantuml',
        template: `@startjson
{
  "name": "gDiagram",
  "version": "0.1.0",
  "features": [
    "PlantUML",
    "Mermaid",
    "Live Preview"
  ],
  "config": {
    "theme": "auto",
    "renderer": "graphviz"
  }
}
@endjson`,
    },
    {
        label: '$(file-code) PlantUML: YAML Visualization',
        description: 'Render YAML data as a tree',
        language: 'plantuml',
        template: `@startyaml
name: gDiagram
version: 0.1.0
features:
  - PlantUML
  - Mermaid
  - Live Preview
config:
  theme: auto
  renderer: graphviz
@endyaml`,
    },
    {
        label: '$(timeline-pin) PlantUML: Chronology Diagram',
        description: 'Timeline of events',
        language: 'plantuml',
        template: `@startuml
title Project Chronology

concise "Development" as dev
concise "Testing" as test
concise "Release" as rel

@0
dev is "Planning"
test is {-}
rel is {-}

@5
dev is "Coding"

@15
dev is "Review"
test is "QA"

@25
dev is {-}
test is "UAT"
rel is "Staging"

@30
test is {-}
rel is "Production"

@enduml`,
    },
    {
        label: '$(pulse) PlantUML: Timing Diagram',
        description: 'Signal timing and waveforms',
        language: 'plantuml',
        template: `@startuml
title Timing Diagram

clock "Clock" as clk with period 2
binary "Enable" as en
binary "Data" as data
binary "Output" as out

@0
en is low
data is low
out is low

@2
en is high

@4
data is high

@6
out is high

@10
en is low
out is low

@12
data is low

@enduml`,
    },
    {
        label: '$(globe) PlantUML: Network Diagram',
        description: 'Network topology (nwdiag)',
        language: 'plantuml',
        template: `@startuml
nwdiag {
  network internet {
    address = "Internet"
    web01 [address = "210.x.x.1"]
    web02 [address = "210.x.x.2"]
  }

  network dmz {
    address = "172.x.0.x/24"
    web01 [address = "172.x.0.1"]
    web02 [address = "172.x.0.2"]
    db01 [address = "172.x.0.100"]
  }

  network internal {
    address = "192.168.x.x/24"
    db01 [address = "192.168.0.100"]
    app01 [address = "192.168.0.200"]
  }
}
@enduml`,
    },
    {
        label: '$(layers) PlantUML: Archimate Diagram',
        description: 'Enterprise architecture (ArchiMate)',
        language: 'plantuml',
        template: `@startuml
title ArchiMate Diagram

!define Junction_Or circle #black

rectangle "Business Layer" <<Business>> {
  rectangle "Customer Service" as cs <<BusinessProcess>>
  rectangle "Order Management" as om <<BusinessProcess>>
}

rectangle "Application Layer" <<Application>> {
  rectangle "CRM System" as crm <<ApplicationComponent>>
  rectangle "Order System" as osys <<ApplicationComponent>>
}

rectangle "Technology Layer" <<Technology>> {
  rectangle "App Server" as app <<Node>>
  rectangle "Database" as db <<Node>>
}

cs --> crm : <<serving>>
om --> osys : <<serving>>
crm --> app : <<realization>>
osys --> app : <<realization>>
app --> db : <<serving>>

@enduml`,
    },
    {
        label: '$(graph) PlantUML: DOT Graph',
        description: 'Raw Graphviz DOT graph',
        language: 'plantuml',
        template: `@startuml
digraph G {
  rankdir=LR
  node [shape=box style=rounded]

  A [label="Start"]
  B [label="Process"]
  C [label="Decision" shape=diamond]
  D [label="Output A"]
  E [label="Output B"]
  F [label="End"]

  A -> B
  B -> C
  C -> D [label="yes"]
  C -> E [label="no"]
  D -> F
  E -> F
}
@enduml`,
    },
    {
        label: '$(window) PlantUML: Salt Wireframe',
        description: 'UI wireframe/mockup',
        language: 'plantuml',
        template: `@startsalt
{
  Login Form
  ==
  {
    Username: | "admin    "
    Password: | "****     "
  }
  [  Cancel  ] | [  Login  ]
}
@endsalt`,
    },
    {
        label: '$(database) PlantUML: Chen ER Diagram',
        description: 'Chen notation entity-relationship',
        language: 'plantuml',
        template: `@startuml
title Chen ER Notation

entity Customer {
}

entity Order {
}

diamond places

Customer -- places
places -- Order

@enduml`,
    },
    {
        label: '$(symbol-keyword) PlantUML: EBNF Diagram',
        description: 'Extended Backus-Naur Form syntax diagram',
        language: 'plantuml',
        template: `@startuml
title EBNF Grammar

<expression> ::= <term> (("+" | "-") <term>)*
<term> ::= <factor> (("*" | "/") <factor>)*
<factor> ::= <number> | "(" <expression> ")"
<number> ::= <digit>+
<digit> ::= "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9"

@enduml`,
    },
    {
        label: '$(regex) PlantUML: Regex Diagram',
        description: 'Regular expression visualization',
        language: 'plantuml',
        template: `@startuml
title Regex Visualization

<regex> ::= <term> ("|" <term>)*
<term> ::= <factor>+
<factor> ::= <atom> <quantifier>?
<atom> ::= <char> | "." | "(" <regex> ")"
<quantifier> ::= "*" | "+" | "?" | "{" <number> "}"

@enduml`,
    },
    {
        label: '$(list-tree) PlantUML: Tree Diagram',
        description: 'Hierarchical tree structure',
        language: 'plantuml',
        template: `@startuml
title File System Tree

salt
{
  {T
    + /home
    ++ user
    +++ Documents
    ++++ report.pdf
    ++++ notes.txt
    +++ Downloads
    ++++ image.png
    +++ .config
    ++++ settings.json
  }
}
@enduml`,
    },
    {
        label: '$(circuit-board) PlantUML: Ditaa Diagram',
        description: 'ASCII art to diagram',
        language: 'plantuml',
        template: `@startditaa
+--------+   +--------+   +--------+
|        |   |        |   |        |
| Client +-->| Server +-->|  DB    |
|        |   |        |   |        |
+--------+   +---+----+   +--------+
                 |
                 v
             +---+----+
             |        |
             | Cache  |
             |        |
             +--------+
@endditaa`,
    },
    {
        label: '$(checklist) PlantUML: Board Diagram',
        description: 'Kanban-style board',
        language: 'plantuml',
        template: `@startuml
title Project Board

map "To Do" as todo {
  Task 1 => Design UI
  Task 2 => Write tests
}

map "In Progress" as progress {
  Task 3 => Implement API
  Task 4 => Code review
}

map "Done" as done {
  Task 5 => Setup CI
  Task 6 => Database schema
}

todo --> progress : move
progress --> done : complete

@enduml`,
    },
    // Mermaid templates
    {
        label: '$(git-merge) Mermaid: Flowchart',
        description: 'Flow diagram with nodes and edges',
        language: 'mermaid',
        template: `flowchart TD
    A[Start] --> B{Decision}
    B -->|Yes| C[Process A]
    B -->|No| D[Process B]
    C --> E[Step 1]
    C --> F[Step 2]
    D --> G[Step 3]
    E --> H[End]
    F --> H
    G --> H`,
    },
    {
        label: '$(symbol-method) Mermaid: Sequence Diagram',
        description: 'Interaction between participants',
        language: 'mermaid',
        template: `sequenceDiagram
    participant C as Client
    participant S as Server
    participant D as Database

    C->>S: HTTP Request
    activate S
    S->>D: Query
    activate D
    D-->>S: Result
    deactivate D
    S-->>C: HTTP Response
    deactivate S

    Note over C,S: Communication complete`,
    },
    {
        label: '$(circle-outline) Mermaid: State Diagram',
        description: 'State machine with transitions',
        language: 'mermaid',
        template: `stateDiagram-v2
    [*] --> Idle

    Idle --> Processing : start
    Processing --> Completed : success
    Processing --> Failed : error
    Failed --> Idle : retry
    Completed --> [*]

    state Processing {
        [*] --> Validating
        Validating --> Executing : valid
        Executing --> [*] : done
    }`,
    },
    {
        label: '$(symbol-class) Mermaid: Class Diagram',
        description: 'Classes with attributes and methods',
        language: 'mermaid',
        template: `classDiagram
    class Animal {
        +String name
        +int age
        +makeSound() void
    }

    class Dog {
        +String breed
        +fetch() void
    }

    class Cat {
        +bool indoor
        +purr() void
    }

    class Trainable {
        <<interface>>
        +train(command) bool
    }

    Animal <|-- Dog
    Animal <|-- Cat
    Trainable <|.. Dog`,
    },
    {
        label: '$(database) Mermaid: ER Diagram',
        description: 'Entity-relationship model',
        language: 'mermaid',
        template: `erDiagram
    CUSTOMER ||--o{ ORDER : places
    ORDER ||--|{ LINE-ITEM : contains
    PRODUCT ||--o{ LINE-ITEM : "ordered in"

    CUSTOMER {
        int id PK
        string name
        string email
    }

    ORDER {
        int id PK
        int customer_id FK
        date created
        float total
    }

    LINE-ITEM {
        int id PK
        int order_id FK
        int product_id FK
        int quantity
    }

    PRODUCT {
        int id PK
        string name
        float price
    }`,
    },
    {
        label: '$(calendar) Mermaid: Gantt Chart',
        description: 'Project schedule timeline',
        language: 'mermaid',
        template: `gantt
    title Project Schedule
    dateFormat YYYY-MM-DD

    section Planning
        Requirements     :a1, 2024-01-01, 10d
        Design           :a2, after a1, 15d

    section Development
        Frontend         :b1, after a2, 20d
        Backend          :b2, after a2, 25d
        Integration      :b3, after b1, 10d

    section Testing
        QA Testing       :c1, after b3, 15d
        UAT              :c2, after c1, 10d

    section Release
        Deployment       :d1, after c2, 5d`,
    },
    {
        label: '$(pie-chart) Mermaid: Pie Chart',
        description: 'Pie chart with percentages',
        language: 'mermaid',
        template: `pie title Technology Usage
    "JavaScript" : 35
    "Python" : 25
    "TypeScript" : 20
    "Go" : 12
    "Rust" : 8`,
    },
    {
        label: '$(person) Mermaid: User Journey',
        description: 'User experience journey map',
        language: 'mermaid',
        template: `journey
    title User Shopping Journey
    section Browse
        Visit homepage: 5: Customer
        Search products: 4: Customer
        View product details: 4: Customer
    section Purchase
        Add to cart: 3: Customer
        Checkout: 2: Customer
        Enter payment: 2: Customer
    section Post-Purchase
        Receive confirmation: 5: Customer
        Track shipping: 4: Customer
        Receive product: 5: Customer`,
    },
    {
        label: '$(git-branch) Mermaid: Git Graph',
        description: 'Git branch and commit visualization',
        language: 'mermaid',
        template: `gitGraph
    commit id: "Initial"
    branch develop
    checkout develop
    commit id: "Feature A"
    commit id: "Feature B"
    branch feature-x
    checkout feature-x
    commit id: "WIP"
    commit id: "Complete"
    checkout develop
    merge feature-x
    checkout main
    merge develop tag: "v1.0"
    commit id: "Hotfix"`,
    },
    {
        label: '$(type-hierarchy) Mermaid: Mindmap',
        description: 'Hierarchical mind map',
        language: 'mermaid',
        template: `mindmap
    root((Project))
        Design
            UI/UX
            Architecture
            Prototyping
        Development
            Frontend
                React
                CSS
            Backend
                API
                Database
        Testing
            Unit Tests
            Integration
            E2E
        Deployment
            CI/CD
            Monitoring`,
    },
    {
        label: '$(timeline-pin) Mermaid: Timeline',
        description: 'Chronological events',
        language: 'mermaid',
        template: `timeline
    title History of Web Development
    section 1990s
        1991 : First website
        1995 : JavaScript created
        1996 : CSS introduced
    section 2000s
        2004 : Web 2.0 era
        2006 : jQuery released
        2008 : Chrome browser
    section 2010s
        2010 : AngularJS
        2013 : React
        2014 : Vue.js
    section 2020s
        2020 : Deno
        2022 : Bun
        2023 : AI-assisted coding`,
    },
    {
        label: '$(graph-scatter) Mermaid: Quadrant Chart',
        description: 'Four-quadrant analysis',
        language: 'mermaid',
        template: `quadrantChart
    title Priority Matrix
    x-axis Low Effort --> High Effort
    y-axis Low Impact --> High Impact
    quadrant-1 Plan carefully
    quadrant-2 Do first
    quadrant-3 Delegate
    quadrant-4 Quick wins
    Feature A: [0.8, 0.9]
    Feature B: [0.3, 0.8]
    Feature C: [0.7, 0.3]
    Feature D: [0.2, 0.2]
    Feature E: [0.5, 0.6]`,
    },
    {
        label: '$(graph-line) Mermaid: XY Chart',
        description: 'Line and bar charts',
        language: 'mermaid',
        template: `xychart-beta
    title "Monthly Revenue"
    x-axis [Jan, Feb, Mar, Apr, May, Jun, Jul, Aug, Sep, Oct, Nov, Dec]
    y-axis "Revenue (USD)" 0 --> 50000
    bar [12000, 15000, 18000, 22000, 25000, 28000, 30000, 32000, 35000, 38000, 42000, 48000]
    line [10000, 13000, 16000, 20000, 23000, 26000, 28000, 30000, 33000, 36000, 40000, 45000]`,
    },
    {
        label: '$(checklist) Mermaid: Kanban Board',
        description: 'Task board with columns',
        language: 'mermaid',
        template: `kanban
    Todo
        Design homepage
        Write API docs
        Set up CI/CD
    In Progress
        Implement auth
        Build dashboard
    Review
        Fix login bug
        Update tests
    Done
        Database schema
        Project setup`,
    },
    {
        label: '$(graph) Mermaid: Sankey Diagram',
        description: 'Flow quantity visualization',
        language: 'mermaid',
        template: `sankey-beta
    Source A,Process X,50
    Source A,Process Y,30
    Source B,Process X,20
    Source B,Process Z,40
    Process X,Output 1,45
    Process X,Output 2,25
    Process Y,Output 1,30
    Process Z,Output 2,40`,
    },
    {
        label: '$(verified) Mermaid: Requirement Diagram',
        description: 'Requirements and traceability',
        language: 'mermaid',
        template: `requirementDiagram

    requirement "User Authentication" {
        id: REQ-001
        text: System shall support user login
        risk: high
        verifymethod: test
    }

    requirement "Password Policy" {
        id: REQ-002
        text: Passwords must be 8+ characters
        risk: medium
        verifymethod: inspection
    }

    element "Auth Module" {
        type: module
    }

    element "Login Test Suite" {
        type: testCase
    }

    "Auth Module" - satisfies -> "User Authentication"
    "Auth Module" - satisfies -> "Password Policy"
    "Login Test Suite" - verifies -> "User Authentication"`,
    },
    {
        label: '$(layout) Mermaid: Block Diagram',
        description: 'Block-based architecture diagram',
        language: 'mermaid',
        template: `block-beta
    columns 3

    block:frontend["Frontend"]
        columns 1
        WebApp["Web App"]
        MobileApp["Mobile App"]
    end

    block:backend["Backend"]
        columns 1
        API["API Gateway"]
        Auth["Auth Service"]
        Logic["Business Logic"]
    end

    block:data["Data Layer"]
        columns 1
        DB[("Database")]
        Cache[("Cache")]
    end

    frontend --> backend
    backend --> data`,
    },
    {
        label: '$(package) Mermaid: Packet Diagram',
        description: 'Network packet structure',
        language: 'mermaid',
        template: `packet-beta
    0-3: "Version"
    4-7: "IHL"
    8-15: "Type of Service"
    16-31: "Total Length"
    32-47: "Identification"
    48-50: "Flags"
    51-63: "Fragment Offset"
    64-71: "TTL"
    72-79: "Protocol"
    80-95: "Header Checksum"
    96-127: "Source Address"
    128-159: "Destination Address"`,
    },
    {
        label: '$(layers) Mermaid: C4 Context Diagram',
        description: 'C4 model system context',
        language: 'mermaid',
        template: `C4Context
    title System Context Diagram

    Person(customer, "Customer", "A user of the system")
    Person(admin, "Admin", "System administrator")

    System(webapp, "Web Application", "Main user-facing application")
    System_Ext(email, "Email Service", "Sends notifications")
    System_Ext(payment, "Payment Gateway", "Processes payments")

    Rel(customer, webapp, "Uses", "HTTPS")
    Rel(admin, webapp, "Manages", "HTTPS")
    Rel(webapp, email, "Sends emails", "SMTP")
    Rel(webapp, payment, "Processes payments", "API")`,
    },
    {
        label: '$(server-environment) Mermaid: Architecture Diagram',
        description: 'System architecture with services',
        language: 'mermaid',
        template: `architecture-beta
    group cloud(cloud)[Cloud Platform]

    service api(server)[API Server] in cloud
    service web(internet)[Web App] in cloud
    service db(database)[Database] in cloud
    service cache(database)[Cache] in cloud
    service queue(server)[Message Queue] in cloud
    service worker(server)[Worker] in cloud

    web:R --> L:api
    api:R --> L:db
    api:B --> T:cache
    api:R --> L:queue
    queue:R --> L:worker
    worker:B --> T:db`,
    },
    {
        label: '$(code) Mermaid: ZenUML Sequence',
        description: 'Code-style sequence diagram',
        language: 'mermaid',
        template: `zenuml
    title Order Processing

    Client->API.createOrder(items) {
        API->Auth.validate(token) {
            return valid
        }
        API->OrderService.process(items) {
            OrderService->DB.save(order)
            OrderService->Notification.send(email)
            return orderConfirmation
        }
        return response
    }`,
    },
    {
        label: '$(target) Mermaid: Radar Chart',
        description: 'Multi-axis comparison chart',
        language: 'mermaid',
        template: `radar-beta
    title Skill Assessment
    axis Performance, Reliability, Scalability, Security, Usability, Maintainability
    curve Team A: [4, 3, 5, 4, 3, 4]
    curve Team B: [3, 5, 3, 5, 4, 3]
    curve Team C: [5, 4, 4, 3, 5, 5]`,
    },
    {
        label: '$(list-tree) Mermaid: Treemap',
        description: 'Hierarchical area-proportional chart',
        language: 'mermaid',
        template: `treemap-beta
    title Disk Usage
    root["Storage"]
        ["Documents (4GB)"]
            ["Reports (2GB)"]
            ["Photos (1.5GB)"]
            ["Other (0.5GB)"]
        ["Applications (3GB)"]
            ["IDE (1.5GB)"]
            ["Browser (1GB)"]
            ["Tools (0.5GB)"]
        ["System (2GB)"]
            ["OS (1.5GB)"]
            ["Logs (0.5GB)"]`,
    },
];
class TemplateProvider {
    static async showTemplatePicker(client) {
        let templates = BUILTIN_TEMPLATES;
        // Try to get templates from the LSP server; fall back to built-in
        try {
            const serverTemplates = (await client.sendRequest('gdiagram/getTemplates'));
            if (serverTemplates && Array.isArray(serverTemplates) && serverTemplates.length > 0) {
                templates = serverTemplates;
            }
        }
        catch {
            // LSP not available or doesn't support this request; use built-in templates
        }
        const picked = await vscode.window.showQuickPick(templates, {
            placeHolder: 'Select a diagram template',
            matchOnDescription: true,
        });
        if (!picked) {
            return;
        }
        const doc = await vscode.workspace.openTextDocument({
            language: picked.language,
            content: picked.template,
        });
        await vscode.window.showTextDocument(doc);
    }
}
exports.TemplateProvider = TemplateProvider;
//# sourceMappingURL=TemplateProvider.js.map