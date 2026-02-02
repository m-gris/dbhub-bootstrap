#!/usr/bin/env node
// ============================================================================
// CLI Entry Point
// ============================================================================

import { setup, type SetupOptions } from '../index.js'

/**
 * Parse --cwd flag from process.argv.
 * Pure computation: given argv, return cwd or undefined.
 */
function parseCwd(argv: string[]): string | undefined {
  const cwdIndex = argv.indexOf('--cwd')
  if (cwdIndex !== -1 && cwdIndex + 1 < argv.length) {
    return argv[cwdIndex + 1]
  }
  return undefined
}

async function main(): Promise<void> {
  const cwd = parseCwd(process.argv)

  const options: SetupOptions = cwd !== undefined ? { cwd } : {}

  try {
    await setup(options)
  } catch (error) {
    // Handle Ctrl+C gracefully
    if ((error as NodeJS.ErrnoException).code === 'ERR_USE_AFTER_CLOSE') {
      process.exit(130)
    }

    console.error('Error:', (error as Error).message)
    process.exit(1)
  }
}

main()
