# gDiagram - Comprehensive Diagram Gallery

Welcome to the complete showcase of gDiagram's capabilities!

## 🎯 What You'll Find Here

This gallery demonstrates **all 17+ diagram types** supported by gDiagram:
- ✅ 7 Mermaid diagram types with advanced features
- ✅ 10+ PlantUML diagram types with professional themes
- ✅ Real-world examples
- ✅ Best practices
- ✅ Styling techniques

---

## 📊 Mermaid Diagrams (7 Types)

### 1. Flowcharts - The Most Versatile

**Basic Flowchart:**
```mermaid
flowchart TD
    A[Start] --> B[Process]
    B --> C{Decision?}
    C -->|Yes| D[Success]
    C -->|No| E[Error]
    D --> F[End]
    E --> F
```

**Styled Flowchart:**
```mermaid
flowchart LR
    classDef success fill:#90EE90,stroke:#228B22,stroke-width:2
    classDef error fill:#FFB6C1,stroke:#DC143C,stroke-width:2

    Start([🚀 Begin]) --> Process[⚙️ Work]
    Process --> Done([✅ Complete])
    Process --> Failed([❌ Failed])

    class Done success
    class Failed error
```

**All Shapes Showcase:**
```mermaid
flowchart TD
    A[Rectangle]
    B(Rounded)
    C([Stadium])
    D[[Subroutine]]
    E{Diamond}
    F{{Hexagon}}
    G((Circle))
    H(((Double Circle)))

    A --> B --> C --> D --> E --> F --> G --> H
```

---

### 2. Sequence Diagrams - Interactions

**API Call Flow:**
```mermaid
sequenceDiagram
    autonumber
    User->>Frontend: Click Login
    Frontend->>API: POST /auth
    API->>Database: Query User
    Database-->>API: User Data

    alt Valid Credentials
        API-->>Frontend: JWT Token
        Frontend-->>User: Dashboard
    else Invalid
        API-->>Frontend: Error 401
        Frontend-->>User: Error Message
    end
```

---

### 3. State Diagrams - State Machines

**Order Processing:**
```mermaid
stateDiagram-v2
    [*] --> Pending

    Pending --> Processing: payment received
    Processing --> Shipped: items packed
    Processing --> Cancelled: out of stock

    Shipped --> Delivered: delivery confirmed
    Delivered --> [*]
    Cancelled --> Refunded: refund processed
    Refunded --> [*]
```

---

### 4. Class Diagrams - OOP Design

**E-Commerce System:**
```mermaid
classDiagram
    class User {
        +int id
        +string email
        +login()
        +logout()
    }

    class Order {
        +int orderId
        +date orderDate
        +calculate Total()
    }

    class Product {
        +string sku
        +decimal price
        +updateStock()
    }

    User "1" --> "*" Order : places
    Order "*" --> "*" Product : contains
```

---

### 5. ER Diagrams - Database Design

**Blog Platform:**
```mermaid
erDiagram
    USER ||--o{ POST : writes
    POST ||--o{ COMMENT : has
    USER ||--o{ COMMENT : writes

    USER {
        int user_id PK
        string username
        string email
        date created_at
    }

    POST {
        int post_id PK
        int user_id FK
        string title
        text content
        date published_at
    }

    COMMENT {
        int comment_id PK
        int post_id FK
        int user_id FK
        text content
        date created_at
    }
```

---

### 6. Gantt Charts - Project Planning

**Software Development Cycle:**
```mermaid
gantt
    title Development Roadmap Q1 2025
    dateFormat YYYY-MM-DD

    section Planning
    Requirements    :done, 2025-01-01, 1w
    Architecture    :done, 2025-01-08, 1w

    section Development
    Backend API     :active, 2025-01-15, 3w
    Frontend UI     :active, 2025-01-22, 3w
    Database        :done, 2025-01-15, 1w

    section Testing
    Unit Tests      :crit, 2025-02-05, 1w
    Integration     :crit, 2025-02-12, 1w

    section Deployment
    Staging         :milestone, 2025-02-19, 1d
    Production      :milestone, 2025-02-26, 1d
```

---

### 7. Pie Charts - Data Visualization

**Budget Allocation:**
```mermaid
pie title Annual Budget Distribution
    "Engineering" : 40
    "Marketing" : 25
    "Sales" : 20
    "Operations" : 10
    "Other" : 5
```

---

## 📐 PlantUML Diagrams (10+ Types)

### Activity Diagrams - Process Flows

```plantuml
@startuml
start
:Initialize;
if (Check condition?) then (yes)
  :Process A;
else (no)
  :Process B;
endif
:Finalize;
stop
@enduml
```

---

### Use Case Diagrams - System Actors

```plantuml
@startuml
left to right direction
actor User
actor Admin

rectangle System {
  User -- (View Diagrams)
  User -- (Export Diagrams)
  Admin -- (Manage Users)
  Admin -- (Configure System)
}
@enduml
```

---

### Component Diagrams - Architecture

```plantuml
@startuml
package "Frontend" {
  [UI Components]
  [State Management]
}

package "Backend" {
  [API Server]
  [Business Logic]
}

database "Database" {
  [PostgreSQL]
}

[UI Components] --> [State Management]
[State Management] --> [API Server]
[API Server] --> [Business Logic]
[Business Logic] --> [PostgreSQL]
@enduml
```

---

## 🎨 Styling Examples

### Color-Coded Flowchart

```mermaid
flowchart TD
    classDef startEnd fill:#98D8C8,stroke:#27AE60,stroke-width:3
    classDef process fill:#87CEEB,stroke:#4682B4,stroke-width:2
    classDef decision fill:#FFD700,stroke:#DAA520,stroke-width:2
    classDef success fill:#90EE90,stroke:#228B22,stroke-width:2
    classDef error fill:#FFB6C1,stroke:#DC143C,stroke-width:2

    Start([Start]):::startEnd --> Validate{Valid?}:::decision
    Validate -->|Yes| Process[Process]:::process
    Validate -->|No| Error[Error]:::error
    Process --> Success[Success]:::success
    Error --> End([End]):::startEnd
    Success --> End
```

---

### Interactive Diagram with Links

```mermaid
flowchart TD
    Docs[📚 Documentation] --> Code[💻 Source Code]
    Code --> Build[🔨 Build]
    Build --> Deploy[🚀 Deploy]

    click Docs "https://github.com/packerlschupfer/gDiagram/tree/main/docs"
    click Code "https://github.com/packerlschupfer/gDiagram"
    click Build "https://github.com/packerlschupfer/gDiagram/actions"
    click Deploy "https://github.com/packerlschupfer/gDiagram/releases"
```

---

### Complex Workflow with Subgraphs

```mermaid
flowchart TD
    Start[User Request] --> Auth{Authenticated?}

    Auth -->|No| Login[Login Page]
    Login --> Auth

    Auth -->|Yes| Load[Load Data]

    subgraph "Data Processing"
        Load --> Validate{Valid?}
        Validate -->|Yes| Transform[Transform]
        Validate -->|No| ErrorHandler[Handle Error]
        Transform --> Cache[Cache Result]
    end

    Cache --> Display[Display to User]
    ErrorHandler --> Display
    Display --> End[Done]
```

---

## 📚 Real-World Examples

### Software Architecture Diagram
Shows microservices architecture with databases and message queues

### Database Schema
Complete e-commerce database with users, products, orders, payments

### Project Timeline
Agile sprint planning with epics, stories, and milestones

### API Documentation
Sequence diagrams for all major API flows

### State Machine
Order lifecycle from creation to delivery

---

## 💡 Tips for Great Diagrams

### 1. Use Color Coding
- Green for success paths
- Red for error paths
- Blue for normal processing
- Yellow for decisions

### 2. Add Meaningful Labels
- Use descriptive node names
- Label decision branches clearly
- Add edge labels for context

### 3. Organize with Subgraphs
- Group related components
- Show system boundaries
- Improve visual hierarchy

### 4. Leverage Interactivity
- Add clickable links to documentation
- Include hover tooltips for details
- Link to related diagrams

### 5. Keep It Simple
- Limit to 20-30 nodes per diagram
- Split complex flows into multiple diagrams
- Use consistent naming conventions

---

## 🎯 Use Cases by Diagram Type

| Diagram Type | Best For |
|--------------|----------|
| **Flowchart** | Algorithms, processes, workflows |
| **Sequence** | API calls, user interactions, protocols |
| **State** | Order status, user states, lifecycles |
| **Class** | OOP design, software architecture |
| **ER** | Database schemas, data models |
| **Gantt** | Project planning, sprint schedules |
| **Pie** | Budget allocation, market share |

---

**All examples in this gallery can be copied and used as starting points for your own diagrams!**

**Try them in gDiagram**: `gdiagram examples/`
