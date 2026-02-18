WITH target_school AS (
  SELECT id FROM schools WHERE lower(district) = lower('Hingoli') ORDER BY created_at ASC LIMIT 1
),
admin_ref AS (
  SELECT u.id, u.school_id
  FROM users u
  JOIN target_school ts ON ts.id = u.school_id
  WHERE u.phone = '+919999999999'
  LIMIT 1
)
INSERT INTO events (
  school_id, title, description, event_date, start_time, end_time, location, audience, category,
  published, published_at, created_by
)
SELECT ar.school_id, seed.title, seed.description, seed.event_date, seed.start_time, seed.end_time,
       seed.location, seed.audience, seed.category, TRUE, now(), ar.id
FROM admin_ref ar
JOIN (
  VALUES
    ('Annual Sports Day', 'Inter-house finals with track and field events.', DATE '2026-02-15', '09:00 AM', '05:00 PM', 'School Ground', 'All Students', 'Sports'),
    ('Parent-Teacher Meeting', 'Performance review with class teachers and subject mentors.', DATE '2026-02-22', '10:00 AM', '01:00 PM', 'Main Auditorium', 'Parents', 'Meeting'),
    ('Science Exhibition', 'Student innovation showcase and project demonstration.', DATE '2026-03-05', '11:00 AM', '04:00 PM', 'Science Block', 'Classes 8-12', 'Academic')
) AS seed(title, description, event_date, start_time, end_time, location, audience, category)
ON TRUE
WHERE NOT EXISTS (
  SELECT 1 FROM events e
  WHERE e.school_id = ar.school_id
    AND lower(e.title) = lower(seed.title)
    AND e.event_date = seed.event_date
);

WITH target_school AS (
  SELECT id FROM schools WHERE lower(district) = lower('Hingoli') ORDER BY created_at ASC LIMIT 1
),
admin_ref AS (
  SELECT u.id, u.school_id
  FROM users u
  JOIN target_school ts ON ts.id = u.school_id
  WHERE u.phone = '+919999999999'
  LIMIT 1
)
INSERT INTO app_configs (school_id, feature_flags, dashboard_widgets, updated_by, updated_at)
SELECT ar.school_id,
       '{
         "show_events": true,
         "show_announcements": true,
         "show_attendance": false,
         "show_academic_tab": true
       }'::jsonb,
       '[
         {"key":"gpa","label":"GPA","value":"9.2","hint":"This term","icon":"school"},
         {"key":"attendance","label":"Attend","value":"94.5%","hint":"Monthly avg","icon":"check_circle"},
         {"key":"rank","label":"Rank","value":"#3","hint":"Class standing","icon":"emoji_events"}
       ]'::jsonb,
       ar.id,
       now()
FROM admin_ref ar
WHERE NOT EXISTS (
  SELECT 1 FROM app_configs c WHERE c.school_id = ar.school_id
);
