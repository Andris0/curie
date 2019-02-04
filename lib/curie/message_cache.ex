defmodule Curie.MessageCache do
  use GenServer

  import Nostrum.Struct.Snowflake, only: [is_snowflake: 1]

  alias Nostrum.Struct.{Channel, Guild, Message, User}
  alias Nostrum.Api

  @type get_response :: {:ok, [map()]} | {:error, :not_found}

  @self __MODULE__
  @ignore [Application.get_env(:curie, :owner)]
  @limit 500

  @spec start_link(term) :: GenServer.on_start()
  def start_link(_args) do
    GenServer.start_link(@self, [], name: @self)
  end

  @impl GenServer
  def init(_args) do
    {:ok, %{id: me}} = Api.get_current_user()
    {:ok, %{:ignore => [me | @ignore]}}
  end

  @impl GenServer
  def handle_cast({:add, %{guild_id: guild_id, channel_id: channel_id} = message}, state) do
    container_id = guild_id || channel_id

    state =
      if Map.has_key?(state, container_id),
        do: %{state | container_id => Deque.append(state[container_id], message)},
        else: Map.put(state, container_id, Deque.new(@limit) |> Deque.append(message))

    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:get, container_id, message_id}, _from, state) do
    if Map.has_key?(state, container_id) do
      state[container_id]
      |> Enum.filter(&(&1.id == message_id))
      |> case do
        [] -> {:reply, {:error, :not_found}, state}
        messages -> {:reply, {:ok, messages}, state}
      end
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_call({:get, message_id}, _from, state) do
    state
    |> Map.delete(:ignore)
    |> Enum.flat_map(fn {_container_id, container} ->
      Enum.filter(container, &(&1.id == message_id))
    end)
    |> case do
      [] -> {:reply, {:error, :not_found}, state}
      messages -> {:reply, {:ok, messages}, state}
    end
  end

  @impl GenServer
  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  @impl GenServer
  def handle_call(:ignore, _from, %{ignore: ignore_list} = state) do
    {:reply, ignore_list, state}
  end

  @spec add(Message.t()) :: no_return()
  defp add(message) do
    GenServer.cast(@self, {:add, message})
  end

  @spec ignore?(%{author: %{id: User.id()}}) :: boolean()
  def ignore?(%{author: %{id: user_id}}) do
    user_id in GenServer.call(@self, :ignore)
  end

  @spec ignore?(%{user: %{id: User.id()}}) :: boolean()
  def ignore?(%{user: %{id: user_id}}) do
    user_id in GenServer.call(@self, :ignore)
  end

  @spec get(%{guild_id: Guild.id(), id: Message.id()}) :: get_response()
  def get(%{guild_id: guild_id, id: message_id}) when guild_id != nil do
    GenServer.call(@self, {:get, guild_id, message_id})
  end

  @spec get(%{channel_id: Channel.id(), id: Message.id()}) :: get_response()
  def get(%{channel_id: channel_id, id: message_id}) do
    GenServer.call(@self, {:get, channel_id, message_id})
  end

  @spec get(Message.id()) :: get_response()
  def get(message_id) when is_snowflake(message_id) do
    GenServer.call(@self, {:get, message_id})
  end

  @spec handler(map()) :: no_return()
  def handler(message) do
    unless ignore?(message) do
      add(message)
    end
  end
end
