defmodule Nostrum.Shard.Supervisor do
  @moduledoc false

  use Supervisor

  alias Nostrum.Cache.Mapping.GuildShard
  alias Nostrum.Error.CacheError
  alias Nostrum.Shard
  alias Nostrum.Shard.Session
  alias Nostrum.Shard.Stage.{Cache, Producer}
  alias Nostrum.Util

  require Logger

  def start_link(_args) do
    {url, gateway_shard_count} = Util.gateway()

    num_shards =
      case Application.get_env(:nostrum, :num_shards, :auto) do
        :auto ->
          gateway_shard_count

        ^gateway_shard_count ->
          gateway_shard_count

        shard_count when is_integer(shard_count) and shard_count > 0 ->
          Logger.warn(
            "Configured shard count (#{shard_count}) " <>
              "differs from Discord Gateway's recommended shard count (#{gateway_shard_count}). " <>
              "Consider using `num_shards: :auto` option in your Nostrum config."
          )

          shard_count

        value ->
          raise ~s("#{value}" is not a valid shard count)
      end

    cluster_id = Application.get_env(:nostrum, :cluster_id, 0)
    num_clusters = Application.get_env(:nostrum, :num_clusters, 1)

    Supervisor.start_link(
      __MODULE__,
      [url, num_shards, cluster_id, num_clusters],
      name: ShardSupervisor
    )
  end

  def update_status(status, game, stream, type) do
    ShardSupervisor
    |> Supervisor.which_children()
    |> Enum.filter(fn {_id, _pid, _type, [modules]} -> modules == Nostrum.Shard end)
    |> Enum.map(fn {_id, pid, _type, _modules} -> Supervisor.which_children(pid) end)
    |> List.flatten()
    |> Enum.map(fn {_id, pid, _type, _modules} ->
      Session.update_status(pid, status, game, stream, type)
    end)
  end

  def update_voice_state(guild_id, channel_id, self_mute, self_deaf) do
    case GuildShard.get_shard(guild_id) do
      {:ok, shard_id} ->
        ShardSupervisor
        |> Supervisor.which_children()
        |> Enum.filter(fn {_id, _pid, _type, [modules]} -> modules == Nostrum.Shard end)
        |> Enum.filter(fn {id, _pid, _type, _modules} -> id == shard_id end)
        |> Enum.map(fn {_id, pid, _type, _modules} -> Supervisor.which_children(pid) end)
        |> List.flatten()
        |> Enum.filter(fn {_id, _pid, _type, [modules]} -> modules == Nostrum.Shard.Session end)
        |> List.first()
        |> elem(1)
        |> Session.update_voice_state(guild_id, channel_id, self_mute, self_deaf)

      {:error, :id_not_found} ->
        raise CacheError, key: guild_id, cache_name: GuildShardMapping
    end
  end

  @doc false
  def init([url, num_shards, cluster_id, num_clusters]) do
    children =
      [Producer, Cache] ++
        for i <- :lists.seq(cluster_id, num_shards - 1, num_clusters), do: create_worker(url, i)

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 3, max_seconds: 60)
  end

  @doc false
  def create_worker(gateway, shard_num) do
    Supervisor.child_spec(
      {Shard, [gateway, shard_num]},
      id: shard_num
    )
  end
end
