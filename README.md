# llm-structured-extraction

A lightweight Ruby pipeline for extracting structured data from semi-structured text using versioned LLM prompts.

The project takes JSON records as input, cleans and normalizes text fields, sends them to an LLM for structured extraction, and exports the results as CSV.

## Pipeline

JSON records  
      │  
      ▼  
HTML / text normalization  
      │  
      ▼  
LLM structured extraction  
      │  
      ▼  
CSV export

## Features

- JSON-based input pipeline
- HTML/text cleanup utilities
- lightweight HTTP wrapper for API requests
- versioned prompt support
- structured output parsing from the OpenAI Responses API
- CSV export with UTF-8-safe output handling

## Structure
```text
.
├── utils/
│   ├── http_wrapper.rb
│   └── normalizer.rb
├── llm_extractor.rb
├── runner.rb
├── .env.example
├── .gitignore
├── LICENSE
└── README.md
```
