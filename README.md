# Andromeda

Zig version `0.13.0`.

```
$ zig build run
```

Your SQLite database should have a schema that looks something like this:

```sql
CREATE TABLE nodes(
  x FLOAT NOT NULL DEFAULT 0,
  y FLOAT NOT NULL DEFAULT 0
);

CREATE TABLE edges(
  source INTEGER NOT NULL REFERENCES nodes(rowid),
  target INTEGER NOT NULL REFERENCES nodes(rowid)
);
```

Your nodes must have a unique integer `rowid`, which is the default behavior for all tables in SQLite.
