# Load test (4.2)

Run on Oct 17 on a MacBook Pro (Apple silicon), Postgres 17 and FalkorDB 4.10 in Docker, test database. NYI's real history is not imported yet (1.12), so the test generates an NYI-sized history on the NYI seed: 400 tasks and 3,000 chat messages over the four projects and five people.

```sh
cd api && mix test --only load test/load_test.exs
```

| Step | Result |
| --- | --- |
| Create 400 tasks (with event log) | 494 ms total, 1.2 ms each |
| Record 3,000 messages (dedupe, identity, event, job) | 7.2 s total, 2.4 ms each |
| Events in the log | 3,438 |
| Rebuild the graph from the log | 2.5 s (1,400 events/s) |
| `GET /directory` (median of 10) | 6 ms |
| `GET /tasks?project_id` (median of 10) | 2 ms |
| `POST /ask` "what's blocking Veriq?" (median of 10, no model) | 16 ms |
| `GET /projects/:id/brief` (median of 5) | 14 ms |
| `GET /experts?project_id` (median of 5, refreshes `KNOWS_ABOUT`, PageRank) | 16 ms |

What this means:

- Ingest is not the bottleneck: one Fly machine records NYI's busiest day in well under a second. Every append takes a global lock to keep the log in order; at about 400 appends a second that leaves plenty of room for a team of NYI's size.
- A full graph rebuild of NYI's history takes seconds, so replaying the log is a practical recovery path.
- Reads stay in single-digit to low double-digit milliseconds. With `OPENAI_API_KEY` set, `@noa` and extraction are dominated by the model call (about 1 to 3 s), not by Noa.
- Not measured: the extraction model's throughput and cost on real messages (0.9), and Phoenix Channels fan-out (2.14).
