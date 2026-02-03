# dbhub - Database access for Claude Code

_bin := "$HOME/.mcp-db/bin"

# Initialize dbhub for current project
[no-cd]
init:
    {{ _bin }}/dbhub-init

# Show current configuration
[no-cd]
status:
    {{ _bin }}/dbhub-status

# Remove dbhub
remove:
    {{ _bin }}/dbhub-remove
