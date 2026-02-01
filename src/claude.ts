// ============================================================================
// Claude Code Integration - Register MCP servers
// ============================================================================

import { spawn } from 'node:child_process'

/**
 * Remove an MCP server from Claude Code (if exists).
 */
export async function removeMcpServer(name: string): Promise<void> {
  return new Promise((resolve) => {
    const proc = spawn('claude', ['mcp', 'remove', name], {
      stdio: 'ignore'
    })
    proc.on('close', () => resolve())
    proc.on('error', () => resolve()) // Ignore errors (server might not exist)
  })
}

/**
 * Add an MCP server to Claude Code.
 */
export async function addMcpServer(
  name: string,
  command: string[]
): Promise<void> {
  return new Promise((resolve, reject) => {
    const args = ['mcp', 'add', name, '--', ...command]
    const proc = spawn('claude', args, {
      stdio: 'inherit'
    })

    proc.on('close', (code) => {
      if (code === 0) {
        resolve()
      } else {
        reject(new Error(`claude mcp add failed with code ${code}`))
      }
    })

    proc.on('error', (err) => {
      reject(new Error(`Failed to run claude: ${err.message}`))
    })
  })
}

/**
 * Check if Claude CLI is available.
 */
export async function isClaudeAvailable(): Promise<boolean> {
  return new Promise((resolve) => {
    const proc = spawn('claude', ['--version'], {
      stdio: 'ignore'
    })
    proc.on('close', (code) => resolve(code === 0))
    proc.on('error', () => resolve(false))
  })
}
