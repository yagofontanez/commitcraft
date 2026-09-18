defmodule CommitCraftWeb.PublicProjectControllerTest do
  use CommitCraftWeb.ConnCase

  import CommitCraft.AccountsFixtures
  import CommitCraft.ProjectsFixtures

  alias CommitCraft.Projects

  defp commit(sha, titulo) do
    %{
      kind: "commit",
      title: titulo,
      xp: 5,
      occurred_at: DateTime.utc_now(:second),
      external_id: sha,
      meta: %{}
    }
  end

  defp publicar(user, project) do
    {:ok, project} = Projects.set_visibility(user, project.slug, true)
    project
  end

  describe "projeto fechado" do
    test "responde 404, mesmo com o endereço certo", %{conn: conn} do
      user = user_fixture(login: "yagofontanez")
      project_fixture(user, %{name: "Privado"})

      assert conn |> get(~p"/p/yagofontanez/privado") |> html_response(404)
    end

    test "nada na resposta revela que o projeto existe", %{conn: conn} do
      user = user_fixture(login: "yagofontanez")
      project_fixture(user, %{name: "Privado"})

      fechado = conn |> get(~p"/p/yagofontanez/privado") |> html_response(404)
      inexistente = conn |> get(~p"/p/yagofontanez/nunca-existiu") |> html_response(404)

      # As duas respostas têm que ser indistinguíveis, tirando o token de CSRF
      # que muda a cada requisição por definição.
      limpar = &Regex.replace(~r/content="[^"]*csrf[^"]*"|content="[A-Za-z0-9_\-]{40,}"/, &1, "")

      assert limpar.(fechado) == limpar.(inexistente)
      refute fechado =~ "Privado"
    end
  end

  describe "projeto aberto" do
    test "qualquer um vê, sem estar logado", %{conn: conn} do
      user = user_fixture(login: "yagofontanez", name: "Yago")
      project = project_fixture(user, %{name: "Minha Loja", xp: 6940})
      publicar(user, project)

      html = conn |> get(~p"/p/yagofontanez/minha-loja") |> html_response(200)

      assert html =~ "Minha Loja"
      assert html =~ "LV 07"
      assert html =~ "yagofontanez"
    end

    test "explica o que é o CommitCraft para quem caiu de paraquedas", %{conn: conn} do
      user = user_fixture(login: "yagofontanez")
      publicar(user, project_fixture(user, %{name: "Meu"}))

      html = conn |> get(~p"/p/yagofontanez/meu") |> html_response(200)

      assert html =~ "transforma o seu repositório num jogo"
    end

    test "o card de compartilhamento fala do projeto, não do produto", %{conn: conn} do
      user = user_fixture(login: "yagofontanez")
      project = project_fixture(user, %{name: "Minha Loja", xp: 6940})
      publicar(user, project)

      html = conn |> get(~p"/p/yagofontanez/minha-loja") |> html_response(200)

      assert html =~ ~s(property="og:title")
      assert html =~ "Minha Loja"
      assert html =~ "Nível 7"
    end
  end

  describe "repositório privado" do
    setup %{conn: conn} do
      user = user_fixture(login: "yagofontanez")
      project = project_fixture(user, %{name: "Meu"})

      {:ok, project} =
        Projects.connect_repo(user, project.slug, %{
          id: 7,
          full_name: "yagofontanez/segredo",
          private: true
        })

      {:ok, _} = Projects.record_events(project, [commit("a", "fix: corrige o cálculo secreto")])

      %{conn: conn, project: publicar(user, project)}
    end

    test "nunca mostra mensagem de commit nem nome do repositório", %{conn: conn} do
      html = conn |> get(~p"/p/yagofontanez/meu") |> html_response(200)

      # Tornar o projeto público não pode arrastar junto uma coisa que a pessoa
      # nunca pensou em publicar.
      refute html =~ "fix: corrige o cálculo secreto"
      refute html =~ "yagofontanez/segredo"
    end

    test "o caminho continua lá, só sem as palavras", %{conn: conn} do
      html = conn |> get(~p"/p/yagofontanez/meu") |> html_response(200)

      assert html =~ "O caminho"
      assert html =~ "+5"
      assert html =~ "porque o repositório é privado"
    end
  end

  describe "repositório público" do
    test "mostra as mensagens, que já eram públicas mesmo", %{conn: conn} do
      user = user_fixture(login: "yagofontanez")
      project = project_fixture(user, %{name: "Meu"})

      {:ok, project} =
        Projects.connect_repo(user, project.slug, %{
          id: 7,
          full_name: "yagofontanez/aberto",
          private: false
        })

      {:ok, _} = Projects.record_events(project, [commit("a", "feat: uma coisa boa")])
      publicar(user, project)

      html = conn |> get(~p"/p/yagofontanez/meu") |> html_response(200)

      assert html =~ "feat: uma coisa boa"
      assert html =~ "yagofontanez/aberto"
    end
  end
end
