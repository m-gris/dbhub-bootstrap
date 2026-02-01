// ============================================================================
// DBHub Backend - Generate .dbhub.toml configuration
// ============================================================================

import { writeFile } from 'node:fs/promises'
import { join } from 'node:path'

export interface DbhubConfig {
  readonly dsn: string
  readonly readonly?: boolean
  readonly maxRows?: number
}

/**
 * Generate .dbhub.toml content.
 */
export function generateDbhubToml(config: DbhubConfig): string {
  const { dsn, readonly = true, maxRows = 1000 } = config

  return `[[sources]]
id = "default"
dsn = "${dsn}"

[[tools]]
name = "execute_sql"
source = "default"
readonly = ${readonly}
max_rows = ${maxRows}
`
}

/**
 * Write .dbhub.toml to the specified directory.
 */
export async function writeDbhubConfig(
  dir: string,
  config: DbhubConfig
): Promise<string> {
  const content = generateDbhubToml(config)
  const configPath = join(dir, '.dbhub.toml')
  await writeFile(configPath, content, 'utf-8')
  return configPath
}

/**
 * Get the npx command to run dbhub with config.
 */
export function getDbhubCommand(configPath: string): string[] {
  return [
    'npx', '-y', '@bytebase/dbhub@latest',
    '--transport', 'stdio',
    '--config', configPath
  ]
}
