defmodule Caravan.Registry.ConflictHandler do
  @moduledoc false
  use GenServer
  require Logger

  def start_link(name, {_, _, _} = mfa, callback) do
    via_tuple = Caravan.Registry.via_tuple(name)
    GenServer.start_link(__MODULE__, [name: name, mfa: mfa, callback: callback], name: via_tuple)
  end

  def start_link(name, pid) when is_pid(pid) do
    via_tuple = Caravan.Registry.via_tuple(name)
    GenServer.start_link(__MODULE__, [name: name, pid: pid], name: via_tuple)
  end

  def get_child_pid(key) do
    case key do
      :undefined -> :undefined
      pid when is_pid(pid) -> pid
      name -> GenServer.call(Caravan.Registry.via_tuple(name), :get_child_pid)
    end
  end

  @impl GenServer
  def init(args) do
    name = args[:name]
    mfa = Keyword.get(args, :mfa)
    in_pid = Keyword.get(args, :pid)
    callback = Keyword.get(args, :callback, fn _ -> :ok end)

    pid =
      if in_pid == nil do
        start_process(name, mfa, fn _ -> :ok end)
      else
        Process.link(in_pid)
        in_pid
      end

    {:ok, %{pid: pid, callback: callback}}
  end

  @impl GenServer
  def handle_cast(msg, %{pid: pid} = state) do
    GenServer.cast(pid, msg)
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:get_child_pid, _, %{pid: pid} = state) do
    {:reply, pid, state}
  end

  @impl GenServer
  def handle_call(msg, _from, %{pid: pid} = state) do
    reply = GenServer.call(pid, msg)
    {:reply, reply, state}
  end

  @impl GenServer
  def handle_info({:global_name_conflict, name}, state) do
    Logger.warn("Got global name conflict #{inspect(name)} [#{inspect(self())}]")
    {:stop, {:shutdown, :global_name_conflict}, state}
  end

  @impl GenServer
  def handle_info(msg, %{pid: pid} = state) do
    send(pid, msg)
    {:noreply, state}
  end

  defp start_process(name, {m, f, a} = mfa, callback) do
    case apply(m, f, a) do
      {:ok, pid} ->
        debug(fn -> "Started process #{inspect(name)} [#{inspect(pid)}] on #{Node.self()}" end)
        callback.({:started_process, {Node.self(), name, pid}})
        pid

      msg ->
        error_msg =
          "Caravan.Registry.ConflictHandler: Could not start child process. " <>
            "mfa: #{i(mfa)} error: #{i(msg)}"

        raise error_msg
    end
  end

  defp i(any), do: inspect(any)
  defdelegate debug(chardata_or_fun), to: Logger
end
