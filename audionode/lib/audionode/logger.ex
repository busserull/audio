defmodule An.Logger do
  use GenServer

  alias An.Logger.Timer

  def start_link(opts) do
    logfile = Keyword.fetch!(opts, :logfile)
    GenServer.start_link(__MODULE__, logfile, name: __MODULE__)
  end

  def log_packet(from, seq) do
    GenServer.cast(__MODULE__, {:log_packet, from, seq})
  end

  def log_dropped_connection(source) do
    GenServer.cast(__MODULE__, {:dropped_connection, source})
  end

  def init(path) do
    {:ok, file} = File.open(path, [:append, :utf8])
    {:ok, {file, %{}}}
  end

  def handle_cast({:log_packet, from, seq}, {log, tally}) do
    ts = Timer.timestamp()
    source = fmt_from(from)

    case Map.get(tally, from) do
      nil ->
        IO.write(log, "[#{ts}] [#{source}] New connection\n")

      last when last == seq ->
        IO.write(log, "[#{ts}] [#{source}] Repeated packet\n")

      last when last > seq ->
        IO.write(log, "[#{ts}] [#{source}] Out of order packets\n")

      last when last != seq - 1 ->
        IO.write(log, "[#{ts}] [#{source}] Missing packets\n")

      _ ->
        :ok
    end

    {:noreply, {log, Map.put(tally, from, seq)}}
  end

  def handle_cast({:dropped_connection, source}, {log, tally}) do
    IO.write(log, "[#{Timer.timestamp()}] [#{fmt_from(source)}] Dropped connection\n")
    {:noreply, {log, Map.drop(tally, [source])}}
  end

  def terminate(_reason, {log, _}) do
    File.close(log)
  end

  defp fmt_from({{a, b, c, d}, port}) do
    String.pad_leading("#{a}.#{b}.#{c}.#{d}:#{port}", 21, " ")
  end
end
