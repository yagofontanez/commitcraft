// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/commitcraft"
import topbar from "../vendor/topbar"

// O caminho do projeto rola na horizontal e o que importa está no fim dele.
//
// Rolar até o fim sozinho só é gentil enquanto a pessoa não foi olhar o
// passado: puxar a tela de volta no meio de uma leitura é pior do que não
// rolar. Por isso o salto só acontece se ela já estava por perto do fim.
const Jornada = {
  mounted() {
    this.aoFim("instant")
  },

  updated() {
    if (this.pertoDoFim) this.aoFim("smooth")
  },

  beforeUpdate() {
    const restante = this.el.scrollWidth - this.el.scrollLeft - this.el.clientWidth
    this.pertoDoFim = restante < 240
  },

  aoFim(behavior) {
    this.el.scrollTo({left: this.el.scrollWidth, behavior})
  }
}

// ─────────────────────────────── som ───────────────────────────────
//
// Os bipes são sintetizados no WebAudio, não tocados de arquivo: pela mesma
// razão que os sprites são grades de texto — nenhum binário no repositório, e
// dá para afinar uma nota mexendo num número.
//
// Três regras que não são capricho:
//   1. O navegador proíbe tocar som antes de a pessoa interagir com a página.
//      Por isso o contexto só nasce no primeiro clique ou tecla.
//   2. Quem desligou fica desligado: a escolha vai para o localStorage.
//   3. Quem pediu menos movimento no sistema provavelmente também não quer
//      barulho — começa mudo.
const Som = {
  contexto: null,
  chave: "commitcraft:som",

  ligado() {
    const guardado = localStorage.getItem(this.chave)

    if (guardado !== null) return guardado === "1"

    return !window.matchMedia("(prefers-reduced-motion: reduce)").matches
  },

  alternar() {
    const novo = !this.ligado()
    localStorage.setItem(this.chave, novo ? "1" : "0")
    if (novo) this.tocar([[660, 0.07]])
    return novo
  },

  despertar() {
    if (!this.contexto) {
      const Contexto = window.AudioContext || window.webkitAudioContext
      if (Contexto) this.contexto = new Contexto()
    }

    if (this.contexto && this.contexto.state === "suspended") this.contexto.resume()
  },

  // Cada nota é [frequência em hertz, duração em segundos]. A onda quadrada é
  // o que dá o timbre de console de 8 bits; senoide soaria como despertador.
  tocar(notas) {
    if (!this.ligado() || !this.contexto) return

    let quando = this.contexto.currentTime

    for (const [hz, duracao] of notas) {
      const oscilador = this.contexto.createOscillator()
      const volume = this.contexto.createGain()

      oscilador.type = "square"
      oscilador.frequency.setValueAtTime(hz, quando)

      // Sem esse decaimento cada nota termina num estalo.
      volume.gain.setValueAtTime(0.06, quando)
      volume.gain.exponentialRampToValueAtTime(0.0001, quando + duracao)

      oscilador.connect(volume).connect(this.contexto.destination)
      oscilador.start(quando)
      oscilador.stop(quando + duracao)

      quando += duracao
    }
  },

  xp() {
    this.tocar([[880, 0.05], [1175, 0.06]])
  },

  levelUp() {
    // Arpejo subindo: a frase que todo console toca quando algo dá certo.
    this.tocar([[523, 0.09], [659, 0.09], [784, 0.09], [1047, 0.22]])
  },

  conquista() {
    this.tocar([[784, 0.08], [1047, 0.08], [1319, 0.18]])
  }
}

// O contexto de áudio só pode nascer depois de um gesto da pessoa.
for (const gesto of ["pointerdown", "keydown"]) {
  window.addEventListener(gesto, () => Som.despertar(), {once: true})
}

// O LiveView avisa pelo `push_event`, que o Phoenix entrega como um evento de
// janela com prefixo `phx:`.
window.addEventListener("phx:som", (evento) => {
  const toque = {xp: "xp", level_up: "levelUp", conquista: "conquista"}[evento.detail.tipo]

  if (toque) Som[toque]()
})

// Delegação em vez de listener no botão: o cabeçalho é redesenhado a cada
// navegação do LiveView, e um listener preso ao elemento morreria junto.
const pintarBotoes = () => {
  const ligado = Som.ligado()

  for (const botao of document.querySelectorAll("[data-som]")) {
    botao.setAttribute("aria-pressed", String(ligado))
    botao.dataset.ligado = ligado ? "1" : "0"
    botao.title = ligado ? "Desligar o som" : "Ligar o som"
  }
}

document.addEventListener("click", (evento) => {
  if (!evento.target.closest("[data-som]")) return

  Som.despertar()
  Som.alternar()
  pintarBotoes()
})

document.addEventListener("DOMContentLoaded", pintarBotoes)
window.addEventListener("phx:page-loading-stop", pintarBotoes)

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, Jornada},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}


// Máquina de escrever da caixa de diálogo do herói.
//
// O texto já vem renderizado do servidor: sem JS, ou com "reduzir movimento"
// ligado, a frase simplesmente aparece inteira. O script só a esconde para
// reescrevê-la letra a letra — e espera a caixa entrar na tela, senão a
// digitação acaba enquanto a pessoa ainda está lendo o título.
const typewrite = (el) => {
  const full = el.textContent
  let i = 0

  el.textContent = ""
  el.classList.add("typing-caret")

  const tick = () => {
    el.textContent = full.slice(0, ++i)

    if (i < full.length) {
      // Uma pausa maior depois do ponto final dá ritmo de fala.
      setTimeout(tick, full[i - 1] === "." ? 260 : 22)
    } else {
      el.classList.remove("typing-caret")
    }
  }

  setTimeout(tick, 350)
}

document.addEventListener("DOMContentLoaded", () => {
  const targets = document.querySelectorAll("[data-typewriter]")
  if (!targets.length) return

  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

  // Esconde já, para o texto não piscar inteiro antes de a caixa aparecer.
  targets.forEach(el => { el.dataset.full = el.textContent; el.textContent = "" })

  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (!entry.isIntersecting) return
      observer.unobserve(entry.target)
      entry.target.textContent = entry.target.dataset.full
      typewrite(entry.target)
    })
  }, {threshold: 0.6})

  targets.forEach(el => observer.observe(el))
})

// As mensagens do sistema aparecem em páginas comuns, sem LiveView, então não
// há quem as recolha. Somem no clique, e sozinhas depois de alguns segundos.
document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll("[data-flash]").forEach((flash) => {
    const dismiss = () => flash.remove()

    flash.addEventListener("click", dismiss)
    setTimeout(dismiss, 6000)
  })
})
