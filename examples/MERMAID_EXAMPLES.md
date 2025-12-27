# Mermaid Diagram Examples for gDiagram

This document contains working examples of Mermaid diagrams supported by gDiagram.

## Flowchart Examples

### Basic Flowchart

```mermaid
flowchart TD
    A[Start] --> B[Process]
    B --> C[End]
```

### Flowchart with Decision

```mermaid
flowchart TD
    Start[Start Process] --> Input{Input Valid?}
    Input -->|Yes| Process[Process Data]
    Input -->|No| Error[Show Error]
    Process --> End[End]
    Error --> End
```

### All Node Shapes

```mermaid
flowchart LR
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

### Flowchart with Subgraph

```mermaid
flowchart TD
    A[Input] --> B[Process]

    subgraph Processing
        B --> C[Transform]
        C --> D[Validate]
    end

    D --> E[Output]
```

### Different Arrow Types

```mermaid
flowchart TD
    A -->|Solid| B
    C -.->|Dotted| D
    E ==>|Thick| F
    G --o|Open| H
    I --x|Cross| J
```

### Complex Workflow

```mermaid
flowchart TD
    Start[Start] --> CheckInput{Input Valid?}
    CheckInput -->|Yes| ProcessData[Process Data]
    CheckInput -->|No| ShowError[Show Error]

    ProcessData --> Transform((Transform))
    Transform --> Validate{Validation}

    Validate -->|Pass| Save[Save to DB]
    Validate -->|Fail| ShowError

    Save --> Success[Success Message]
    ShowError --> End([End])
    Success --> End
```

## Sequence Diagram Examples

### Basic Sequence

```mermaid
sequenceDiagram
    Alice->>Bob: Hello Bob!
    Bob-->>Alice: Hi Alice!
```

### With Participants

```mermaid
sequenceDiagram
    participant Alice
    participant Bob
    participant Charlie

    Alice->>Bob: Hello Bob
    Bob->>Charlie: Hi Charlie
    Charlie-->>Alice: Hello Alice
```

### With Aliases

```mermaid
sequenceDiagram
    participant A as Alice
    participant B as Bob

    A->>B: Message to Bob
    B-->>A: Response to Alice
```

### With Autonumbering

```mermaid
sequenceDiagram
    autonumber
    Alice->>Bob: First message
    Bob->>Charlie: Second message
    Charlie-->>Alice: Third message
```

### With Notes

```mermaid
sequenceDiagram
    participant Alice
    participant Bob

    Alice->>Bob: Hello
    Note over Alice,Bob: They greet each other
    Bob-->>Alice: Hi
    Note right of Bob: Bob is happy
```

### With Activation/Deactivation

```mermaid
sequenceDiagram
    Alice->>Bob: Request
    activate Bob
    Bob->>Database: Query
    Database-->>Bob: Result
    Bob-->>Alice: Response
    deactivate Bob
```

### With Loops and Alternatives

```mermaid
sequenceDiagram
    Alice->>Bob: Authentication Request

    alt Successful case
        Bob->>Alice: Authentication Accepted
    else Failure case
        Bob->>Alice: Authentication Rejected
    end

    opt Extra step
        Alice->>Bob: Another request
    end
```

### Complete Authentication Flow

```mermaid
sequenceDiagram
    autonumber
    participant User
    participant Frontend
    participant Backend
    participant Database

    User->>Frontend: Click Login
    Frontend->>Backend: POST /auth/login
    activate Backend
    Backend->>Database: Query user
    Database-->>Backend: User data

    alt User found
        Backend->>Backend: Verify password
        Backend-->>Frontend: Auth token
        Frontend-->>User: Redirect to dashboard
    else User not found
        Backend-->>Frontend: Error 401
        Frontend-->>User: Show error message
    end

    deactivate Backend

    Note over User,Frontend: Authentication complete
```

## Supported Mermaid Features

### Flowchart

✅ **Supported:**
- Directions: TD (top-down), LR (left-right), RL (right-left), BT (bottom-top)
- Node shapes: Rectangle `[]`, Rounded `()`, Stadium `([])`, Subroutine `[[]]`, Diamond `{}`, Hexagon `{{}}`, Circle `(())`, Double Circle `((())))`
- Arrow types: `-->` (solid), `-.->` (dotted), `==>` (thick), `--o` (open), `--x` (cross)
- Edge labels: `A -->|Label| B`
- Chained edges: `A --> B --> C`
- Subgraphs with titles
- Style declarations (basic)

### Sequence Diagram

✅ **Supported:**
- Participants and actors
- Participant aliases: `participant A as Alice`
- Messages with arrows: `->>`, `-->>`, `->`, `-->`
- Arrow types: solid, dotted, open, cross
- Notes: `Note over A,B`, `Note right of A`, `Note left of A`
- Autonumbering
- Activation/deactivation
- Control structures: loop, alt, opt, par, critical, break, rect
- Title

## File Format Support

gDiagram automatically detects the diagram format:

- **.puml, .plantuml, .pu** → PlantUML
- **.mmd, .mermaid** → Mermaid
- **Content detection** → Checks for `flowchart`, `sequenceDiagram`, or `@startuml` keywords

## Building Packages