defmodule An.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    logfile = System.get_env("LOGFILE", "audionode.log")
    send_interval = System.get_env("BUFFER_SIZE", "200") |> String.to_integer()
    listener_port = System.get_env("LISTEN_PORT", "4030") |> String.to_integer()
    {dest_address, dest_port} = System.get_env("DEST", "127.0.0.1:4040") |> get_dest()

    children = [
      AnWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:audionode, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: An.PubSub},
      # Start the Finch HTTP client for sending emails
      # {Finch, name: An.Finch},
      # Start a worker by calling: An.Worker.start_link(arg)
      # {An.Worker, arg},
      # Start to serve requests, typically the last entry
      AnWeb.Endpoint,
      An.Logger.Timer,
      {An.Logger, logfile: logfile},
      {An.Streamer, address: dest_address, port: dest_port},
      {An.Mixer, send_interval: send_interval},
      {An.Listener, port: listener_port}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: An.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AnWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp get_dest(destination) do
    [ip, port] = String.split(destination, ":")
    [a, b, c, d] = ip |> String.split(".") |> Enum.map(&String.to_integer/1)

    {{a, b, c, d}, String.to_integer(port)}
  end
end
