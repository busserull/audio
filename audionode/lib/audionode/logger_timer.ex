defmodule An.Logger.Timer do
  use Agent

  def start_link(_) do
    Agent.start_link(fn -> System.monotonic_time() end, name: __MODULE__)
  end

  def timestamp do
    Agent.get(__MODULE__, fn started_at ->
      (System.monotonic_time() - started_at)
      |> System.convert_time_unit(:native, :millisecond)
      |> Integer.to_string()
      |> String.pad_leading(12, " ")
    end)
  end
end
