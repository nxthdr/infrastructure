# Infrastructure Documentation

This directory contains the documentation for the nxthdr infrastructure repository, built with [MkDocs](https://www.mkdocs.org/) and [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/).

## Quick Links

- **Live Documentation**: https://nxthdr.github.io/infrastructure/
- **Repository**: https://github.com/nxthdr/infrastructure

## Local Development

### Prerequisites

- Python 3.8+
- pip

### Setup

1. Install dependencies:

```bash
pip install -r requirements.txt
```

2. Serve documentation locally:

```bash
mkdocs serve
```

The documentation will be available at http://127.0.0.1:8000

### Build

To build the static site:

```bash
mkdocs build
```

Output will be in the `site/` directory.

## Documentation Structure

```
docs/
├── mkdocs.yml              # MkDocs configuration
├── requirements.txt        # Python dependencies
├── docs/                   # Documentation source
│   ├── index.md           # Homepage
│   ├── getting-started/   # Getting started guides
│   ├── guides/            # Task-specific guides
│   ├── reference/         # Technical reference
│   └── ai/                # AI assistant guides
└── site/                  # Built site (gitignored)
```

## Contributing

To add or update documentation:

1. Edit Markdown files in `docs/`
2. Test locally with `mkdocs serve`
3. Commit and push changes
4. GitHub Actions will automatically deploy to GitHub Pages

## Deployment

Documentation is automatically deployed to GitHub Pages via GitHub Actions when changes are pushed to the `main` branch.

