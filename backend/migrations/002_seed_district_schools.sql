INSERT INTO schools (name, state, district)
SELECT 'JNV Hingoli', 'Maharashtra', 'Hingoli'
WHERE NOT EXISTS (
  SELECT 1 FROM schools WHERE lower(district) = lower('Hingoli')
);

INSERT INTO schools (name, state, district)
SELECT 'JNV Nanded', 'Maharashtra', 'Nanded'
WHERE NOT EXISTS (
  SELECT 1 FROM schools WHERE lower(district) = lower('Nanded')
);
