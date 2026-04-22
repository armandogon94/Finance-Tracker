# Gotchas & Lessons Learned

- **JSON vs JSONB:** Use `JSON` not `JSONB`/`ARRAY` in SQLAlchemy models — JSONB is PostgreSQL-only, breaks SQLite tests
- **bcrypt 4.x:** Use `bcrypt` directly, NOT `passlib` — passlib has compatibility issues with bcrypt 4.x on Python 3.12+
- **Next.js 14 config:** Use `.mjs` not `.ts` for config files (next.config.mjs)
- **vitest pooling:** Exclude `vitest.config.ts` from tsconfig to prevent vite version conflicts; use `pool: "threads"` not forks (forks timeout with spaces in path)
- **lucide-react icons:** Don't accept `title` prop — wrap in `<span title="">` instead
- **CSS properties:** `ringColor` is invalid — use `outlineColor` instead
- **SQLite datetimes:** Stored without timezone — strip tzinfo before comparing with timezone-aware values
- **pytest conftest:** Must `drop_all` BEFORE `create_all` to handle stale test.db files
- **vitest + vite version:** vitest 1.x incompatible with vite 7+; must use vitest 4.x with vite 8.x
- **Naive/aware datetime fix:** PostgreSQL and SQLite handle timezones differently — use `datetime.now()` (naive) for SQLite compatibility, convert in SQL queries
