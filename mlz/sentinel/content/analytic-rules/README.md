# Analytic Rules (MLZ)

Store MLZ-specific analytic rule YAML definitions here. Use naming conventions that make it easy to map back to the upstream rule when applicable:

- `<area>-<scenario>-mlz.yaml`
- Include metadata fields (id, version, tags) that reflect the MLZ package release cadence.

When you copy rules from `content/analytic-rules` at the repo root, add comments in the YAML header describing the MLZ deltas (query tweaks, suppression defaults, incident settings).
