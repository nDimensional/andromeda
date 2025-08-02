# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Andromeda is a high-performance force-directed graph layout engine written in Zig using GTK4 and OpenGL. It visualizes large-scale graphs by computing force-directed layouts with the ForceAtlas2 algorithm, supporting interactive manipulation and real-time rendering.

## Build System and Commands

**Requirements:** Zig version 0.14.0

**Primary Commands:**
- `zig build run` - Build and run the application
- `zig build` - Build the executable only

The project uses Zig's build system with external dependencies managed through build.zig.zon. Key dependencies include SQLite for data storage, GTK4/GDK4 for UI, OpenGL (via libepoxy) for rendering, and a custom quadtree implementation for spatial optimization.

## Architecture Overview

**Core Components:**
- `Graph.zig` - Central graph data structure managing nodes, edges, and their relationships. Handles loading from SQLite database, spatial indexing, and coordinate updates.
- `engines/ForceAtlas2.zig` - Multi-threaded ForceAtlas2 force-directed layout algorithm implementation using quadtrees for spatial optimization.
- `ApplicationWindow.zig` - Main GTK4 application window handling UI state, file operations, and rendering coordination.
- `Canvas.zig` - OpenGL-based rendering component for graph visualization with shader support.
- `Store.zig` - SQLite database interface for persistent graph data storage.

**Data Flow:**
1. SQLite database contains nodes (id, x, y, mass) and edges (source, target, weight) tables
2. Graph.zig loads data into memory structures optimized for layout computation
3. ForceAtlas2 engine computes forces using quadtree spatial partitioning across multiple threads
4. Canvas renders updated positions using OpenGL shaders
5. Changes can be saved back to the database

**Key Design Patterns:**
- Multi-threaded force computation with thread pool for performance
- Spatial optimization using quadtrees to reduce O(n²) force calculations
- GTK4 integration with custom OpenGL rendering context
- Asynchronous loading with progress reporting via GIO tasks
- Memory management following Zig idioms with explicit allocator usage

**OpenGL Rendering:**
- Vertex/fragment shaders for node rendering (supports both OpenGL 3.2 ES and 4.1 Core profiles)
- Custom rendering pipeline integrated with GTK4's GL context
- Real-time updates during layout computation

## Database Schema

Expected SQLite schema:
```sql
CREATE TABLE nodes(
  id INTEGER PRIMARY KEY NOT NULL,
  x FLOAT NOT NULL DEFAULT 0,
  y FLOAT NOT NULL DEFAULT 0
);

CREATE TABLE edges(
  source INTEGER NOT NULL REFERENCES nodes(id),
  target INTEGER NOT NULL REFERENCES nodes(id)
);
```

## Key Development Considerations

- The codebase follows Zig 0.14.0 conventions and memory management patterns
- Multi-threading is implemented using Zig's standard thread pool for ForceAtlas2 calculations
- GTK4 integration requires careful memory management between C interop and Zig allocation
- OpenGL shader compilation supports multiple versions for cross-platform compatibility
- Database operations use prepared statements for performance with large datasets