# .src.py

class Project:
    name = "simvox"


class Ollama:
    enabled = True

    commit_model = "llama3.2:3b"

    analysis_model = "qwen2.5-coder:7b-instruct-q4_K_M"
    review_model = "qwen2.5-coder:7b-instruct-q4_K_M"

    host = "http://localhost:11434"
    timeout = 60

    commit_workers = 2


class Sync:
    enabled = False
    debounce_seconds = 15
    push = False


class Git:
    branch = "main"
    remote = "origin"

    fallback_commit_message = "chore: update {file}"

    auto_commit_small_changes = True
    small_change_threshold = 10


class Formatter:
    enabled = True
    max_blank_lines = 2


IGNORE = [
    "*.log",
    ".env",
    "node_modules",
    "coverage",
    ".pm",
]