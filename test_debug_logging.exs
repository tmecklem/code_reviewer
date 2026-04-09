#!/usr/bin/env elixir

# Test to demonstrate the difference between debug and non-debug mode

IO.puts(String.duplicate("=", 80))
IO.puts("TESTING LOGGING CONFIGURATION")
IO.puts(String.duplicate("=", 80))

IO.puts("\n1. WITHOUT --debug flag:")
IO.puts("   The logs should show:")
IO.puts("   - Progress messages (which rule group is running)")
IO.puts("   - Summary of findings")
IO.puts("   - NO verbose debug output")

IO.puts("\n2. WITH --debug flag:")
IO.puts("   The logs should show:")
IO.puts("   - All of the above PLUS")
IO.puts("   - Detailed ACP messages")
IO.puts("   - Tool input/output")
IO.puts("   - Session updates")

IO.puts("\nTo test, run these commands:")
IO.puts("\n# Without debug (clean output):")
IO.puts("MIX_ENV=dev mix review tmecklem/code_reviewer 1 --groups blocking 2>&1 | head -50")

IO.puts("\n# With debug (verbose output):")
IO.puts("MIX_ENV=dev mix review tmecklem/code_reviewer 1 --groups blocking --debug 2>&1 | head -50")

IO.puts("\n\n")
IO.puts("The key difference is that --debug shows all the internal")
IO.puts("workings while the default mode only shows essential progress.")