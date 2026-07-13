# C4-PlantUML Examples

gDiagram supports C4 architecture diagrams two ways:

## 1. Native C4 stereotypes (recommended)

Use `<<person>>`, `<<container>>`, `<<container_db>>`, `<<system>>`,
`<<system_boundary>>`, `<<container_boundary>>`, `<<external_*>>` directly
on `rectangle`/`database`/`queue` declarations. gDiagram recognises these
and applies the canonical C4 colors automatically.

```plantuml
rectangle "Customer" <<person>> as customer
rectangle "Online Store" <<system_boundary>> as store {
    rectangle "Web App\n[React]" <<container>> as web
    database  "Database\n[PostgreSQL]" <<container>> as db
}
customer --> web : "Uses\n[HTTPS]"
web      --> db  : "Reads/Writes\n[SQL]"
```

See [`01_native_container.puml`](01_native_container.puml). This form is
self-contained — no external includes needed — and renders cleanly out
of the box.

## 2. Full C4-PlantUML stdlib

If you want the canonical `Person()`, `Container()`, `Rel()`,
`System_Boundary()` macro syntax, gDiagram's preprocessor expands the
real [C4-PlantUML stdlib](https://github.com/plantuml-stdlib/C4-PlantUML).

Setup:

```bash
git clone https://github.com/plantuml-stdlib/C4-PlantUML.git ~/git/C4-PlantUML
```

Then write your diagram with an `!include` pointing at your clone:

```plantuml
@startuml
!define RELATIVE_INCLUDE "."
!include /home/you/git/C4-PlantUML/C4_Container.puml

Person(customer, "Customer", "A user of the system")
System_Boundary(c1, "Online Store") {
    Container(web, "Web App", "React", "User interface")
    Container(api, "API", "Go", "Business logic")
    ContainerDb(db, "Database", "PostgreSQL")
}
Rel(customer, web, "Uses", "HTTPS")
Rel(web, api, "Calls", "JSON")
Rel(api, db, "Reads/Writes", "SQL")
@enduml
```

See [`02_full_stdlib.puml`](02_full_stdlib.puml) — edit the include path
before opening it.

The `!define RELATIVE_INCLUDE "."` short-circuits the C4 stdlib's HTTPS
fallback include, since gDiagram's preprocessor doesn't fetch over the
network.

### What works

- Macro expansion: `Person`, `System`, `Container`, `ContainerDb`,
  `ContainerQueue`, all the `*_Ext` variants, `System_Boundary`,
  `Container_Boundary`, `Enterprise_Boundary`, `Rel`, `BiRel`
- All C4 stereotype-based colors and shapes
- Conditional `!if`/`!ifdef` directives, parameterized procedures and
  functions, expression evaluation, the built-in functions C4-PlantUML
  uses (`%substr`, `%strpos`, `%function_exists`, etc.)

### What's still rough

- Long labels that should wrap (`!while`-based text wrapping is
  degraded — short labels render perfectly, very long ones lose the
  wrap)
- Some `!global` declarations and a few of the more obscure
  preprocessor directives

The native form (option 1) sidesteps all of these and gives a cleaner
result.
