CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS schools (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  state text NOT NULL,
  district text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id uuid NULL REFERENCES schools(id),
  role text NOT NULL,
  full_name text NOT NULL,
  phone text NOT NULL UNIQUE,
  email text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS students (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id uuid NOT NULL REFERENCES schools(id),
  full_name text NOT NULL,
  class_label text NOT NULL,
  roll_number int NOT NULL,
  date_of_birth date NOT NULL,
  house text NOT NULL,
  parent_phone text NOT NULL,
  admission_year int NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (school_id, class_label, roll_number)
);

CREATE TABLE IF NOT EXISTS parent_links (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  parent_id uuid NOT NULL REFERENCES users(id),
  student_id uuid NOT NULL REFERENCES students(id),
  status text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS subjects (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id uuid NOT NULL REFERENCES schools(id),
  class text NOT NULL,
  name text NOT NULL,
  locked boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (school_id, class, name)
);

CREATE TABLE IF NOT EXISTS exams (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id uuid NOT NULL REFERENCES schools(id),
  class text NOT NULL,
  title text NOT NULL,
  term text NOT NULL,
  exam_date date NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS scores (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  exam_id uuid NOT NULL REFERENCES exams(id),
  student_id uuid NOT NULL REFERENCES students(id),
  subject text NOT NULL,
  score numeric NOT NULL,
  max_score numeric NOT NULL,
  grade text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS announcements (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id uuid NOT NULL REFERENCES schools(id),
  title text NOT NULL,
  content text NOT NULL,
  category text NOT NULL,
  priority text NOT NULL,
  published boolean NOT NULL DEFAULT false,
  published_at timestamptz NULL,
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
