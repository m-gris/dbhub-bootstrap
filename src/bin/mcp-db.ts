#!/usr/bin/env node
// ============================================================================
// CLI Entry Point
// ============================================================================

import { setup } from '../index.js'

async function main(): Promise<void> {
  // Simple CLI - no args needed for now
  // Future: could add --backend, --name, --readonly flags

  try {
    await setup()
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
