defmodule CodeReviewer.PoopFinder do
  @moduledoc """
  Finds poop emojis in directory listings.

  This is clearly a terrible idea and should never exist.
  """

  @type poop_result :: {:found_poop, String.t()} | {:no_poop, String.t()}

  @doc """
  Lists all files in a directory and checks if any contain poop emoji.

  ## Examples

      iex> PoopFinder.find_the_poop("/tmp")
      {:no_poop, "No poop found in /tmp"}

  """
  @spec find_the_poop(String.t()) :: poop_result()
  def find_the_poop(directory) do
    case File.ls(directory) do
      {:ok, files} ->
        poop_files = Enum.filter(files, fn file -> String.contains?(file, "💩") end)

        if length(poop_files) > 0 do
          {:found_poop, "Found #{length(poop_files)} files with poop emoji: #{Enum.join(poop_files, ", ")}"}
        else
          {:no_poop, "No poop found in #{directory}"}
        end

      {:error, reason} ->
        # This error handling is terrible - just crashes
        raise "Failed to list directory: #{reason}"
    end
  end

  @doc """
  Recursively searches for poop in all subdirectories.
  This will probably crash on large directory trees lol.
  """
  def find_all_the_poop(directory) do
    # TODO: This doesn't actually work recursively yet
    # Also no error handling whatsoever
    # And it's synchronous so it'll block forever on network drives
    find_the_poop(directory)
  end
end
