# dbhub-bootstrap

One command to give your AI assistant database access.

## Why?

[dbhub](https://github.com/bytebase/dbhub) is an MCP server that lets AI assistants query databases. But setting it up means:

- Installing Node/npx
- Writing TOML config files
- Registering the MCP server with your client
- Remembering the incantation for each new project

**dbhub-bootstrap** reduces this to:

```bash
curl -fsSL https://raw.githubusercontent.com/m-gris/dbhub-bootstrap/main/bootstrap.sh | bash
```

Then, in any project:

```bash
just -g mcp dbhub init    # interactive DSN picker, writes config, registers MCP
```

Done. Your AI can now query your database.

## Usage

```bash
just -g mcp dbhub init      # configure database for current project
just -g mcp dbhub status    # check current config
just -g mcp dbhub remove    # unregister MCP server
```

The init wizard:
- Scans your environment for database URLs (`DATABASE_URL`, `*_DSN`, etc.)
- Lets you pick or enter a DSN manually
- Writes `.dbhub.toml` (gitignored)
- Registers dbhub with Claude Code

## Requirements

- macOS with [Homebrew](https://brew.sh)
- [Claude Code](https://claude.ai/code) CLI

## How It Works

Bootstrap installs two tools:
- **[gum](https://github.com/charmbracelet/gum)** — pretty terminal UI
- **[just](https://github.com/casey/just)** — task runner

Then clones this repo to `~/.dbhub-bootstrap` for the lib/bin scripts.

The architecture follows FP principles — small composable pieces, side effects at the edges:

```
lib/config.sh   → constants
lib/detect.sh   → read-only queries
lib/compute.sh  → pure transforms
lib/actions.sh  → atomic side effects
lib/ui.sh       → gum wrappers
bin/*           → orchestration
```

## License

MIT
