-- Example state store for §2 of the skill (PostgreSQL).
-- The handoff memory holds the narrative; these tables make it queryable.
-- The constraints are deliberate: they are what the GOTCHAS in the skill are about.

CREATE TABLE IF NOT EXISTS session_handoff (
  id             bigserial PRIMARY KEY,
  session_id     text        NOT NULL,
  handoff_prompt text        NOT NULL,          -- the §3 resume prompt
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS decisions (
  id          bigserial PRIMARY KEY,
  title       text NOT NULL,
  rationale   text,
  applies_to  text,                              -- project name
  status      text NOT NULL
              CHECK (status IN ('pending','implemented','superseded','deferred','rejected')),
  session     text,
  "timestamp" text NOT NULL,                     -- keyword as a name: quote it; text, so now()::text
  decided_at  timestamptz
);

CREATE TABLE IF NOT EXISTS code_map (
  id              bigserial PRIMARY KEY,
  module          text,
  path            text NOT NULL,                 -- no unique constraint: DELETE the path before re-inserting
  lines           integer,
  purpose         text,
  bounded_context text
);
