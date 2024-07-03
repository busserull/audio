defmodule AnWeb.PageLive do
  use AnWeb, :live_view

  alias Phoenix.PubSub
  alias An.Mixer

  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.subscribe(An.PubSub, "panel")
      {master_volume, panel} = Mixer.get_panel()

      panel = Enum.map(panel, fn {source, settings} -> {format_source(source), settings} end)

      {:ok, assign(socket, master_volume: master_volume, panel: panel)}
    else
      {:ok, assign(socket, master_volume: 1.0, panel: [])}
    end
  end

  def handle_event("set-master-volume", %{"volume" => volume}, socket) do
    broadcast({:master_volume, String.to_integer(volume) / 100})
    {:noreply, socket}
  end

  def handle_event("change-panel-settings", params, socket) do
    %{
      "source" => source,
      "volume" => volume,
      "balance" => balance
    } = params

    source = parse_source(source)
    volume = String.to_integer(volume) / 100
    balance = String.to_integer(balance) / 100

    right = 1.0 - balance
    left = balance

    broadcast({:change_panel, source, {volume, right, left}})

    {:noreply, socket}
  end

  def handle_info({:master_volume, volume}, socket) do
    {:noreply, assign(socket, :master_volume, volume)}
  end

  def handle_info({:new_stream, source, settings}, socket) do
    source = format_source(source)

    if Enum.find(socket.assigns.panel, fn {s, _} -> s == source end) do
      {:noreply, socket}
    else
      {:noreply, update(socket, :panel, &[{source, settings} | &1])}
    end
  end

  def handle_info({:drop_stream, source}, socket) do
    source = format_source(source)
    panel = Enum.reject(socket.assigns.panel, fn {s, _} -> s == source end)
    {:noreply, assign(socket, :panel, panel)}
  end

  def handle_info({:change_panel, source, settings}, socket) do
    source = format_source(source)

    panel =
      Enum.map(socket.assigns.panel, fn {s, current} ->
        if s == source do
          {s, settings}
        else
          {s, current}
        end
      end)

    {:noreply, assign(socket, :panel, panel)}
  end

  defp broadcast(message) do
    PubSub.broadcast(An.PubSub, "panel", message)
  end

  defp format_source({{a, b, c, d}, port}) do
    "#{a}.#{b}.#{c}.#{d}:#{port}"
  end

  defp parse_source(source) do
    [ip, port] = String.split(source, ":")
    [a, b, c, d] = ip |> String.split(".") |> Enum.map(&String.to_integer/1)

    {{a, b, c, d}, String.to_integer(port)}
  end
end
