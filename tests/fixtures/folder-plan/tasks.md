# Folder-layout plan — tasks

```yaml
slices:
  - id: F1
    name: first
    depends-on: []
    acceptance:
      - "Test: F1 lands"
  - id: F2
    name: second
    depends-on:
      - F1
    acceptance:
      - "Test: F2 lands after F1"
```
