CREATE TABLE competitors (
  handle TEXT PRIMARY KEY,
  added_at TEXT NOT NULL,
  active INTEGER NOT NULL DEFAULT 1,
  last_error TEXT,
  last_collected_at TEXT
);

CREATE TABLE competitor_snapshots (
  id INTEGER PRIMARY KEY,
  handle TEXT NOT NULL,
  collected_at TEXT NOT NULL,
  followers REAL,
  media_count REAL,
  name TEXT
);
CREATE INDEX idx_comp_snap ON competitor_snapshots(handle, collected_at);

CREATE TABLE competitor_media (
  media_id TEXT PRIMARY KEY,
  handle TEXT NOT NULL,
  posted_at TEXT,
  media_type TEXT,
  product_type TEXT,
  caption TEXT,
  likes REAL,
  comments REAL,
  permalink TEXT,
  collected_at TEXT NOT NULL
);
CREATE INDEX idx_comp_media ON competitor_media(handle, posted_at);
