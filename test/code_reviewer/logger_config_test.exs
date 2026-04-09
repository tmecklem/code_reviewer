defmodule CodeReviewer.LoggerConfigTest do
  use ExUnit.Case, async: true

  alias CodeReviewer.LoggerConfig

  describe "configure/1" do
    test "sets log level to info by default" do
      LoggerConfig.configure()
      assert Logger.level() == :info
    end

    test "sets log level to debug when debug flag is true" do
      LoggerConfig.configure(debug: true)
      assert Logger.level() == :debug
    end

    test "sets log level to info when debug flag is false" do
      LoggerConfig.configure(debug: false)
      assert Logger.level() == :info
    end

    test "sets log level to info when debug flag is nil" do
      LoggerConfig.configure(debug: nil)
      assert Logger.level() == :info
    end
  end

  describe "debug_enabled?/0" do
    test "returns true when debug is enabled" do
      LoggerConfig.configure(debug: true)
      assert LoggerConfig.debug_enabled?()
    end

    test "returns false when debug is disabled" do
      LoggerConfig.configure(debug: false)
      refute LoggerConfig.debug_enabled?()
    end

    test "returns false by default" do
      LoggerConfig.configure()
      refute LoggerConfig.debug_enabled?()
    end
  end

  describe "log_progress/2" do
    import ExUnit.CaptureLog

    test "logs progress messages at info level" do
      log = capture_log(fn ->
        LoggerConfig.log_progress("Testing", "Running test suite")
      end)

      assert log =~ "[Testing] Running test suite"
    end

    test "includes group name when provided" do
      log = capture_log(fn ->
        LoggerConfig.log_progress("Review", "Processing", group: "Security Rules")
      end)

      assert log =~ "[Review - Security Rules] Processing"
    end
  end

  describe "log_debug/2" do
    import ExUnit.CaptureLog

    test "logs debug messages only when debug is enabled" do
      LoggerConfig.configure(debug: true)

      log = capture_log([level: :debug], fn ->
        LoggerConfig.log_debug("Test", "Debug message")
      end)

      assert log =~ "[Test] Debug message"
    end

    test "does not log debug messages when debug is disabled" do
      LoggerConfig.configure(debug: false)

      log = capture_log([level: :debug], fn ->
        LoggerConfig.log_debug("Test", "Debug message")
      end)

      refute log =~ "Debug message"
    end
  end
end