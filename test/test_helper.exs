ExUnit.start()

# Setup mocks if Mox is available
if Code.ensure_loaded?(Mox) do
  Application.ensure_all_started(:mox)
end
