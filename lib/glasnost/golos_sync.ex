defmodule Golos.Sync do
  use GenServer
  alias Glasnost.Repo

  def start_link(args \\ %{}) do
    GenServer.start_link(__MODULE__, args, [])
  end

  def init(args) do
    import Ecto.Query
    Repo.delete_all(from c in Glasnost.Comment)
    blog_author = RuntimeConfig.blog_author
    state = %{current_cursor: "", blog_author: blog_author}
    Process.send_after(self(), :tick, 1_000)
    {:ok, state}
  end

  def handle_info(:tick, state) do
     utc_now_str = NaiveDateTime.utc_now |> NaiveDateTime.to_iso8601 |> String.replace(~r/\..+/, "")
     {:ok, posts} = Golos.get_discussions_by_author_before_date(state.blog_author, state.current_cursor, utc_now_str, 100)
     for post <- posts do
       post = update_in(post["json_metadata"], &Poison.Parser.parse!(&1))
       result =
         case Repo.get(Glasnost.Comment, post["id"]) do
           nil  -> %Glasnost.Comment{}
           comment -> comment
         end
         |> Glasnost.Comment.changeset(post)
         |> Repo.insert_or_update

       case result do
         {:ok, struct}       -> :ok
         {:error, changeset} -> :error
       end
     end
     state = if length(posts) == 100 do
       Process.send_after(self(), :tick, 100, [])
       next_permlink = posts |> List.last() |> Map.get("permlink")
       put_in(state.current_cursor, next_permlink)
     else
       Process.send_after(self(), :tick, :timer.minutes(60), [])
       put_in(state.current_cursor, "")
     end
     {:noreply, state}
  end



end