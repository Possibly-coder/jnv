ALTER TABLE app_configs
ADD COLUMN IF NOT EXISTS min_supported_version text NOT NULL DEFAULT '',
ADD COLUMN IF NOT EXISTS force_update_message text NOT NULL DEFAULT '';

CREATE TABLE IF NOT EXISTS device_tokens (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token text NOT NULL UNIQUE,
  platform text NOT NULL DEFAULT 'android',
  created_at timestamptz NOT NULL DEFAULT now()
);
