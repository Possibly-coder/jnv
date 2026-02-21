CREATE TABLE IF NOT EXISTS audit_events (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id uuid NULL REFERENCES schools(id),
  user_id uuid NULL REFERENCES users(id),
  user_role text NOT NULL DEFAULT '',
  action text NOT NULL,
  payload text NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_events_school_created
  ON audit_events (school_id, created_at DESC);
