-- Oronzo — seeded exercise library.
--
-- Seeded rows are owned by nobody (user_id IS NULL) and identified by `slug`. Custom
-- exercises the user creates are owned (user_id = auth.uid()) and have no slug, so they
-- can never collide with this file.
--
-- Idempotent: `on conflict (slug) do update` means re-running this file UPDATES the seed
-- definitions rather than duplicating them. That is what you want when correcting a name
-- or a default — and it never touches a custom exercise.

insert into public.exercises
  (slug, name, muscle_group, equipment, default_mode, default_duration_seconds, default_reps)
values
  -- chest
  ('bench-press-barbell',      'Barbell Bench Press',        'chest',      'barbell',    'reps', null,  8),
  ('bench-press-dumbbell',     'Dumbbell Bench Press',       'chest',      'dumbbell',   'reps', null, 10),
  ('incline-press-dumbbell',   'Incline Dumbbell Press',     'chest',      'dumbbell',   'reps', null, 10),
  ('incline-press-barbell',    'Incline Barbell Press',      'chest',      'barbell',    'reps', null,  8),
  ('chest-press-machine',      'Chest Press Machine',        'chest',      'machine',    'reps', null, 10),
  ('push-up',                  'Push-Up',                    'chest',      'bodyweight', 'reps', null, 12),
  ('push-up-incline',          'Incline Push-Up',            'chest',      'bodyweight', 'reps', null, 12),
  ('dip-chest',                'Chest Dip',                  'chest',      'bodyweight', 'reps', null,  8),
  ('cable-fly',                'Cable Fly',                  'chest',      'cable',      'reps', null, 12),
  ('pec-deck',                 'Pec Deck',                   'chest',      'machine',    'reps', null, 12),

  -- back
  ('pull-up',                  'Pull-Up',                    'back',       'bodyweight', 'reps', null,  6),
  ('chin-up',                  'Chin-Up',                    'back',       'bodyweight', 'reps', null,  6),
  ('pull-up-assisted',         'Assisted Pull-Up',           'back',       'machine',    'reps', null,  8),
  ('lat-pulldown',             'Lat Pulldown',               'back',       'cable',      'reps', null, 10),
  ('row-barbell',              'Barbell Row',                'back',       'barbell',    'reps', null,  8),
  ('row-dumbbell',             'One-Arm Dumbbell Row',       'back',       'dumbbell',   'reps', null, 10),
  ('row-seated-cable',         'Seated Cable Row',           'back',       'cable',      'reps', null, 10),
  ('row-machine',              'Machine Row',                'back',       'machine',    'reps', null, 10),
  ('row-t-bar',                'T-Bar Row',                  'back',       'barbell',    'reps', null, 10),
  ('straight-arm-pulldown',    'Straight-Arm Pulldown',      'back',       'cable',      'reps', null, 12),
  ('face-pull',                'Face Pull',                  'back',       'cable',      'reps', null, 15),
  ('back-extension',           'Back Extension',             'back',       'bodyweight', 'reps', null, 12),
  ('inverted-row',             'Inverted Row',               'back',       'bodyweight', 'reps', null, 10),
  ('shrug-barbell',            'Barbell Shrug',              'back',       'barbell',    'reps', null, 12),

  -- shoulders
  ('overhead-press',           'Overhead Press',             'shoulders',  'barbell',    'reps', null,  8),
  ('shoulder-press-dumbbell',  'Dumbbell Shoulder Press',    'shoulders',  'dumbbell',   'reps', null, 10),
  ('shoulder-press-machine',   'Shoulder Press Machine',     'shoulders',  'machine',    'reps', null, 10),
  ('arnold-press',             'Arnold Press',               'shoulders',  'dumbbell',   'reps', null, 10),
  ('lateral-raise-dumbbell',   'Lateral Raise',              'shoulders',  'dumbbell',   'reps', null, 12),
  ('lateral-raise-cable',      'Cable Lateral Raise',        'shoulders',  'cable',      'reps', null, 12),
  ('front-raise',              'Front Raise',                'shoulders',  'dumbbell',   'reps', null, 12),
  ('rear-delt-fly',            'Rear Delt Fly',              'shoulders',  'dumbbell',   'reps', null, 12),
  ('upright-row',              'Upright Row',                'shoulders',  'barbell',    'reps', null, 12),
  ('pike-push-up',             'Pike Push-Up',               'shoulders',  'bodyweight', 'reps', null, 10),

  -- biceps
  ('curl-barbell',             'Barbell Curl',               'biceps',     'barbell',    'reps', null, 10),
  ('curl-dumbbell',            'Dumbbell Curl',              'biceps',     'dumbbell',   'reps', null, 10),
  ('curl-hammer',              'Hammer Curl',                'biceps',     'dumbbell',   'reps', null, 10),
  ('curl-incline-dumbbell',    'Incline Dumbbell Curl',      'biceps',     'dumbbell',   'reps', null, 10),
  ('curl-preacher',            'Preacher Curl',              'biceps',     'machine',    'reps', null, 10),
  ('curl-cable',               'Cable Curl',                 'biceps',     'cable',      'reps', null, 12),

  -- triceps
  ('triceps-pushdown',         'Triceps Pushdown',           'triceps',    'cable',      'reps', null, 12),
  ('triceps-overhead-cable',   'Overhead Cable Extension',   'triceps',    'cable',      'reps', null, 12),
  ('triceps-skullcrusher',     'Skull Crusher',              'triceps',    'barbell',    'reps', null, 10),
  ('triceps-kickback',         'Triceps Kickback',           'triceps',    'dumbbell',   'reps', null, 12),
  ('bench-dip',                'Bench Dip',                  'triceps',    'bodyweight', 'reps', null, 12),
  ('close-grip-push-up',       'Close-Grip Push-Up',         'triceps',    'bodyweight', 'reps', null, 12),
  ('assisted-dip',             'Assisted Dip',               'triceps',    'machine',    'reps', null, 10),

  -- forearms
  ('wrist-curl',               'Wrist Curl',                 'forearms',   'dumbbell',   'reps', null, 15),
  ('farmers-carry',            'Farmer''s Carry',            'forearms',   'dumbbell',   'time',   45, null),
  ('dead-hang',                'Dead Hang',                  'forearms',   'bodyweight', 'time',   30, null),

  -- quads
  ('back-squat',               'Back Squat',                 'quads',      'barbell',    'reps', null,  8),
  ('front-squat',              'Front Squat',                'quads',      'barbell',    'reps', null,  8),
  ('goblet-squat',             'Goblet Squat',               'quads',      'kettlebell', 'reps', null, 12),
  ('hack-squat',               'Hack Squat',                 'quads',      'machine',    'reps', null, 10),
  ('leg-press',                'Leg Press',                  'quads',      'machine',    'reps', null, 12),
  ('leg-extension',            'Leg Extension',              'quads',      'machine',    'reps', null, 12),
  ('lunge-walking',            'Walking Lunge',              'quads',      'dumbbell',   'reps', null, 12),
  ('split-squat-bulgarian',    'Bulgarian Split Squat',      'quads',      'dumbbell',   'reps', null, 10),
  ('step-up',                  'Step-Up',                    'quads',      'dumbbell',   'reps', null, 10),
  ('squat-bodyweight',         'Bodyweight Squat',           'quads',      'bodyweight', 'reps', null, 20),

  -- hamstrings
  ('deadlift',                 'Conventional Deadlift',      'hamstrings', 'barbell',    'reps', null,  5),
  ('romanian-deadlift',        'Romanian Deadlift',          'hamstrings', 'barbell',    'reps', null,  8),
  ('leg-curl-lying',           'Lying Leg Curl',             'hamstrings', 'machine',    'reps', null, 12),
  ('leg-curl-seated',          'Seated Leg Curl',            'hamstrings', 'machine',    'reps', null, 12),
  ('good-morning',             'Good Morning',               'hamstrings', 'barbell',    'reps', null, 10),
  ('nordic-curl',              'Nordic Curl',                'hamstrings', 'bodyweight', 'reps', null,  6),
  ('glute-ham-raise',          'Glute-Ham Raise',            'hamstrings', 'bodyweight', 'reps', null,  8),

  -- glutes
  ('hip-thrust',               'Hip Thrust',                 'glutes',     'barbell',    'reps', null, 10),
  ('glute-bridge',             'Glute Bridge',               'glutes',     'bodyweight', 'reps', null, 15),
  ('sumo-deadlift',            'Sumo Deadlift',              'glutes',     'barbell',    'reps', null,  6),
  ('cable-kickback',           'Cable Glute Kickback',       'glutes',     'cable',      'reps', null, 12),
  ('hip-abduction',            'Hip Abduction',              'glutes',     'machine',    'reps', null, 15),

  -- calves
  ('calf-raise-standing',      'Standing Calf Raise',        'calves',     'machine',    'reps', null, 15),
  ('calf-raise-seated',        'Seated Calf Raise',          'calves',     'machine',    'reps', null, 15),
  ('calf-raise-bodyweight',    'Bodyweight Calf Raise',      'calves',     'bodyweight', 'reps', null, 20),

  -- core
  ('plank',                    'Plank',                      'core',       'bodyweight', 'time',   45, null),
  ('plank-side',               'Side Plank',                 'core',       'bodyweight', 'time',   30, null),
  ('hollow-hold',              'Hollow Body Hold',           'core',       'bodyweight', 'time',   30, null),
  ('crunch',                   'Crunch',                     'core',       'bodyweight', 'reps', null, 20),
  ('sit-up',                   'Sit-Up',                     'core',       'bodyweight', 'reps', null, 15),
  ('bicycle-crunch',           'Bicycle Crunch',             'core',       'bodyweight', 'reps', null, 20),
  ('leg-raise-hanging',        'Hanging Leg Raise',          'core',       'bodyweight', 'reps', null, 10),
  ('leg-raise-lying',          'Lying Leg Raise',            'core',       'bodyweight', 'reps', null, 12),
  ('russian-twist',            'Russian Twist',              'core',       'bodyweight', 'reps', null, 20),
  ('dead-bug',                 'Dead Bug',                   'core',       'bodyweight', 'reps', null, 12),
  ('bird-dog',                 'Bird Dog',                   'core',       'bodyweight', 'reps', null, 10),
  ('mountain-climber',         'Mountain Climber',           'core',       'bodyweight', 'time',   30, null),
  ('ab-wheel-rollout',         'Ab Wheel Rollout',           'core',       'other',      'reps', null, 10),
  ('cable-crunch',             'Cable Crunch',               'core',       'cable',      'reps', null, 15),
  ('pallof-press',             'Pallof Press',               'core',       'cable',      'reps', null, 12),

  -- full body
  ('burpee',                   'Burpee',                     'full_body',  'bodyweight', 'reps', null, 10),
  ('power-clean',              'Power Clean',                'full_body',  'barbell',    'reps', null,  5),
  ('kettlebell-swing',         'Kettlebell Swing',           'full_body',  'kettlebell', 'reps', null, 15),
  ('thruster',                 'Thruster',                   'full_body',  'barbell',    'reps', null, 10),
  ('turkish-getup',            'Turkish Get-Up',             'full_body',  'kettlebell', 'reps', null,  3),
  ('bear-crawl',               'Bear Crawl',                 'full_body',  'bodyweight', 'time',   30, null),
  ('clean-and-press',          'Clean and Press',            'full_body',  'dumbbell',   'reps', null,  8),

  -- cardio / conditioning
  ('jump-rope',                'Jump Rope',                  'cardio',     'other',      'time',   60, null),
  ('jumping-jack',             'Jumping Jack',               'cardio',     'bodyweight', 'time',   45, null),
  ('high-knees',               'High Knees',                 'cardio',     'bodyweight', 'time',   30, null),
  ('rowing-machine',           'Rowing Machine',             'cardio',     'machine',    'time',  300, null),
  ('rowing-intervals',         'Rowing Intervals',           'cardio',     'machine',    'time',   60, null),
  ('stationary-bike',          'Stationary Bike',            'cardio',     'machine',    'time',  300, null),
  ('treadmill-run',            'Treadmill Run',              'cardio',     'machine',    'time',  300, null),
  ('stair-climber',            'Stair Climber',              'cardio',     'machine',    'time',  300, null),

  -- mobility
  ('cat-cow',                  'Cat-Cow',                    'mobility',   'bodyweight', 'reps', null, 10),
  ('worlds-greatest-stretch',  'World''s Greatest Stretch',  'mobility',   'bodyweight', 'reps', null,  5),
  ('hip-flexor-stretch',       'Hip Flexor Stretch',         'mobility',   'bodyweight', 'time',   45, null),
  ('hamstring-stretch',        'Standing Hamstring Stretch', 'mobility',   'bodyweight', 'time',   45, null),
  ('thoracic-rotation',        'Thoracic Rotation',          'mobility',   'bodyweight', 'reps', null, 10),
  ('shoulder-passthrough',     'Shoulder Pass-Through',      'mobility',   'band',       'reps', null, 12),
  ('foam-roll-quads',          'Foam Roll Quads',            'mobility',   'other',      'time',   60, null),
  ('downward-dog',             'Downward Dog',               'mobility',   'bodyweight', 'time',   45, null),
  ('childs-pose',              'Child''s Pose',              'mobility',   'bodyweight', 'time',   60, null),

  -- warm-up staples
  ('arm-circles',              'Arm Circles',                'mobility',   'bodyweight', 'reps', null, 15),
  ('scapular-push-up',         'Scapular Push-Up',           'chest',      'bodyweight', 'reps', null, 10),
  ('inchworm',                 'Inchworm',                   'full_body',  'bodyweight', 'reps', null,  5)
on conflict (slug) do update set
  name                     = excluded.name,
  muscle_group             = excluded.muscle_group,
  equipment                = excluded.equipment,
  default_mode             = excluded.default_mode,
  default_duration_seconds = excluded.default_duration_seconds,
  default_reps             = excluded.default_reps;
