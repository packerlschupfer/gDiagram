# Kubernetes Learning Mindmap (C4)

A drillable C4 model of Kubernetes itself, structured as a mindmap.
Open `context.puml` and navigate down through the cluster architecture
into specific topic areas.

## File tree

```
context.puml          ← start here: actors + cluster boundary
└── cluster.puml      ← architecture: control plane + nodes + concepts
    ├── apiserver.puml    ← request flow: authn -> authz -> admission -> etcd
    ├── scheduler.puml    ← filter & score phases for pod placement
    ├── kubelet.puml      ← node agent responsibilities
    ├── workloads.puml    ← Pod, Deployment, StatefulSet, DaemonSet, Job
    ├── networking.puml   ← Service, Ingress, NetworkPolicy, DNS, kube-proxy
    ├── storage.puml      ← PV, PVC, StorageClass, CSI driver
    └── security.puml     ← AuthN, RBAC, Admission, Secrets
```

## How to use

```bash
gdiagram examples/plantuml/c4/kubernetes/context.puml
```

Then double-click any element to drill into the next level. Use the
back arrow or breadcrumb to navigate up.

## Topic-to-file mapping

| Topic | File(s) |
|---|---|
| Cluster architecture, installation & configuration | `cluster.puml`, `apiserver.puml`, `kubelet.puml` |
| Workloads & scheduling | `workloads.puml`, `scheduler.puml` |
| Services & networking | `networking.puml` |
| Storage | `storage.puml` |
| Troubleshooting | all files (helps locate which component owns which behavior) |
| RBAC & security | `security.puml`, `apiserver.puml` |

## Notes

- Each file is standalone — external references are redeclared.
- ~15 elements per diagram, sized to fit on one screen.
- Stereotypes follow the C4 convention (`<<person>>`, `<<container>>`,
  `<<component>>`, `<<system_boundary>>`, `<<container_boundary>>`).
- Drill targets match filenames: an element `as apiserver` in
  `cluster.puml` opens `apiserver.puml` on double-click.
