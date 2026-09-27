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

-- Fase 5: contenido piloto real. Se agregan 2 ejercicios más a cada una de
-- las 2 lecciones existentes (para llegar a 4 por lección, como el resto),
-- una 3ra lección a la Unidad 1, y 2 unidades nuevas con 3 lecciones cada
-- una, todas con 4 ejercicios y sus learning_items correspondientes.

insert into learning_items (id, course_id, item_type, value, translation) values
  ('50000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'vocab', 'Good morning', 'Buenos días'),
  ('50000000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'grammar', 'How are you?', '¿Cómo estás?'),
  ('50000000-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'vocab', 'Nice to meet you', 'Mucho gusto'),
  ('50000000-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111', 'grammar', 'I am from ...', 'Soy de...');

insert into exercises (id, lesson_id, sort_order, type, content, correct_answer) values
  ('70000000-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', 3, 'multiple_choice',
   '{"prompt": "¿Cómo se dice \"Buenos días\" en inglés?", "options": ["Good morning", "Goodbye", "Thank you"]}'::jsonb,
   '"Good morning"'::jsonb),
  ('70000000-0000-0000-0000-000000000002', '33333333-3333-3333-3333-333333333333', 4, 'fill_blank',
   '{"prompt": "Hello! How ___ you?", "options": ["are", "is", "am"]}'::jsonb,
   '"are"'::jsonb),
  ('70000000-0000-0000-0000-000000000003', '44444444-4444-4444-4444-444444444444', 3, 'multiple_choice',
   '{"prompt": "¿Cómo se dice \"Mucho gusto\" en inglés?", "options": ["Nice to meet you", "Good morning", "Thank you"]}'::jsonb,
   '"Nice to meet you"'::jsonb),
  ('70000000-0000-0000-0000-000000000004', '44444444-4444-4444-4444-444444444444', 4, 'word_order',
   '{"words": ["from", "I", "Mexico", "am"]}'::jsonb,
   '"I am from Mexico"'::jsonb);

insert into exercise_learning_items (exercise_id, learning_item_id) values
  ('70000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001'),
  ('70000000-0000-0000-0000-000000000002', '50000000-0000-0000-0000-000000000002'),
  ('70000000-0000-0000-0000-000000000003', '50000000-0000-0000-0000-000000000003'),
  ('70000000-0000-0000-0000-000000000004', '50000000-0000-0000-0000-000000000004');

insert into lessons (id, unit_id, title, sort_order) values
  ('10000000-0000-0000-0000-000000000013', '22222222-2222-2222-2222-222222222222', 'Cortesía básica', 3);

insert into learning_items (id, course_id, item_type, value, translation) values
  ('50000000-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111', 'vocab', 'Please', 'Por favor'),
  ('50000000-0000-0000-0000-000000000006', '11111111-1111-1111-1111-111111111111', 'vocab', 'Thank you', 'Gracias'),
  ('50000000-0000-0000-0000-000000000007', '11111111-1111-1111-1111-111111111111', 'vocab', 'Sorry', 'Lo siento'),
  ('50000000-0000-0000-0000-000000000008', '11111111-1111-1111-1111-111111111111', 'vocab', 'Excuse me', 'Disculpa');

insert into exercises (id, lesson_id, sort_order, type, content, correct_answer) values
  ('70000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000013', 1, 'multiple_choice',
   '{"prompt": "¿Cómo se dice \"por favor\" en inglés?", "options": ["Please", "Thank you", "Sorry"]}'::jsonb,
   '"Please"'::jsonb),
  ('70000000-0000-0000-0000-000000000006', '10000000-0000-0000-0000-000000000013', 2, 'multiple_choice',
   '{"prompt": "¿Cómo se dice \"gracias\" en inglés?", "options": ["Please", "Thank you", "Sorry"]}'::jsonb,
   '"Thank you"'::jsonb),
  ('70000000-0000-0000-0000-000000000007', '10000000-0000-0000-0000-000000000013', 3, 'fill_blank',
   '{"prompt": "___ me, where is the bathroom?", "options": ["Excuse", "Thank", "Please"]}'::jsonb,
   '"Excuse"'::jsonb),
  ('70000000-0000-0000-0000-000000000008', '10000000-0000-0000-0000-000000000013', 4, 'word_order',
   '{"words": ["you", "Thank", "very", "much"]}'::jsonb,
   '"Thank you very much"'::jsonb);

insert into exercise_learning_items (exercise_id, learning_item_id) values
  ('70000000-0000-0000-0000-000000000005', '50000000-0000-0000-0000-000000000005'),
  ('70000000-0000-0000-0000-000000000006', '50000000-0000-0000-0000-000000000006'),
  ('70000000-0000-0000-0000-000000000007', '50000000-0000-0000-0000-000000000008'),
  ('70000000-0000-0000-0000-000000000008', '50000000-0000-0000-0000-000000000006');

insert into units (id, course_id, cefr_level, title, sort_order, status)
values ('20000000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'A1', 'Números y familia', 2, 'published');

insert into lessons (id, unit_id, title, sort_order) values
  ('20000000-0000-0000-0000-000000000021', '20000000-0000-0000-0000-000000000002', 'Números del 1 al 10', 1),
  ('20000000-0000-0000-0000-000000000022', '20000000-0000-0000-0000-000000000002', 'La familia', 2),
  ('20000000-0000-0000-0000-000000000023', '20000000-0000-0000-0000-000000000002', 'Edades', 3);

insert into learning_items (id, course_id, item_type, value, translation) values
  ('50000000-0000-0000-0000-000000000009', '11111111-1111-1111-1111-111111111111', 'vocab', 'Two', 'Dos'),
  ('50000000-0000-0000-0000-000000000010', '11111111-1111-1111-1111-111111111111', 'vocab', 'Three', 'Tres'),
  ('50000000-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', 'vocab', 'Four', 'Cuatro'),
  ('50000000-0000-0000-0000-000000000012', '11111111-1111-1111-1111-111111111111', 'vocab', 'Seven', 'Siete'),
  ('50000000-0000-0000-0000-000000000013', '11111111-1111-1111-1111-111111111111', 'vocab', 'Ten', 'Diez');

insert into exercises (id, lesson_id, sort_order, type, content, correct_answer) values
  ('70000000-0000-0000-0000-000000000009', '20000000-0000-0000-0000-000000000021', 1, 'multiple_choice',
   '{"prompt": "¿Cómo se dice \"tres\" en inglés?", "options": ["Two", "Three", "Four"]}'::jsonb,
   '"Three"'::jsonb),
  ('70000000-0000-0000-0000-000000000010', '20000000-0000-0000-0000-000000000021', 2, 'multiple_choice',
   '{"prompt": "¿Cómo se dice \"siete\" en inglés?", "options": ["Six", "Seven", "Eight"]}'::jsonb,
   '"Seven"'::jsonb),
  ('70000000-0000-0000-0000-000000000011', '20000000-0000-0000-0000-000000000021', 3, 'fill_blank',
   '{"prompt": "Two plus two is ___.", "options": ["four", "five", "six"]}'::jsonb,
   '"four"'::jsonb),
  ('70000000-0000-0000-0000-000000000012', '20000000-0000-0000-0000-000000000021', 4, 'word_order',
   '{"words": ["ten", "have", "I", "dollars"]}'::jsonb,
   '"I have ten dollars"'::jsonb);

insert into exercise_learning_items (exercise_id, learning_item_id) values
  ('70000000-0000-0000-0000-000000000009', '50000000-0000-0000-0000-000000000010'),
  ('70000000-0000-0000-0000-000000000010', '50000000-0000-0000-0000-000000000012'),
  ('70000000-0000-0000-0000-000000000011', '50000000-0000-0000-0000-000000000011'),
  ('70000000-0000-0000-0000-000000000012', '50000000-0000-0000-0000-000000000013');

insert into learning_items (id, course_id, item_type, value, translation) values
  ('50000000-0000-0000-0000-000000000014', '11111111-1111-1111-1111-111111111111', 'vocab', 'Mother', 'Madre'),
  ('50000000-0000-0000-0000-000000000015', '11111111-1111-1111-1111-111111111111', 'vocab', 'Father', 'Padre'),
  ('50000000-0000-0000-0000-000000000016', '11111111-1111-1111-1111-111111111111', 'vocab', 'Brother', 'Hermano'),
  ('50000000-0000-0000-0000-000000000017', '11111111-1111-1111-1111-111111111111', 'vocab', 'Sister', 'Hermana');

insert into exercises (id, lesson_id, sort_order, type, content, correct_answer) values
  ('70000000-0000-0000-0000-000000000013', '20000000-0000-0000-0000-000000000022', 1, 'multiple_choice',
   '{"prompt": "¿Cómo se dice \"madre\" en inglés?", "options": ["Father", "Mother", "Sister"]}'::jsonb,
   '"Mother"'::jsonb),
  ('70000000-0000-0000-0000-000000000014', '20000000-0000-0000-0000-000000000022', 2, 'multiple_choice',
   '{"prompt": "¿Cómo se dice \"hermano\" en inglés?", "options": ["Brother", "Sister", "Son"]}'::jsonb,
   '"Brother"'::jsonb),
  ('70000000-0000-0000-0000-000000000015', '20000000-0000-0000-0000-000000000022', 3, 'fill_blank',
   '{"prompt": "My ___ is a doctor.", "options": ["father", "brother", "sister"]}'::jsonb,
   '"father"'::jsonb),
  ('70000000-0000-0000-0000-000000000016', '20000000-0000-0000-0000-000000000022', 4, 'word_order',
   '{"words": ["is", "my", "This", "sister"]}'::jsonb,
   '"This is my sister"'::jsonb);

insert into exercise_learning_items (exercise_id, learning_item_id) values
  ('70000000-0000-0000-0000-000000000013', '50000000-0000-0000-0000-000000000014'),
  ('70000000-0000-0000-0000-000000000014', '50000000-0000-0000-0000-000000000016'),
  ('70000000-0000-0000-0000-000000000015', '50000000-0000-0000-0000-000000000015'),
  ('70000000-0000-0000-0000-000000000016', '50000000-0000-0000-0000-000000000017');

insert into learning_items (id, course_id, item_type, value, translation) values
  ('50000000-0000-0000-0000-000000000018', '11111111-1111-1111-1111-111111111111', 'grammar', 'How old are you?', '¿Cuántos años tienes?'),
  ('50000000-0000-0000-0000-000000000019', '11111111-1111-1111-1111-111111111111', 'grammar', 'I am ... years old', 'Tengo ... años');

insert into exercises (id, lesson_id, sort_order, type, content, correct_answer) values
  ('70000000-0000-0000-0000-000000000017', '20000000-0000-0000-0000-000000000023', 1, 'multiple_choice',
   '{"prompt": "¿Cómo se dice \"¿Cuántos años tienes?\" en inglés?", "options": ["How old are you?", "What is your name?", "Where are you from?"]}'::jsonb,
   '"How old are you?"'::jsonb),
  ('70000000-0000-0000-0000-000000000018', '20000000-0000-0000-0000-000000000023', 2, 'multiple_choice',
   '{"prompt": "¿Cómo se dice \"Tengo veinte años\" en inglés?", "options": ["I am twenty years old", "I have twenty years", "I am twenty"]}'::jsonb,
   '"I am twenty years old"'::jsonb),
  ('70000000-0000-0000-0000-000000000019', '20000000-0000-0000-0000-000000000023', 3, 'fill_blank',
   '{"prompt": "I am ten years ___.", "options": ["old", "young", "new"]}'::jsonb,
   '"old"'::jsonb),
  ('70000000-0000-0000-0000-000000000020', '20000000-0000-0000-0000-000000000023', 4, 'word_order',
   '{"words": ["are", "you", "old", "How"]}'::jsonb,
   '"How old are you"'::jsonb);

insert into exercise_learning_items (exercise_id, learning_item_id) values
  ('70000000-0000-0000-0000-000000000017', '50000000-0000-0000-0000-000000000018'),
  ('70000000-0000-0000-0000-000000000018', '50000000-0000-0000-0000-000000000019'),
  ('70000000-0000-0000-0000-000000000019', '50000000-0000-0000-0000-000000000019'),
  ('70000000-0000-0000-0000-000000000020', '50000000-0000-0000-0000-000000000018');

insert into units (id, course_id, cefr_level, title, sort_order, status)
values ('30000000-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'A1', 'Comida y rutina diaria', 3, 'published');

insert into lessons (id, unit_id, title, sort_order) values
  ('30000000-0000-0000-0000-000000000031', '30000000-0000-0000-0000-000000000003', 'Comida básica', 1),
  ('30000000-0000-0000-0000-000000000032', '30000000-0000-0000-0000-000000000003', 'Mi rutina diaria', 2),
  ('30000000-0000-0000-0000-000000000033', '30000000-0000-0000-0000-000000000003', 'Mi día', 3);

insert into learning_items (id, course_id, item_type, value, translation) values
  ('50000000-0000-0000-0000-000000000020', '11111111-1111-1111-1111-111111111111', 'vocab', 'Bread', 'Pan'),
  ('50000000-0000-0000-0000-000000000021', '11111111-1111-1111-1111-111111111111', 'vocab', 'Rice', 'Arroz'),
  ('50000000-0000-0000-0000-000000000022', '11111111-1111-1111-1111-111111111111', 'vocab', 'Chicken', 'Pollo'),
  ('50000000-0000-0000-0000-000000000023', '11111111-1111-1111-1111-111111111111', 'grammar', 'I like', 'Me gusta');

insert into exercises (id, lesson_id, sort_order, type, content, correct_answer) values
  ('70000000-0000-0000-0000-000000000021', '30000000-0000-0000-0000-000000000031', 1, 'multiple_choice',
   '{"prompt": "¿Cómo se dice \"pan\" en inglés?", "options": ["Bread", "Rice", "Water"]}'::jsonb,
   '"Bread"'::jsonb),
  ('70000000-0000-0000-0000-000000000022', '30000000-0000-0000-0000-000000000031', 2, 'multiple_choice',
   '{"prompt": "¿Cómo se dice \"Me gusta\" en inglés?", "options": ["I like", "I don''t like", "I have"]}'::jsonb,
   '"I like"'::jsonb),
  ('70000000-0000-0000-0000-000000000023', '30000000-0000-0000-0000-000000000031', 3, 'fill_blank',
   '{"prompt": "I ___ apples.", "options": ["like", "likes", "liking"]}'::jsonb,
   '"like"'::jsonb),
  ('70000000-0000-0000-0000-000000000024', '30000000-0000-0000-0000-000000000031', 4, 'word_order',
   '{"words": ["like", "I", "chicken", "and", "rice"]}'::jsonb,
   '"I like chicken and rice"'::jsonb);

insert into exercise_learning_items (exercise_id, learning_item_id) values
  ('70000000-0000-0000-0000-000000000021', '50000000-0000-0000-0000-000000000020'),
  ('70000000-0000-0000-0000-000000000022', '50000000-0000-0000-0000-000000000023'),
  ('70000000-0000-0000-0000-000000000023', '50000000-0000-0000-0000-000000000023'),
  ('70000000-0000-0000-0000-000000000024', '50000000-0000-0000-0000-000000000022'),
  ('70000000-0000-0000-0000-000000000024', '50000000-0000-0000-0000-000000000021');

insert into learning_items (id, course_id, item_type, value, translation) values
  ('50000000-0000-0000-0000-000000000024', '11111111-1111-1111-1111-111111111111', 'vocab', 'Wake up', 'Despertarse'),
  ('50000000-0000-0000-0000-000000000025', '11111111-1111-1111-1111-111111111111', 'vocab', 'Eat breakfast', 'Desayunar'),
  ('50000000-0000-0000-0000-000000000026', '11111111-1111-1111-1111-111111111111', 'vocab', 'Go to work', 'Ir al trabajo'),
  ('50000000-0000-0000-0000-000000000027', '11111111-1111-1111-1111-111111111111', 'vocab', 'Sleep', 'Dormir');

insert into exercises (id, lesson_id, sort_order, type, content, correct_answer) values
  ('70000000-0000-0000-0000-000000000025', '30000000-0000-0000-0000-000000000032', 1, 'multiple_choice',
   '{"prompt": "¿Cómo se dice \"despertarse\" en inglés?", "options": ["Wake up", "Sleep", "Eat"]}'::jsonb,
   '"Wake up"'::jsonb),
  ('70000000-0000-0000-0000-000000000026', '30000000-0000-0000-0000-000000000032', 2, 'multiple_choice',
   '{"prompt": "¿Cómo se dice \"desayunar\" en inglés?", "options": ["Eat breakfast", "Go to work", "Sleep"]}'::jsonb,
   '"Eat breakfast"'::jsonb),
  ('70000000-0000-0000-0000-000000000027', '30000000-0000-0000-0000-000000000032', 3, 'fill_blank',
   '{"prompt": "I ___ up at seven.", "options": ["wake", "sleep", "eat"]}'::jsonb,
   '"wake"'::jsonb),
  ('70000000-0000-0000-0000-000000000028', '30000000-0000-0000-0000-000000000032', 4, 'word_order',
   '{"words": ["work", "go", "I", "to"]}'::jsonb,
   '"I go to work"'::jsonb);

insert into exercise_learning_items (exercise_id, learning_item_id) values
  ('70000000-0000-0000-0000-000000000025', '50000000-0000-0000-0000-000000000024'),
  ('70000000-0000-0000-0000-000000000026', '50000000-0000-0000-0000-000000000025'),
  ('70000000-0000-0000-0000-000000000027', '50000000-0000-0000-0000-000000000024'),
  ('70000000-0000-0000-0000-000000000028', '50000000-0000-0000-0000-000000000026');

insert into learning_items (id, course_id, item_type, value, translation) values
  ('50000000-0000-0000-0000-000000000028', '11111111-1111-1111-1111-111111111111', 'grammar', 'I am hungry', 'Tengo hambre');

insert into exercises (id, lesson_id, sort_order, type, content, correct_answer) values
  ('70000000-0000-0000-0000-000000000029', '30000000-0000-0000-0000-000000000033', 1, 'multiple_choice',
   '{"prompt": "¿Cómo se dice \"Tengo hambre\" en inglés?", "options": ["I am hungry", "I am tired", "I am happy"]}'::jsonb,
   '"I am hungry"'::jsonb),
  ('70000000-0000-0000-0000-000000000030', '30000000-0000-0000-0000-000000000033', 2, 'fill_blank',
   '{"prompt": "I eat breakfast, then I ___ to work.", "options": ["go", "sleep", "like"]}'::jsonb,
   '"go"'::jsonb),
  ('70000000-0000-0000-0000-000000000031', '30000000-0000-0000-0000-000000000033', 3, 'word_order',
   '{"words": ["breakfast", "I", "eat", "every", "morning"]}'::jsonb,
   '"I eat breakfast every morning"'::jsonb),
  ('70000000-0000-0000-0000-000000000032', '30000000-0000-0000-0000-000000000033', 4, 'multiple_choice',
   '{"prompt": "¿Cómo se dice \"dormir\" en inglés?", "options": ["Sleep", "Wake up", "Eat"]}'::jsonb,
   '"Sleep"'::jsonb);

insert into exercise_learning_items (exercise_id, learning_item_id) values
  ('70000000-0000-0000-0000-000000000029', '50000000-0000-0000-0000-000000000028'),
  ('70000000-0000-0000-0000-000000000030', '50000000-0000-0000-0000-000000000026'),
  ('70000000-0000-0000-0000-000000000031', '50000000-0000-0000-0000-000000000025'),
  ('70000000-0000-0000-0000-000000000032', '50000000-0000-0000-0000-000000000027');
