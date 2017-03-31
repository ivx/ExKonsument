defmodule ExKonsument.HandlingError do
  defexception message: "Handling function did not return :ok", return: nil
end
