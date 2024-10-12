# Andromeda

Zig version `0.13.0`.

```
$ zig build run
```

Your SQLite database should have a schema that looks exactly like this:

```sql
CREATE TABLE nodes(
  idx INTEGER PRIMARY KEY AUTOINCREMENT,
  x FLOAT NOT NULL DEFAULT 0,
  y FLOAT NOT NULL DEFAULT 0
);

CREATE TABLE edges(
    source INTEGER NOT NULL REFERENCES nodes(idx),
    target INTEGER NOT NULL REFERENCES nodes(idx)
);
```

Your nodes **must** have sequential `idx` ids, from 1 to count(nodes).
