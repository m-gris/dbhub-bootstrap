// ============================================================================
// mcp-db - One-command database MCP setup for Claude Code
// ============================================================================

import { pickDsn, mask } from 'pick-dsn'
import { writeDbhubConfig, getDbhubCommand } from './backends/dbhub.js'
import { removeMcpServer, addMcpServer, isClaudeAvailable } from './claude.js'
import { appendFile, access } from 'node:fs/promises'
import { join, dirname } from 'node:path'

export interface SetupOptions {
  /** Working directory (default: auto-detect from .git or cwd) */
  readonly cwd?: string
  /** MCP server name (default: 'dbhub') */
  readonly serverName?: string
  /** Backend to use (default: 'dbhub') */
  readonly backend?: 'dbhub'
  /** Read-only mode (default: true) */
  readonly readonly?: boolean
  /** Max rows for queries (default: 1000) */
  readonly maxRows?: number
}

/**
 * Find project root by walking up to find .git directory.
 * Pure computation: given a starting dir, return project root or null.
 *
 * @param startDir - Directory to start searching from
 * @returns Project root path or null if not found
 */
export async function findProjectRoot(startDir: string): Promise<string | null> {
  let currentDir = startDir
  const root = dirname('/') // platform-agnostic root

  while (currentDir !== root) {
    try {
      await access(join(currentDir, '.git'))
      return currentDir
    } catch {
      // .git not found, continue up
      const parentDir = dirname(currentDir)
      if (parentDir === currentDir) {
        // Reached root without finding .git
        break
      }
      currentDir = parentDir
    }
  }

  return null
}

/**
 * Main setup flow:
 * 1. Pick DSN using pick-dsn
 * 2. Generate config file
 * 3. Add to .gitignore
 * 4. Register with Claude Code
 */
export async function setup(options: SetupOptions = {}): Promise<void> {
  // Determine working directory: explicit cwd > project root > process.cwd()
  let workingDir: string
  if (options.cwd) {
    workingDir = options.cwd
  } else {
    const projectRoot = await findProjectRoot(process.cwd())
    workingDir = projectRoot ?? process.cwd()
  }

  const {
    serverName = 'dbhub',
    backend = 'dbhub',
    readonly = true,
    maxRows = 1000
  } = options

  const cwd = workingDir

  // Check Claude CLI
  const claudeAvailable = await isClaudeAvailable()
  if (!claudeAvailable) {
    throw new Error('Claude CLI not found. Install: https://claude.ai/code')
  }

  // Step 1: Pick DSN
  console.error('🔍 Select your database connection...\n')
  const result = await pickDsn()

  if (result.type === 'cancelled') {
    console.error('Cancelled.')
    process.exit(1)
  }

  const dsn = result.dsn
  console.error(`\n✓ Using: ${mask(dsn)}`)

  // Step 2: Generate config
  let configPath: string

  if (backend === 'dbhub') {
    configPath = await writeDbhubConfig(cwd, { dsn, readonly, maxRows })
    console.error(`✓ Created: ${configPath}`)
  } else {
    throw new Error(`Unknown backend: ${backend}`)
  }

  // Step 3: Add to .gitignore
  await ensureGitignore(cwd, '.dbhub.toml')

  // Step 4: Register with Claude Code
  console.error(`\n📡 Registering MCP server...`)
  await removeMcpServer(serverName)

  const command = getDbhubCommand(configPath)
  await addMcpServer(serverName, command)

  console.error(`\n✅ Done! Restart Claude Code to connect.`)
  console.error(`   Run /mcp to verify the connection.`)
}

/**
 * Ensure a pattern is in .gitignore (if .gitignore exists).
 */
async function ensureGitignore(dir: string, pattern: string): Promise<void> {
  const gitignorePath = join(dir, '.gitignore')

  try {
    await access(gitignorePath)
  } catch {
    // No .gitignore, skip
    return
  }

  const { readFile } = await import('node:fs/promises')
  const content = await readFile(gitignorePath, 'utf-8')

  if (!content.includes(pattern)) {
    await appendFile(gitignorePath, `\n${pattern}\n`)
    console.error(`✓ Added ${pattern} to .gitignore`)
  }
}

// Re-export for library usage
export { pickDsn, mask, normalize, isDbDsn } from 'pick-dsn'
export { generateDbhubToml, writeDbhubConfig } from './backends/dbhub.js'
export { addMcpServer, removeMcpServer, isClaudeAvailable } from './claude.js'
// findProjectRoot is exported above
