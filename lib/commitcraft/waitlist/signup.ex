defmodule CommitCraft.Waitlist.Signup do
  use Ecto.Schema
  import Ecto.Changeset

  schema "waitlist_signups" do
    field :email, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(signup, attrs) do
    signup
    |> cast(attrs, [:email])
    |> update_change(:email, &normalize/1)
    |> validate_required([:email])
    # Deliberadamente frouxo: a validação séria de um e-mail é mandar uma
    # mensagem para ele. Aqui só barramos o que claramente não é endereço.
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@,;]+\.[^\s@,;]+$/,
      message: "não parece um endereço de e-mail"
    )
    |> validate_length(:email, max: 160)
    |> unique_constraint(:email)
  end

  defp normalize(email) when is_binary(email), do: email |> String.trim() |> String.downcase()
  defp normalize(email), do: email
end
