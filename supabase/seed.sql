insert into languages (code, name) values
  ('en', 'English'),
  ('es', 'Español')
on conflict (code) do nothing;

insert into courses (id, source_language, target_language, title, status)
values ('11111111-1111-1111-1111-111111111111', 'es', 'en', 'Inglés para hispanohablantes', 'published');

insert into units (id, course_id, cefr_level, title, sort_order, status)
values ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'A1', 'Saludos básicos', 1, 'published');

insert into lessons (id, unit_id, title, sort_order) values
  ('33333333-3333-3333-3333-333333333333', '22222222-2222-2222-2222-222222222222', 'Saludar y despedirse', 1),
  ('44444444-4444-4444-4444-444444444444', '22222222-2222-2222-2222-222222222222', 'Presentarse', 2);

insert into learning_items (id, course_id, item_type, value, translation) values
  ('55555555-5555-5555-5555-555555555555', '11111111-1111-1111-1111-111111111111', 'vocab', 'Hello', 'Hola'),
  ('66666666-6666-6666-6666-666666666666', '11111111-1111-1111-1111-111111111111', 'vocab', 'Goodbye', 'Adiós');

insert into exercises (id, lesson_id, sort_order, type, content, correct_answer) values
  ('77777777-7777-7777-7777-777777777777', '33333333-3333-3333-3333-333333333333', 1, 'multiple_choice',
   '{"prompt": "¿Cómo se dice \"Hola\" en inglés?", "options": ["Hello", "Goodbye", "Please"]}'::jsonb,
   '"Hello"'::jsonb),
  ('88888888-8888-8888-8888-888888888888', '33333333-3333-3333-3333-333333333333', 2, 'multiple_choice',
   '{"prompt": "¿Cómo se dice \"Adiós\" en inglés?", "options": ["Hello", "Goodbye", "Thanks"]}'::jsonb,
   '"Goodbye"'::jsonb);

insert into exercise_learning_items (exercise_id, learning_item_id) values
  ('77777777-7777-7777-7777-777777777777', '55555555-5555-5555-5555-555555555555'),
  ('88888888-8888-8888-8888-888888888888', '66666666-6666-6666-6666-666666666666');

insert into learning_items (id, course_id, item_type, value, translation) values
  ('99999999-9999-9999-9999-999999999999', '11111111-1111-1111-1111-111111111111', 'vocab', 'name', 'nombre'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'grammar', 'My name is', 'Me llamo');

insert into exercises (id, lesson_id, sort_order, type, content, correct_answer) values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '44444444-4444-4444-4444-444444444444', 1, 'fill_blank',
   '{"prompt": "What is your ___?", "options": ["name", "goodbye", "please"]}'::jsonb,
   '"name"'::jsonb),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', '44444444-4444-4444-4444-444444444444', 2, 'word_order',
   '{"words": ["is", "My", "Ana", "name"]}'::jsonb,
   '"My name is Ana"'::jsonb);

insert into exercise_learning_items (exercise_id, learning_item_id) values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '99999999-9999-9999-9999-999999999999'),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
