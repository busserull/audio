defmodule An.Mixer do
  use GenServer

  alias Phoenix.PubSub
  alias An.Logger

  @default_panel {1.0, 0.5, 0.5}
  @drop_count 5

  def start_link(opts) do
    send_interval = Keyword.fetch!(opts, :send_interval)
    GenServer.start_link(__MODULE__, send_interval, name: __MODULE__)
  end

  def add_stream(from, stream) do
    GenServer.cast(__MODULE__, {:add_stream, from, stream})
  end

  def get_panel() do
    GenServer.call(__MODULE__, :get_panel)
  end

  def init(send_interval) do
    PubSub.subscribe(An.PubSub, "panel")
    :timer.send_interval(send_interval, :send_stream)
    {:ok, {1.0, %{}}}
  end

  def handle_call(:get_panel, _from, {master_volume, %{}}) do
    {:reply, {master_volume, []}, {master_volume, %{}}}
  end

  def handle_call(:get_panel, _from, {master_volume, streams}) do
    incoming = Enum.reduce(streams, fn {source, {settings, _, _}} -> {source, settings} end)
    {:reply, {master_volume, incoming}, {master_volume, streams}}
  end

  def handle_cast({:add_stream, from, stream}, {master_volume, streams}) do
    unless Map.has_key?(streams, from) do
      broadcast({:new_stream, from, @default_panel})
    end

    new_streams =
      Map.update(
        streams,
        from,
        {@default_panel, @drop_count, stream},
        fn {settings, _drop_count, buffer} ->
          {settings, @drop_count, buffer ++ stream}
        end
      )

    {:noreply, {master_volume, new_streams}}
  end

  def handle_info(:send_stream, {master_volume, streams}) do
    An.Synth.merge_and_send(master_volume, Map.values(streams))

    {kept_streams, dead_streams} =
      Enum.split_with(streams, fn {_, {_, drop_count, _}} -> drop_count > 0 end)

    Enum.each(dead_streams, fn {source, _} ->
      Logger.log_dropped_connection(source)
      broadcast({:drop_stream, source})
    end)

    streams =
      for {source, {settings, drop_count, _buffer}} <- kept_streams, into: %{} do
        {source, {settings, drop_count - 1, []}}
      end

    {:noreply, {master_volume, streams}}
  end

  def handle_info({:master_volume, master_volume}, {_, streams}) do
    {:noreply, {master_volume, streams}}
  end

  def handle_info({:change_panel, source, settings}, {master_volume, streams}) do
    streams =
      Map.update!(streams, source, fn {_, drop_count, buffer} ->
        {settings, drop_count, buffer}
      end)

    {:noreply, {master_volume, streams}}
  end

  def handle_info({:new_stream, _, _}, state) do
    {:noreply, state}
  end

  def handle_info({:drop_stream, _}, state) do
    {:noreply, state}
  end

  defp broadcast(message) do
    PubSub.broadcast(An.PubSub, "panel", message)
  end
end
