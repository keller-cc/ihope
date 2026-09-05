-- Optional helper if connecting to an empty Postgres without compose defaults.
-- Prefer `docker compose up` in appserver/ which creates ihope_web automatically.
CREATE DATABASE ihope_web;
