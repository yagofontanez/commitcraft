defmodule CommitCraft.Accounts do
  @moduledoc """
  Quem está jogando.

  Toda conta nasce de um login com GitHub; não há cadastro por e-mail nem senha.
  """
  import Ecto.Query, warn: false

  alias CommitCraft.Accounts.User
  alias CommitCraft.Repo

  @doc "Busca um usuário pelo id interno. Devolve nil se não existir."
  def get_user(id), do: Repo.get(User, id)

  @doc "Busca pelo identificador numérico do GitHub."
  def get_user_by_github_id(github_id), do: Repo.get_by(User, github_id: github_id)

  @doc """
  Cria ou atualiza a conta a partir do que o GitHub devolveu.

  Entrar de novo não cria conta nova nem sobrescreve o histórico: o `github_id`
  é a chave, e só o que o GitHub tem de mais recente (nome, avatar, token) é
  atualizado. Assim alguém que trocou o `@login` continua sendo a mesma pessoa.
  """
  def upsert_from_github(%{} = profile, %{} = credentials) do
    attrs = %{
      github_id: profile.id,
      github_login: profile.login,
      name: profile.name,
      avatar_url: profile.avatar_url,
      github_token: credentials.token,
      github_scopes: credentials.scopes
    }

    %User{}
    |> User.github_changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [:github_login, :name, :avatar_url, :github_token, :github_scopes, :updated_at]},
      conflict_target: :github_id,
      returning: true
    )
  end

  @doc """
  Esquece o token guardado, mantendo a conta.

  Usado quando a pessoa sai: não há motivo para guardar uma credencial de acesso
  aos repositórios de alguém que não está com a sessão aberta.
  """
  def forget_github_token(%User{} = user) do
    user
    |> Ecto.Changeset.change(github_token: nil, github_scopes: [])
    |> Repo.update()
  end
end
