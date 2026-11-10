# llm-structured-extraction

A small Ruby CLI that turns free-text event announcements into typed, validated fields. It cleans the HTML, sends each announcement to the OpenAI Responses API with a strict JSON Schema, checks the answer against the same schema locally, and writes one CSV row per record.

Standard library only: no gems, no SDK.

## Example

One record from [`examples/events.json`](examples/events.json):

```json
{
  "record_id": "evt-002",
  "source": "Northlight Events",
  "posted_on": "2026-01-15",
  "title": "Applied ML Summit 2026",
  "description": "<h1>Applied ML Summit 2026</h1>\n<p><b>14&ndash;15 May 2026 &bull; Berlin</b></p> ... <p>Registration opens at 08:15. Opening keynote at 09:00.</p> ... <p>Early bird: &euro;249 (until 1 April)<br>Regular: &euro;349<br>Student: &euro;120 with valid ID</p> ..."
}
```

The fields the pipeline is expected to produce for it, from the hand-labelled [`examples/expected.json`](examples/expected.json):

| event_type | start_date | start_time | format | city | is_free | price_amount | price_currency | topic |
|---|---|---|---|---|---|---|---|---|
| conference | 2026-05-14 | 09:00 | in_person | Berlin | false | 349 | EUR | data_ai |

The interesting part is what must be ignored: the registration time, the early-bird and student prices, and the second day.

## Status

The pipeline, the prompt, the schema and the tests are in place. **No model run is committed yet**, so this repo does not claim any accuracy. The steps to record a run and score it are under [Record and replay](#record-and-replay) and [Evaluation](#evaluation).

## How it works

```text
examples/events.json
      │  runner.rb reads the records
      ▼
utils/normalizer.rb        HTML → plain text (drops script/style, decodes entities, keeps line breaks)
      │
      ▼
llm_extractor.rb           POST /v1/responses with
      │                      instructions = prompts/event_extraction/v1.md
      │                      text.format  = schema/event.schema.json (strict)
      ▼
utils/schema_validator.rb  the answer is checked against the same schema locally
      │
      ▼
CSV                        one row per record: status, error, and one column per schema field
```

- **Prompt and schema live in the repo.** [`prompts/event_extraction/v1.md`](prompts/event_extraction/v1.md) defines every field and its edge cases; [`schema/event.schema.json`](schema/event.schema.json) defines types, enums and formats. `LLM_PROMPT_VERSION` selects the prompt file.
- **Failures are rows, not silence.** Every record gets a row. If extraction fails, `status` says why and the field columns stay empty. The process exits with code 1 if any record failed.
- **Results are written as they arrive**, so an interrupted run keeps the rows it finished.

| status | meaning |
|---|---|
| `ok` | output parsed and matches the schema |
| `api_error` | network failure or non-2xx HTTP status (the message carries the status and the API's error text) |
| `invalid_response` | the API response was not the expected JSON |
| `incomplete` | the model stopped before finishing |
| `refused` | the model declined to answer |
| `invalid_json` | the model's output is not JSON |
| `invalid_schema` | the output is JSON but breaks the schema (the message lists each violation) |
| `invalid_record` | the input record is not an object or has no description |

## Run it

Requires Ruby 3.3 or newer.

```bash
export OPENAI_API_KEY=sk-...
ruby runner.rb examples/events.json
```

Optional environment variables: `OPENAI_MODEL` (default `gpt-5.2`) and `LLM_PROMPT_VERSION` (default `1`). Use `--out FILE` to choose the CSV path.

### Record and replay

```bash
# call the API and keep each raw response
ruby runner.rb --record examples/recorded --out examples/output.csv examples/events.json

# rebuild the same CSV from the saved responses: no API key, no network
ruby runner.rb --replay examples/recorded --out /tmp/out.csv examples/events.json
```

Replay runs the saved responses through the same parsing and validation code as a live run.

## Evaluation

[`examples/expected.json`](examples/expected.json) holds hand-written labels for the ten sample announcements. `eval.rb` compares an output CSV with them by exact match per field:

```bash
ruby eval.rb examples/output.csv examples/expected.json
```

The samples are written to cover specific traps: a deadline table next to the real conference date, early-bird and student prices next to the regular one, a doors-open time before the programme start, a relative date ("this Friday"), a missing date, an online event that mentions the organiser's city, tracking scripts with misleading values, and two announcements in Turkish.

A schema-valid answer is not necessarily a correct one. Validation only proves the output has the right shape; `eval.rb` is what checks the values against the source text.

## Tests

```bash
rake test
```

The tests need no API key. They cover HTML cleanup, schema validation, every extractor status, record/replay, the evaluation script, and the CLI end to end.

## Limitations

- Ten hand-written samples are a smoke test, not a benchmark.
- No retry or backoff: a rate-limited or failed call becomes an `api_error` row.
- Records are processed one at a time.
- Descriptions are cut at 4000 characters after cleanup (a warning is printed).
- The validator supports only the JSON Schema subset this schema uses.
- HTML cleanup is regex-based and decodes only numeric and the most common named entities.

## Sample data

All announcements in `examples/` are fictional and were written for this repo. Organisers, venues and events are made up.

## Layout

```text
.
├── runner.rb                 CLI: read records, run extraction, write CSV
├── llm_extractor.rb          request building, response interpretation, statuses
├── eval.rb                   exact-match scoring against expected labels
├── utils/
│   ├── normalizer.rb         HTML → text
│   ├── schema_validator.rb   JSON Schema subset validator
│   ├── transport.rb          live / recording / replay transports
│   └── http_wrapper.rb       JSON POST over Net::HTTP with timeouts
├── prompts/event_extraction/v1.md
├── schema/event.schema.json
├── examples/                 sample announcements and expected labels
└── test/
```
