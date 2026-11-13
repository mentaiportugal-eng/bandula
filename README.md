# Bandula — Godot 4.7 (Compatibility / WebGL 2)

Sandbox de mundo aberto em **Luanda, Angola**, portado do jogo web Three.js para Godot 4,
com o renderer **Compatibility** (exporta limpo para o browser) e estética toon
Slime Rancher / Pixar.

## Comandos

```bash
G=~/.local/bin/godot4
$G --headless --path godot/bandula --import                                  # 1.ª vez (importa o avatar .glb)
$G --headless --path godot/bandula --script res://tools/build_game.gd        # gera todas as cenas (+ mapa, ~25 s)
$G --headless --path godot/bandula --script res://tools/build_game.gd -- --sem-mundo   # só cenas (2 s)
$G --headless --fixed-fps 60 --path godot/bandula --script res://tests/smoke_test.gd      # teste geral (26)
$G --headless --fixed-fps 60 --path godot/bandula --script res://tests/interiors_test.gd  # interiores (21)
$G --headless --fixed-fps 60 --path godot/bandula --script res://tests/buildings_test.gd  # prédios e mobília (27)
$G --headless --fixed-fps 60 --path godot/bandula --script res://tests/all_buildings_test.gd  # todos os edifícios (18)
godot/bandula/tools/net_test.sh                                              # multijogador: servidor + 2 clientes (10)
godot/bandula/tools/run_server.sh [porta]                                    # servidor online (porta 9080)
$G --headless --path godot/bandula --export-release "Web" build/web/index.html        # exporta para a web
$G --path godot/bandula -e                                                   # abrir no editor
```

A exportação Web não usa threads: corre em qualquer alojamento estático (sem cabeçalhos
COOP/COEP). Ex.: `python3 -m http.server` na raiz do repositório →
`http://localhost:8000/godot/bandula/build/web/`.

## Estrutura

```
res://
├── project.godot            renderer gl_compatibility · autoloads GameManager, Interiors, Network · física GodotPhysics3D
├── export_presets.cfg       preset "Web" (sem threads)
├── shaders/
│   ├── toon_stylized.gdshader   cel-shading 2 bandas, sombras lilases, rim de Fresnel, brilho toon
│   └── water_stylized.gdshader  mar turquesa com ondulação, Fresnel e brilhos
├── scripts/
│   ├── game_manager.gd      autoload: economia, lotes, construções, procurado 1–5★, DETIDO/ESCAPOU
│   ├── player.gd            CharacterBody3D 3.ª pessoa, salto, squash-and-stretch, E/F
│   ├── avatar_slot.gd       slot .glb + AnimationTree (Idle/Walk/Run/Jump/Sit)
│   ├── camera_rig.gd        câmara orbital GTA (SpringArm3D), perfis a pé / veículo
│   ├── vehicle.gd           VehicleBody3D arcade, drift, auto-desvirar, IA, sirene
│   ├── traffic_manager.gd   trânsito civil + viaturas da Guarda conforme as estrelas
│   ├── plot.gd              lote comprável (Area3D) + prédio do kit
│   ├── hud.gd · wanted_stars.gd · minimap_overlay.gd · main.gd
│   └── world/ geo.gd · kit_library.gd · world_builder.gd   (mapa de Luanda)
├── scenes/
│   ├── main.tscn · player.tscn · camera_rig.tscn · hud.tscn
│   ├── vehicles/ buggy.tscn · candongueiro.tscn · guarda.tscn
│   ├── world/luanda.tscn (+ malhas .res)     kit/*.scn (peças do Luanda City Kit)
├── materials/ kit.tres · vidro.tres · verniz.tres     (ShaderMaterial toon)
├── assets/ kit/*.glb (do jogo web) · avatar/avatar_bandula.glb (esqueleto + clipes)
├── ui/bandula_theme.tres
├── tools/build_game.gd      constrói tudo (cenas reprodutíveis)
└── tests/smoke_test.gd
```

## Árvores de nós

**main.tscn**
```
Main (Node3D) [main.gd]
├── WorldEnvironment            (ver «Ambiente»)
├── SolEquatorial (DirectionalLight3D)   cor #ffd9a3 · energia 1.35 · sombras 2 splits · blur 1.6 · 140 m
├── Luanda (instância world/luanda.tscn)
├── Player (instância player.tscn)
├── CameraRig (instância camera_rig.tscn)
├── Traffic (Node3D) [traffic_manager.gd]   civilian_scenes=[buggy, candongueiro] · police_scene=guarda
└── HUD (instância hud.tscn)
```

**player.tscn** — camadas: jogador (2); máscara: mundo (1) + veículos (3)
```
Player (CharacterBody3D) [player.gd]   floor_snap 0.4 · floor_max_angle 50°
├── CollisionShape3D   CapsuleShape3D r 0.35 · h 1.8 · y 0.9
└── Visual (Node3D)            ← escala do squash-and-stretch; vai para o banco no carro
    └── AvatarSlot (Node3D) [avatar_slot.gd]   avatar_scene = assets/avatar/avatar_bandula.glb
        ├── (modelo .glb instanciado)
        └── AnimationTree (criada em código: StateMachine Locomotion/Jump/Sit)
```

**camera_rig.tscn**
```
CameraRig (Node3D) [camera_rig.gd]   top_level
└── Yaw (Node3D) → Pitch (Node3D)
    └── SpringArm3D   comprimento 4.6 · margem 0.3 · SphereShape3D r 0.25 · máscara: mundo
        └── Camera3D (current, FOV 70, far 900)
            └── InteractRay (RayCast3D)   alvo (0,0,−30) · áreas+corpos · máscara mundo + interativos
```

**vehicles/buggy.tscn** (candongueiro e guarda iguais, outras medidas) — camada veículos (3)
```
BuggyUrbano (VehicleBody3D) [vehicle.gd]   massa 520 · centro de massa (0, 0.35, 0)
├── CollisionShape3D   BoxShape3D (largura·0.92, altura·0.8, comprimento·0.95)
├── Carrocaria (instância kit/carro_buggy.scn)
├── RodaFE / RodaFD (VehicleWheel3D, use_as_steering)   ┐ raio = wheel_r · repouso 0.25
├── RodaTE / RodaTD (VehicleWheel3D, use_as_traction)   ┘ rigidez 45 · amortec. 0.88/0.98 · roll 0.12
│   └── Malha (instância kit/roda.scn)
├── Seat (Marker3D)          banco do condutor — à ESQUERDA (+X, condução à direita)
├── ExitPoint (Marker3D)     saída pela esquerda
├── CameraTarget (Marker3D)
└── Sirene (Node3D) — só guarda.tscn
    ├── Vermelha (OmniLight3D) └ Lampada (MeshInstance3D emissiva)
    └── Azul (OmniLight3D)     └ Lampada
```

**hud.tscn** — nós com `%` têm *unique name*
```
HUD (CanvasLayer, layer 10) [hud.gd]
└── Root (Control, ecrã inteiro, tema ui/bandula_theme.tres)
    ├── TopLeft (PanelContainer) → VBox: %Empire · %Day · HBox[Aprovação, %Approval (ProgressBar)]
    ├── TopRight (VBox): %Treasury (Label) · %Stars [wanted_stars.gd] · %WantedInfo
    ├── MinimapFrame (PanelContainer) → Stack (Control, clip)
    │   ├── MinimapContainer (SubViewportContainer, stretch)
    │   │   └── %MinimapViewport (SubViewport 216²) → %MinimapCam (Camera3D ortográfica, size 320)
    │   ├── %MinimapOverlay (Control) [minimap_overlay.gd]
    │   └── N (Label)
    ├── %Speedo (PanelContainer) → VBox: %SpeedValue · %VehicleName
    ├── %Prompt (Label) · %Toasts (VBox) · %Banner (Label «DETIDO»/«ESCAPOU»)
    └── %Menu (PanelContainer) → VBox: título · %Tabs (TabContainer)
        ├── Propriedades: %PlotList (ItemList) · %PlotInfo · HBox[%BuildCasa, %BuildComercio]
        ├── Leis: %TaxLabel · %TaxSlider (0–40 %) · explicação
        └── Relatório: %Report
```

**world/luanda.tscn** (gerada por `world_builder.gd`)
```
Luanda (Node3D)
├── Terreno (MeshInstance3D, toon, cores por vértice) · ColisaoTerreno (StaticBody3D trimesh)
├── Mar (water_stylized) · Estradas · Cidade · ColisaoCidade (asfalto + quadras)
├── BarreiraCosta (StaticBody3D: beira-mar + limites)
├── Marcos: FortalezaShopping (centro comercial, interior gerado) · EsquadraIngombota · TorreBaixa_a/b/c
├── Coqueiros · Imbondeiros · Quiosques · GuardaSois   (peças do kit, cada uma com colisão)
├── Lotes: 128 lotes da cidade + 6 na Ilha (Area3D [plot.gd], camada interativos)
└── Spawns: Jogador · CarroBuggy · CarroCandongueiro · GuardaBase · PortaEsquadra
```
Se existir `../../assets/luanda/layout.json` (editor do mapa em `godot/luanda_map`),
coqueiros, quiosques e guarda-sóis seguem essas posições.

## Ambiente (WorldEnvironment — Compatibility)

| Grupo | Definição |
|---|---|
| Fundo | `BG_SKY` · ProceduralSkyMaterial: topo `#1f9cff`, horizonte `#ffe6cc`, curva 0.12, chão `#c9ab84` |
| Luz ambiente | fonte céu · cor `#b3a6ff` (lilás) · contribuição do céu 0.55 · energia 0.75 |
| Tonemap | **ACES** · exposição 1.0 · white 6.0 |
| Glow / bloom | ativo · intensidade 0.5 · força 0.9 · bloom 0.04 · limiar HDR 1.1 · blend Softlight |
| Névoa | ativa · modo *depth* 160 → 560 m · cor `#ffe7d4` · densidade 0.0012 · sky affect 0.25 |
| Ajustes | saturação 1.1 · contraste 1.04 |
| Sol | DirectionalLight3D `#ffd9a3` · 1.35 · sombras PSSM 2 splits, 140 m, blur 1.6 · direção (38, 120, 30) |

SSAO/GTAO e SDFGI não existem no renderer Compatibility; o contraste de oclusão vem do
cel-shading e do preenchimento lilás do shader (`shadow_tint`, `shadow_fill`).

## Toon shader — parâmetros principais

`shadow_edge`/`mid_edge`/`band_softness` (2 bandas), `mid_tone`, `sun_warmth`,
`shadow_tint` + `shadow_fill` (sombra lilás só da luz direcional), `rim_color`/`rim_strength`/
`rim_power` (Fresnel), `gloss`/`gloss_size` (brilho recortado: vidro 0.65, verniz 0.5).

## Controlos

WASD andar/conduzir · rato câmara (clique captura, Esc liberta) · Shift correr · Espaço
saltar / travão de mão · **E** ver/comprar lote · **F** entrar/sair/roubar veículo ·
**B** Menu do Império · **T** conversar (online; Enter envia, Esc fecha).

## Camadas de física

1 mundo · 2 jogador · 3 veículos · 4 interativos (lotes).

## Personagens (Universal Base Characters — Quaternius, CC0)

8 personagens em `scenes/characters/*.scn`: Governante (jogador), Kianda, Zeca, Nzinga, Mateus,
Rosa, Sr. António e Luena. São as aparências do multijogador e os clientes/atendentes dos interiores.

```bash
python3 -I godot/bandula/tools/import_ubc.py "Universal Base Characters[Standard].zip"   # copia os glTF
$G --headless --path godot/bandula --import
$G --headless --path godot/bandula --script res://tools/build_characters.gd             # gera as personagens (~6 s)
```

- **Animações**: o pack não traz animações. `build_characters.gd` faz o *retarget* das animações
  do avatar antigo (`assets/avatar/avatar_bandula.glb`: Idle, Walk, Run, Jump, Sitting, Clapping…)
  para o esqueleto novo (estilo UE). A conversão é feita em espaço do modelo e corrige a diferença
  pose-A → pose-T pela direção dos ossos → `assets/characters/anims_f.res` / `anims_m.res`.
- **Roupa**: o pack traz corpos-base em roupa interior. Cada vértice recebe máscaras pelos pesos
  dos ossos (tronco, braço, antebraço, anca+coxa, canela, pé → `COLOR`/`UV2`), e o shader
  `shaders/toon_character.gdshader` pinta camisa (sem manga / curta / comprida), calças, calções ou
  saia, sapatos e uma faixa de pano na cintura, com o tom de pele de cada personagem.
- **Cabelo**: penteados do pack (rapado, risca, tranças/coque, comprido, barba) presos ao osso
  `Head` com um BoneAttachment3D. Os cabelos cinzentos do pack são tingidos no material.
- Para criar uma personagem nova, acrescente uma entrada a `LOOKS` em `build_characters.gd` (pele,
  cabelo, cores da roupa, mangas, pernas) e a `Network.LOOKS`/`LOOK_NAMES`.

`AvatarSlot` continua a aceitar qualquer `.glb` com esqueleto e clipes (ajuste `anim_names`).
As personagens geradas trazem as metas `toon_ready` (mantém os materiais) e `height` (altura real).

## Interiores e serviços (BuildingInteriorSystem)

```
scripts/interiors/
├── interior_manager.gd        autoload "Interiors": transições (fade / seamless), criar e libertar interiores
├── building_portal.gd         porta (Area3D) — E entra; também a porta de saída de cada sala (is_exit)
├── interactable_furniture.gd  cadeira/banco (Sit) e balcão (abre a loja); reserva de lugares
├── interior.gd                raiz da sala: letreiro, atendente, clientes sentados e a chegar
├── patron_npc.gd              cliente NPC: entra, senta-se, sai · atendente atrás do balcão
├── interior_kit.gd            geometria chanfrada / torneada com cor por vértice
└── interior_builder.gd        gera scenes/interiors/{restaurante,cantina,loja}.tscn
```

- **Onde:** cada comércio dos NPCs na Baixa e nos bairros tem porta (33 no mapa padrão),
  virada para a rua: restaurante, cantina ou mini-mercado, com nome próprio. Na Ilha de
  Luanda, «Restaurante Kitanda da Ilha» e «Esplanada Mar Azul».
- **Fade (Opção B):** ecrã preto 0,3 s; a sala é instanciada em `Interiors.FADE_ORIGIN`
  (sob o mapa) e o jogador aparece à entrada, de costas para a porta.
- **Seamless (Opção A, Ilha):** a sala aparece no lugar do edifício, cujo casco fica
  escondido e sem colisão; a câmara desliza para dentro sem cortes.
- **Sentar:** E junto a uma cadeira → o avatar vai para o `SitPoint`, clipe *Sitting*, câmara
  `seated` por cima do ombro; W ou Espaço levanta. Lugares reservados (jogador e NPCs).
- **Balcão:** E abre a loja no HUD; as compras saem do tesouro (`GameManager.purchase`):
  comida dá energia, gestos públicos dão aprovação, sociedades dão Kz por dia.
- **Energia:** desce com o tempo e ao correr; abaixo de 8 % não se corre.
- **NPCs:** ao entrar, alguns clientes já estão sentados e o atendente está ao balcão;
  outros vão chegando pela porta, sentam-se 15–45 s e saem.
- **Guarda:** ser detido (na rua ou lá dentro) leva o jogador para a **Esquadra da Ingombota**. A Guarda não entra nos
  estabelecimentos — esconder-se num deles deixa a contagem «ESCAPANDO» correr.
- **Demo na web:** `index.html?interior=restaurante|cantina|loja|ilha` entra logo no
  primeiro estabelecimento desse tipo.

Árvore de uma sala (ex.: `scenes/interiors/restaurante.tscn`):
```
Restaurante (Node3D) [interior.gd]
├── Sala (MeshInstance3D)  · Colisao (StaticBody3D)  · Luz (OmniLight3D ×n)
├── Menu / Letreiro (Label3D)
├── Entrada (Marker3D)
├── Saida (Area3D) [building_portal.gd, is_exit]
├── Balcao (Area3D) [interactable_furniture.gd, counter] └ Atendente (Marker3D)
├── Assentos (Node3D) └ Cadeira_NN (Area3D) [interactable_furniture.gd, seat]
│                        ├ Malha · Colisao · SitPoint · Approach
└── Clientes (Node3D)   ← NPCs criados em jogo
```

## Prédios com tamanhos, divisões e mobília

- **Tamanhos:** casas e comércios em pequeno / médio / grande (`GameManager.BUILD`), com
  exteriores diferentes (`casa_p/m/g`, `comercio_p/m/g`; o comércio grande é uma torre de vidro).
  No Menu do Império (B) escolhe-se o tamanho e, para comércios, o negócio (restaurante,
  cantina, mini-mercado, boutique, café).
- **Divisões** (`interiors/interior_generator.gd`): casa pequena — sala e cozinha, quarto,
  casa de banho; grande — sala, cozinha, 2 quartos, casa de banho. Comércios — salão +
  armazém / cozinha / escritório. Paredes com portas, piso e luz por divisão, placa com o nome.
- **Mobilar (M, `interiors/decorator.gd`):** dentro dos seus prédios, peça-fantasma verde/
  vermelha na mira (grelha 25 cm; não atravessa paredes nem móveis); Tab/1–9 escolher,
  R rodar, E/clique colocar (paga), X retirar (devolve metade). 12 peças
  (`interiors/furniture_catalog.gd`): cadeira, banco, sofá, mesas, balcão, estante,
  frigorífico, cama, planta, tapete, candeeiro. A mobília fica no lote e reaparece ao voltar.
- **Negócio do jogador:** sem balcão está fechado; com balcão tem atendente e os clientes
  NPC sentam-se nas cadeiras que pôs. Cadeiras, mesas, prateleiras e decoração aumentam o
  rendimento diário (balcão do próprio negócio → «ver as contas»). Casas: cama, sofá e
  decoração dão conforto (aprovação).
- **Fortaleza Shopping** (no morro): 6 lojas com montra e atendente — Muamba Express,
  Café Ginga, Moda Luanda (boutique), Kianda Tech (eletrónica), Hiper Kianda, Grelhados do
  Mussulo — e praça da alimentação com 18 lugares. Demo web: `?interior=shopping`.
- **Esquadra da Ingombota:** base da Guarda de Bandula (viaturas estacionadas) e destino de
  quem é detido.

## Todos os edifícios têm interior

Qualquer edifício do mapa tem porta (102 no mapa padrão) e interior visitável:

| Edifício | Interior |
|---|---|
| Comércios dos NPCs (Baixa e bairros) | restaurante, cantina ou mini-mercado (salas fixas) |
| Casas dos NPCs | divisões mobiladas automaticamente + moradores («Casa da família …») |
| Prédios do jogador | divisões por tamanho, mobília à escolha (M) |
| Torres da Baixa | escritórios com receção (consultoria, publicidade) |
| Esquadra da Ingombota | receção, gabinete e celas; ao balcão pode **entregar-se** (multa a metade) |
| Fortaleza Shopping | 6 lojas + praça da alimentação |
| Restaurantes da Ilha | interior seamless no lugar do edifício |
| Quiosques da Ilha | pequeno café (café de Angola, pastel de nata, ginguba) |

A mobília automática (`_auto_furnish` em `interior_generator.gd`) segue o nome da divisão:
sala → sofá, tapete, mesa com cadeiras, candeeiro; quarto → cama; cozinha → frigorífico e
mesa; armazém → estantes; escritório/gabinete → secretária; salão → balcão + mesas ou
estantes conforme o negócio; celas → grades e bancos.
Demo web: `?interior=casa|escritorio|esquadra|cafe|shopping|restaurante|cantina|loja|ilha`.

## Multijogador online (encontrar-se e conversar)

Servidor dedicado por **WebSocket** (funciona no browser e no desktop), autoload `Network`
(`scripts/net/network.gd`):

```
cliente ──register(nome, aparência)──► servidor ──_peer_list / _peer_joined──► outros
cliente ──send_state (15×/s, unreliable)──► servidor valida ──_peer_state──► outros
cliente ──send_chat──► servidor (anti-spam 0,6 s, 160 car.) ──_chat──► todos
```

1. No computador anfitrião: `godot/bandula/tools/run_server.sh` (porta TCP 9080 aberta na firewall/router).
2. Cada jogador abre o jogo → ecrã inicial **Jogar online**: nome, aparência (7 avatares) e
   endereço (por omissão `ws://<anfitrião-da-página>:9080`). Atalho:
   `index.html?online=1&nome=Ana&aparencia=2` · `?solo` salta o menu.
3. Os outros jogadores aparecem com o nome por cima, a andar/correr/sentar ou dentro do carro
   que conduzem. Só se vê quem está no mesmo sítio: na rua, ou **no mesmo interior** (mesmo
   restaurante, casa, shopping…).
4. **T** abre o chat: histórico no canto do HUD e balão sobre o avatar de quem fala;
   o servidor anuncia entradas/saídas.

Partilhado: presença, posição, animação, veículo, interior, chat. **Local** (cada um tem o seu
império): economia, lotes, mobília, estrelas de procurado, trânsito e NPC.
Se a página for servida por **https**, o browser exige `wss://` — pôr o servidor atrás de um
proxy com TLS (ex.: Caddy/nginx `reverse_proxy` para a porta 9080) e usar `wss://dominio/...`.

Ficheiros: `scripts/net/network.gd` (rede + validação), `remote_players.gd` (gere os avatares
remotos e a visibilidade por sala), `remote_avatar.gd` (interpolação, nome, balão, carro),
`server_main.gd` + `scenes/server.tscn` (servidor sem mapa), `tests/net_client.gd`.

## Ainda não incluído

Peões na rua, gravação do jogo, áudio e emotes (existem na versão web). O minimapa é redesenhado
10×/s para poupar a GPU no browser.
