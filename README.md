# ellipse

## Worlds and editor

Ellipse owns the world format, world registry, terrain/mesh/model tools, and
the built-in editor UI. Import `ellipse` for the public modules, or import the
focused modules directly:

```nim
import ellipse/worlds/registry
import ellipse/editing/editors
import ellipse/editing/editors/state

var worlds = WorldsRegistry.init()
setSpawnableEntityTypes(["player", "npc"])
```

`WorldsRegistry` persists worlds below `data/worlds` in the application working
directory. Projects provide their own spawnable entity IDs; the engine editor
does not depend on a project's ECS.
