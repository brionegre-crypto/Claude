CREATE TABLE research_items (
  id INTEGER PRIMARY KEY,
  topic TEXT NOT NULL,
  title TEXT NOT NULL,
  source TEXT,
  url TEXT,
  url_hash TEXT UNIQUE,
  published_at TEXT,
  researched_at TEXT NOT NULL,
  summary TEXT,
  relevance REAL DEFAULT 0,
  kind TEXT DEFAULT 'news',            -- news | conversation | question | evergreen
  opportunities TEXT,                  -- JSON list of content angles
  verification TEXT DEFAULT 'unverified', -- unverified | verified | disputed | not_applicable
  verification_notes TEXT,
  used_count INTEGER DEFAULT 0,
  last_used_at TEXT
);

CREATE TABLE content (
  id TEXT PRIMARY KEY,                 -- uuid
  platform TEXT NOT NULL,
  format TEXT NOT NULL,
  topic TEXT,
  pillar TEXT,
  hook TEXT,
  headline TEXT,
  caption TEXT,
  hashtags TEXT,                       -- JSON list
  cta TEXT,
  body TEXT,                           -- JSON: slides / script / story frames / poll / quiz
  image_concept TEXT,
  status TEXT NOT NULL DEFAULT 'planned', -- planned|generating|draft|ready|blocked|scheduled|publishing|published|failed|skipped|manual_due|cancelled
  scheduled_at TEXT,                   -- UTC ISO
  slot_key TEXT UNIQUE,                -- platform|format|local datetime: prevents double-planning
  research_ids TEXT,                   -- JSON list
  sources TEXT,                        -- JSON list of {title,url}
  fingerprint TEXT,                    -- normalized text hash for exact-duplicate detection
  quality_report TEXT,                 -- JSON
  block_reason TEXT,
  generated_by TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  published_at TEXT,
  platform_post_id TEXT,
  permalink TEXT
);
CREATE INDEX idx_content_status_time ON content(status, scheduled_at);

CREATE TABLE assets (
  id INTEGER PRIMARY KEY,
  content_id TEXT NOT NULL REFERENCES content(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,                  -- image | video | cover
  ordinal INTEGER DEFAULT 0,
  path TEXT NOT NULL,
  width INTEGER, height INTEGER, duration REAL,
  sha256 TEXT,
  license TEXT DEFAULT 'original (generated locally)',
  created_at TEXT NOT NULL
);

CREATE TABLE publish_attempts (
  id INTEGER PRIMARY KEY,
  content_id TEXT NOT NULL REFERENCES content(id),
  idempotency_key TEXT NOT NULL,
  attempt INTEGER NOT NULL,
  state TEXT NOT NULL,                 -- started|container_created|published|failed_temporary|failed_permanent|reconciled
  container_id TEXT,
  platform_post_id TEXT,
  request_summary TEXT,
  response TEXT,
  error TEXT,
  started_at TEXT NOT NULL,
  finished_at TEXT,
  next_retry_at TEXT
);
CREATE INDEX idx_attempts_content ON publish_attempts(content_id);

CREATE TABLE metrics (
  id INTEGER PRIMARY KEY,
  content_id TEXT REFERENCES content(id),
  platform TEXT NOT NULL,
  platform_post_id TEXT,
  collected_at TEXT NOT NULL,
  metric TEXT NOT NULL,
  value REAL NOT NULL
);
CREATE INDEX idx_metrics_content ON metrics(content_id, metric);

CREATE TABLE account_metrics (
  id INTEGER PRIMARY KEY,
  platform TEXT NOT NULL,
  collected_at TEXT NOT NULL,
  metric TEXT NOT NULL,
  value REAL NOT NULL
);

CREATE TABLE notifications (
  id INTEGER PRIMARY KEY,
  created_at TEXT NOT NULL,
  level TEXT NOT NULL,                 -- info|success|warning|error
  category TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT,
  read INTEGER DEFAULT 0,
  delivered TEXT                       -- JSON channels delivered
);

CREATE TABLE job_runs (
  id INTEGER PRIMARY KEY,
  job TEXT NOT NULL,
  started_at TEXT NOT NULL,
  finished_at TEXT,
  ok INTEGER,
  detail TEXT
);
CREATE INDEX idx_job_runs ON job_runs(job, started_at);

CREATE TABLE kv (
  key TEXT PRIMARY KEY,
  value TEXT,
  updated_at TEXT
);

CREATE TABLE ai_calls (
  id INTEGER PRIMARY KEY,
  at TEXT NOT NULL,
  purpose TEXT NOT NULL,
  provider TEXT NOT NULL,
  ok INTEGER NOT NULL,
  duration_ms INTEGER,
  error TEXT
);

CREATE TABLE reports (
  id INTEGER PRIMARY KEY,
  kind TEXT NOT NULL,                  -- weekly | monthly
  period_start TEXT, period_end TEXT,
  created_at TEXT NOT NULL,
  body TEXT NOT NULL
);
