CREATE TABLE IF NOT EXISTS events (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id uuid NOT NULL REFERENCES schools(id),
  title text NOT NULL,
  description text NOT NULL DEFAULT '',
  event_date date NOT NULL,
  start_time text NOT NULL DEFAULT '',
  end_time text NOT NULL DEFAULT '',
  location text NOT NULL DEFAULT '',
  audience text NOT NULL DEFAULT '',
  category text NOT NULL DEFAULT '',
  published boolean NOT NULL DEFAULT false,
  published_at timestamptz NULL,
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS app_configs (
  school_id uuid PRIMARY KEY REFERENCES schools(id),
  feature_flags jsonb NOT NULL DEFAULT '{}'::jsonb,
  dashboard_widgets jsonb NOT NULL DEFAULT '[]'::jsonb,
  updated_by uuid NULL REFERENCES users(id),
  updated_at timestamptz NOT NULL DEFAULT now()
);
