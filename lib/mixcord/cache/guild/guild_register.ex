defmodule Mixcord.Cache.Guild.GuildRegister do
  @moduledoc false

  alias Mixcord.Cache.Guild.GuildServer
  alias Mixcord.Struct
  alias Supervisor.Spec

  def lookup(id) do
    case Registry.lookup(GuildRegistry, id) do
      [{pid, _}] ->
        {:ok, pid}
      [] ->
        {:error, :id_not_found}
    end
  end

  def lookup!(id) do
    case Registry.lookup(GuildRegistry, id) do
      [{pid, _}] ->
        pid
      [] ->
        raise(Mixcord.Error.CacheError, "No entry in guild registry for id #{id}")
    end
  end

  # TODO: Refactor this nasty code and potentially move
  @doc false
  def create_guild_process!(id, guild) do
    case Supervisor.start_child(GuildSupervisor, create_worker_spec(id, guild)) do
      {:error, {:already_started, pid}} ->
        handle_guild_unavailability!(pid, guild)
      {:error, reason} ->
        raise(Mixcord.Error.CacheError,
          "Could not start a new guild process with id #{id}, reason: #{inspect reason}")
      {:ok, _pid} ->
        Struct.Guild.to_struct(guild)
    end
  end

  def create_worker_spec(id, guild) do
    Spec.worker(GuildServer, [id, guild], id: id)
  end

  @doc """
  When attempting to start a guild, if the guild is already created, check to see
  if it's unavailable, and if it is replace it with the new guild payload.
  """
  defp handle_guild_unavailability!(pid, guild) do
    if GuildServer.unavailable?(pid) do
      GuildServer.make_guild_available(pid, guild)
    else
      raise(Mixcord.Error.CacheError, "Attempted to create a child with an id that already exists")
    end
  end

end