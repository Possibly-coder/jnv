WITH target_school AS (
  SELECT id FROM schools WHERE lower(district) = lower('Hingoli') ORDER BY created_at ASC LIMIT 1
),
admin_user AS (
  INSERT INTO users (school_id, role, full_name, phone, email)
  SELECT ts.id, 'admin', 'Demo Admin', '+919999999999', 'admin@jnv.demo'
  FROM target_school ts
  WHERE NOT EXISTS (SELECT 1 FROM users WHERE phone = '+919999999999')
  RETURNING id, school_id
),
existing_admin AS (
  SELECT u.id, u.school_id
  FROM users u
  JOIN target_school ts ON ts.id = u.school_id
  WHERE u.phone = '+919999999999'
  LIMIT 1
),
admin_ref AS (
  SELECT id, school_id FROM admin_user
  UNION ALL
  SELECT id, school_id FROM existing_admin
  LIMIT 1
)
INSERT INTO students (school_id, full_name, class_label, roll_number, date_of_birth, house, parent_phone, admission_year)
SELECT ts.id, 'Aarav Sharma', '8', 12, DATE '2012-07-14', 'Aravali', '+919812345678', 2023
FROM target_school ts
WHERE NOT EXISTS (
  SELECT 1 FROM students s
  WHERE s.school_id = ts.id AND s.class_label = '8' AND s.roll_number = 12
);

WITH target_school AS (
  SELECT id FROM schools WHERE lower(district) = lower('Hingoli') ORDER BY created_at ASC LIMIT 1
)
INSERT INTO students (school_id, full_name, class_label, roll_number, date_of_birth, house, parent_phone, admission_year)
SELECT ts.id, 'Anaya Verma', '8', 14, DATE '2012-03-09', 'Nilgiri', '+919876543210', 2023
FROM target_school ts
WHERE NOT EXISTS (
  SELECT 1 FROM students s
  WHERE s.school_id = ts.id AND s.class_label = '8' AND s.roll_number = 14
);

WITH target_school AS (
  SELECT id FROM schools WHERE lower(district) = lower('Hingoli') ORDER BY created_at ASC LIMIT 1
)
INSERT INTO exams (school_id, class, title, term, exam_date)
SELECT ts.id, '8', 'Unit Test 1', 'Term 1', DATE '2026-01-10'
FROM target_school ts
WHERE NOT EXISTS (
  SELECT 1 FROM exams e
  WHERE e.school_id = ts.id AND e.class = '8' AND e.title = 'Unit Test 1' AND e.exam_date = DATE '2026-01-10'
);

WITH target_exam AS (
  SELECT e.id
  FROM exams e
  JOIN schools sc ON sc.id = e.school_id
  WHERE lower(sc.district) = lower('Hingoli')
    AND e.class = '8'
    AND e.title = 'Unit Test 1'
    AND e.exam_date = DATE '2026-01-10'
  ORDER BY e.created_at DESC
  LIMIT 1
),
target_students AS (
  SELECT id, full_name FROM students
  WHERE lower(full_name) IN (lower('Aarav Sharma'), lower('Anaya Verma'))
)
INSERT INTO scores (exam_id, student_id, subject, score, max_score, grade)
SELECT te.id, ts.id, v.subject, v.score, 100, v.grade
FROM target_exam te
JOIN target_students ts ON TRUE
JOIN (
  VALUES
    ('Aarav Sharma', 'Mathematics', 88::numeric, 'A'),
    ('Aarav Sharma', 'Science', 84::numeric, 'A'),
    ('Aarav Sharma', 'English', 91::numeric, 'A+'),
    ('Anaya Verma', 'Mathematics', 81::numeric, 'A'),
    ('Anaya Verma', 'Science', 86::numeric, 'A'),
    ('Anaya Verma', 'English', 89::numeric, 'A')
) AS v(student_name, subject, score, grade)
  ON lower(v.student_name) = lower(ts.full_name)
WHERE NOT EXISTS (
  SELECT 1 FROM scores s
  WHERE s.exam_id = te.id
    AND s.student_id = ts.id
    AND lower(s.subject) = lower(v.subject)
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
INSERT INTO announcements (school_id, title, content, category, priority, published, published_at, created_by)
SELECT ar.school_id,
       seed.title,
       seed.content,
       seed.category,
       seed.priority,
       TRUE,
       now(),
       ar.id
FROM admin_ref ar
JOIN (
  VALUES
    ('Mid-term Results Uploaded', 'Term 1 subject-wise results are now available in the parent app.', 'Academic', 'high'),
    ('Parent-Teacher Meeting', 'PTM is scheduled on Saturday from 10:00 AM to 1:00 PM in the main hall.', 'Event', 'normal'),
    ('Sports Day Notice', 'Annual Sports Day practice begins next week. House captains will share schedules.', 'Sports', 'normal')
) AS seed(title, content, category, priority)
ON TRUE
WHERE NOT EXISTS (
  SELECT 1
  FROM announcements a
  WHERE a.school_id = ar.school_id
    AND lower(a.title) = lower(seed.title)
);
