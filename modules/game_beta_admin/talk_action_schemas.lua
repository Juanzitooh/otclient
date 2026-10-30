local function text(id, label, maximum, required, help)
    return { id = id, label = label, kind = "text", maxLength = maximum or 48, required = required ~= false, help = help }
end

local function amount(id, label, required, help)
    return { id = id, label = label, kind = "amount", maxLength = 16, required = required ~= false, help = help }
end

local function number(id, label, minimum, maximum, required, help)
    return { id = id, label = label, kind = "number", minimum = minimum, maximum = maximum, required = required ~= false, help = help }
end

local function choice(id, label, options, required, help)
    return { id = id, label = label, kind = "choice", options = options, required = required ~= false, help = help }
end

local schemaByWord = {}
local MAX_PLAYER_ICON_COUNTDOWN_SECONDS = 60

local function register(words, fields, options)
    local schema = options or {}
    schema.fields = fields or {}
    schema.impact = schema.impact or schema.confirm or "Acao de consulta ou teste; confira a resposta do Canary."
    for word in words:gmatch("[^|]+") do
        schemaByWord[word] = schema
    end
end

local onOff = { { "on", "Ativar" }, { "off", "Desativar" } }

-- Every command from the reviewed Canary catalogue is declared here. Commands
-- whose side effects or syntax cannot be bounded safely stay visible but disabled.
register("!aol", {}, { confirm = "Comprar 1 Amulet of Loss. O servidor validara seu saldo." })
register("!autoloot", { choice("mode", "Modo", { { "off", "Desligado" }, { "on", "Normal" }, { "all", "Normal e bosses" } }) }, { impact = "Altera sua preferencia de autoloot." })
register("!balance", {}, { impact = "Consultar seu saldo bancario." })
register("!bless", {}, { confirm = "Comprar todas as blessings disponiveis." })
register("!buyhouse", {}, { confirm = "Comprar a casa da porta a frente. O servidor validara os pre-requisitos." })
register("!checkvip|!vip", {}, { impact = "Consultar o status VIP da sua conta." })
register("!checktaint", {}, { impact = "Consultar o nivel de taint do personagem atual." })
register("!commands", {}, { impact = "Abrir a lista de comandos disponiveis para seu cargo." })
register("!deposit", { amount("amount", "Valor ou all", true, "Use um inteiro positivo ou all para depositar todo o saldo.") }, { separator = " ", confirm = "Mover Gold do inventario para o banco." })
register("!emote", { choice("state", "Emote", onOff) }, { impact = "Se emotes estiverem desativadas no servidor, sua preferencia nao muda." })
register("!flask", { choice("state", "Frascos", { { "on", "Deixar de receber" }, { "off", "Voltar a receber" } }) }, { impact = "Altera quais mensagens de frascos voce recebe." })
register("!hiddenshop", { choice("state", "Itens escondidos", { { "on", "Mostrar" }, { "off", "Ocultar" } }) }, { impact = "Altera a exibicao de itens escondidos para voce." })
register("!leavehouse", {}, { confirm = "Sair da casa atual e transferir a propriedade conforme as regras do servidor." })
register("!livestream", {}, { blockedReason = "O comando mistura senha, moderacao de espectadores e dados da transmissao. Use o chat enquanto um formulario seguro especifico nao estiver disponivel." })
register("!online", {}, { impact = "Consultar a lista publica de jogadores online." })
register("!refill", {}, { confirm = "Recarregar amuletos e aneis elegiveis usando silver tokens." })
register("!reward", {}, { confirm = "Solicitar a recompensa unica de arma de treino." })
register("!sellhouse", { text("target", "Personagem online", 48) }, { separator = " ", confirm = "Iniciar a negociacao da casa atual com o personagem selecionado." })
register("!serverinfo", {}, { impact = "Consultar configuracoes e taxas publicas do servidor." })
register("!time", {}, { impact = "Consultar o horario atual do mundo." })
register("!transfer", { text("target", "Destinatario", 48), number("amount", "Valor", 1, 2147483647) }, { separator = ", ", confirm = "Transferir Gold para outro personagem. O servidor validara saldo e destinatario." })
register("!withdraw", { number("amount", "Valor", 1, 2147483647) }, { separator = " ", confirm = "Retirar Gold do banco. O servidor validara o saldo." })

register("!position", {}, { impact = "Consultar as coordenadas atuais do personagem." })
register("/a", { number("steps", "Passos", 1, 20) }, { separator = " ", confirm = "Teletransportar o operador pela quantidade de passos selecionada." })
register("/active", {}, { blockedReason = "Teleporte aleatorio nao e necessario no beta fechado; use /goto para escolher o jogador de destino. Reavaliar em aperfeicoamentos." })
register("/afk", { choice("state", "AFK", onOff) }, { confirm = "Ativar AFK pode enviar mensagens aos jogadores proximos a cada cinco segundos ate voce andar ou sair." })
register("/ambientsound", {}, { blockedReason = "O OTClient do beta ainda nao apresenta este evento sonoro; suporte a audio fica para aperfeicoamento posterior." })
register("/b", { text("message", "Mensagem", 180) }, { separator = " ", blockedReason = "Transmissao global desativada no painel do beta fechado. Use o fluxo de anuncio aprovado." })
register("/ban", { text("target", "Personagem", 48), number("days", "Duracao em dias", 1, 3650), text("reason", "Motivo", 120) }, { separator = ", ", confirm = "Banimento afeta a conta do personagem e pode desconectar sessoes. Motivo obrigatorio para auditoria." })
register("/bless", {}, { impact = "Consultar o estado das blessings do operador." })
register("/c", { text("target", "Criatura ou jogador", 48) }, { separator = " ", confirm = "Empurrar o alvo selecionado." })
register("/changeflowmap", {}, { blockedReason = "Carrega outro mapa global de Soul War e pode substituir estado do mundo; indisponivel no painel do beta." })
register("/clean", {}, { confirm = "Remover itens do mapa segundo a regra cleanMap().", blockedReason = "A limpeza do mapa pode afetar conteudo de terceiros e fica fora dos testes assistidos pelo painel." })
register("/countmonsters", {}, { blockedReason = "O comando grava monster_count.txt no servidor e nao retorna a contagem ao painel." })
register("/distanceeffect", { number("effectId", "Efeito visual", 1, 65535) }, { separator = " ", impact = "Desenhar um efeito visual a sete tiles na direcao para a qual o operador olha." })
register("/down", {}, { confirm = "Descer um andar na posicao atual." })
register("/effect", { number("effectId", "Efeito magico", 1, 65535) }, { separator = " ", impact = "Mostrar um efeito visual na posicao do operador." })
register("/getlook", { text("target", "Criatura ou jogador", 48) }, { separator = " ", impact = "Consultar os atributos visuais da criatura selecionada." })
register("/getstorage", { text("target", "Personagem online", 48), text("storage", "Storage ID ou nome", 64) }, { separator = ", ", impact = "Consultar um valor de storage administrativo do personagem selecionado." })
register("/ghost", {}, { blockedReason = "O cargo exibido para esta acao nao coincide com o grupo autorizado pelo Canary." })
register("/goldrank", {}, { impact = "Consultar o ranking de personagens por saldo de Gold." })
register("/goto", { text("target", "Criatura, jogador ou fiendish/influenced", 48) }, { separator = " ", confirm = "Teletransportar o operador para o destino selecionado." })
register("/info", { text("target", "Jogador online", 48) }, { separator = " ", confirm = "Consultar dados administrativos sensiveis. Restrito a colaboradores autorizados." })
register("/kick", { text("target", "Jogador online", 48), text("reason", "Motivo", 120) }, { separator = ", ", confirm = "Desconectar o jogador selecionado. Motivo obrigatorio para auditoria." })
register("/listplayers", { choice("scope", "Jogadores", { { "all", "Todos" }, { "active", "Somente ativos" } }) }, { impact = "Consultar nomes e estado de atividade dos jogadores online." })
register("/looktype", { number("lookType", "Looktype", 0, 1468) }, { separator = " ", confirm = "Alterar a aparencia do operador." })
register("/mc", {}, { blockedReason = "A lista expoe enderecos IP; o alcance e o nivel de acesso precisam ser definidos." })
register("/musicsound", {}, { blockedReason = "O OTClient do beta ainda nao apresenta este evento sonoro; suporte a audio fica para aperfeicoamento posterior." })
register("/namelock", { text("target", "Personagem", 48), text("reason", "Motivo", 120) }, { separator = ", ", confirm = "Aplicar alteracao persistente ao nome do personagem." })
register("/pos|!pos", { number("x", "Coordenada X", 0, 65535, false), number("y", "Coordenada Y", 0, 65535, false), number("z", "Andar Z", 0, 15, false) }, { separator = ", ", blockedReason = "O handler alterna consulta e teleporte; use o chat ate o fluxo contextual ser separado." })
register("/rewardbag", { choice("bagId", "Bolsa", { { "34109", "Reward bag 34109" }, { "39546", "Reward bag 39546" }, { "43895", "Reward bag 43895" } }), number("count", "Aberturas", 1, 100) }, { separator = ", ", confirm = "Simular aberturas; nao concede itens e registra resultado no log do Canary." })
register("/setlight", {}, { blockedReason = "Efeito visual de desenvolvimento sem alteracao confirmada no cliente beta; revisar em aperfeicoamentos." })
register("/spy", { text("target", "Jogador online", 48) }, { separator = " ", confirm = "Consultar inventario e equipamento do jogador selecionado." })
register("/t", { text("target", "Jogador online", 48) }, { separator = " ", confirm = "Teletransportar o alvo para o proprio templo." })
register("/teleport|/tp", { number("x", "Coordenada X", 0, 65535), number("y", "Coordenada Y", 0, 65535), number("z", "Andar Z", 0, 15) }, { separator = ", ", confirm = "Criar portal para as coordenadas informadas." })
register("/town", { text("town", "Cidade por nome ou ID", 48) }, { separator = " ", confirm = "Teletransportar o operador para o templo da cidade." })
register("/unban", { text("target", "Personagem", 48) }, { separator = " ", confirm = "Remover banimento associado ao personagem." })
register("/up", {}, { confirm = "Subir um andar na posicao atual." })

register("!testcontainer", { choice("remove", "Conteudo da backpack", { { "", "Manter itens" }, { "remove", "Remover itens" } }, false) }, { confirm = "A opcao Remover apaga os itens da backpack." })
register("/addachievement", { text("target", "Personagem online", 48), text("achievement", "Conquista por nome ou ID", 64) }, { separator = ", ", confirm = "Adicionar uma conquista persistente." })
register("/addaddon", { text("target", "Personagem online", 48), text("lookType", "Looktype ou all", 16), number("addon", "Addon", 0, 3) }, { separator = ", ", confirm = "Alterar addons do personagem selecionado." })
register("/addbadge", { text("target", "Personagem online", 48), number("badge", "Badge ID", 1, 65535) }, { separator = ", ", confirm = "Adicionar badge persistente ao personagem." })
register("/addbosskill", { number("count", "Kills", 1, 1000000), text("monster", "Monstro", 48), text("target", "Personagem online ou vazio para voce", 48, false) }, { separator = ", ", confirm = "Alterar contagem persistente de boss kills." })
register("/addcharms", { text("target", "Personagem online", 48), number("count", "Pontos de charm", 1, 1000000) }, { separator = ", ", confirm = "Adicionar pontos de charm persistentes." })
register("/adddustlevel", { text("target", "Personagem online", 48), number("count", "Niveis de dust", 1, 1000) }, { separator = ", ", confirm = "Aumentar permanentemente o limite de dust do personagem." })
register("/adddusts", { text("target", "Personagem online", 48), number("count", "Dusts", 1, 1000000) }, { separator = ", ", confirm = "Adicionar dusts ao personagem selecionado." })
register("/addloot", { text("item", "Item por nome ou ID", 64), number("count", "Quantidade", 1, 10000, false) }, { separator = " ", confirm = "Adicionar item a Loot Pouch propria." })
register("/addminorcharms", {}, { blockedReason = "Concede progressao persistente de minor charms; nao e necessario para moderacao do beta. Reavaliar em T6.30 com escopo, limites e auditoria." })
register("/addmoney", { text("target", "Personagem online", 48), number("amount", "Gold", 1, 2147483647) }, { separator = ", ", confirm = "Alterar a economia do personagem selecionado." })
register("/addmount", { text("target", "Personagem online", 48), text("mount", "Mount ID ou all", 16) }, { separator = ", ", confirm = "Desbloquear mount(s) para a conta do personagem." })
register("/addreward", { text("item", "Item por nome ou ID", 64), number("count", "Quantidade", 1, 10000, false), text("target", "Personagem online ou vazio para voce", 48, false) }, { separator = ", ", confirm = "Adicionar recompensa ao personagem selecionado." })
register("/addskill", { text("target", "Personagem online", 48), choice("skill", "Skill", { { "level", "Level" }, { "magic", "Magic level" } }), number("count", "Quantidade", 1, 1000000, false) }, { separator = ", ", confirm = "Alterar progresso persistente de skill." })
register("/addtitle", { text("target", "Personagem online", 48), number("title", "Title ID", 1, 65535) }, { separator = ", ", confirm = "Adicionar titulo persistente ao personagem." })
register("/addtutor", { text("target", "Personagem elegivel online", 48) }, { separator = " ", confirm = "Promover a conta ao nivel tutor." })
register("/areasound", { number("soundId", "Sound ID", 1, 65535), number("secondaryId", "ID secundario", 0, 65535, false) }, { separator = ", ", confirm = "Emitir o efeito sonoro para jogadores proximos na area." })
register("/attr", {}, { blockedReason = "O handler altera atributos de itens e jogadores por uma whitelist contextual. Aguarda um seletor de alvo e opcoes verificadas." })
register("/bakragoreicon", { text("icon", "ID do icone ou remove", 16) }, { separator = " ", confirm = "Alterar icones persistentes do personagem atual." })
register("/bountypoints", { text("target", "Personagem online", 48), number("amount", "Quantidade (vazio consulta)", 0, 1000000, false) }, { separator = ", ", confirm = "Com quantidade, altera saldo persistente de bounty points." })
register("/charmexpansion", { text("target", "Personagem online (vazio = voce)", 48, false) }, { separator = " ", confirm = "Habilitar expansao de charms." })
register("/charmrunes", { text("target", "Personagem online (vazio = voce)", 48, false) }, { separator = " ", confirm = "Desbloquear todas as runas de charm." })
register("/checkachievements", { text("target", "Personagem online", 48) }, { separator = " ", impact = "Consultar as conquistas do personagem selecionado." })
register("/clearcooldown", { text("boss", "Boss", 48), text("target", "Personagem (vazio = voce)", 48, false) }, { separator = ", ", confirm = "Limpar o cooldown do boss selecionado." })
register("/clearhirelingstas", {}, { blockedReason = "Limpeza tecnica de hirelings fora da moderacao do beta; aguarda protecao de alvo e persistencia validada." })
register("/clearloot", {}, { confirm = "Remover todos os itens da Loot Pouch propria." })
register("/closeserver", {}, { blockedReason = "Operacao global de servidor excluida do painel do beta fechado." })
register("/countloot", {}, { impact = "Consultar os itens na Loot Pouch do operador." })
register("/createloot", { number("count", "Quantidade", 1, 10000) }, { separator = " ", confirm = "Criar itens aleatorios da lista fixa na Loot Pouch." })
register("/createtestshop", {}, { blockedReason = "Catalogo de teste excede mil itens e nao e necessario para o beta; use a criacao individual de itens." })
register("/fiendish", {}, { confirm = "Teletransportar o operador para um monstro fiendish disponivel." })
register("/forceperiod", { choice("period", "Periodo", { { "day", "Dia" }, { "night", "Noite" }, { "auto", "Automatico" } }) }, { separator = " ", confirm = "Alterar a iluminacao global do mundo. A opcao Automatico restaura o comportamento normal." })
register("/getallkv", { text("target", "Personagem online (vazio = voce)", 48, false) }, { separator = " ", impact = "Consultar valores KV administrativos do personagem selecionado." })
register("/getdusts", { text("target", "Personagem online", 48) }, { separator = " ", impact = "Consultar o saldo de dusts do personagem selecionado." })
register("/getkv", { text("key", "Chave KV", 64), text("target", "Personagem online (vazio = voce)", 48, false) }, { separator = ", ", impact = "Consultar um valor KV administrativo do personagem selecionado." })
register("/globalsound", { number("soundId", "Sound ID", 1, 65535), number("effectId", "Effect ID", 0, 65535, false) }, { separator = ", ", confirm = "O som afeta o mundo inteiro." })
register("/gotohouse", { text("target", "Personagem online (vazio = voce)", 48, false) }, {
    separator = " ",
    confirm = "Teletransportar voce para a saida da sua casa ou da casa do personagem selecionado.",
})
register("/hasflag", { text("target", "Personagem online", 48), text("flag", "Flag por nome ou ID", 64) }, { separator = ", ", impact = "Consultar uma flag administrativa do personagem selecionado." })
register("/hireling", { text("name", "Nome (vazio usa padrao)", 48, false), number("sex", "Sexo", 0, 1, false) }, { separator = ", ", confirm = "Criar hireling vinculado a conta/personagem." })
register("/i", { text("item", "Item por nome ou ID", 64), number("count", "Quantidade", 1, 10000, false), number("tier", "Tier (opcional)", 1, 10, false) }, { separator = ", ", confirm = "Criar item no inventario do operador." })
register("/inbox", {}, { blockedReason = "Altera itens do Store Inbox do alvo e pode afetar itens de loja. Nao e necessario para conceder itens de teste; reavaliar em T6.30." })
register("/influenced", {}, { confirm = "Teletransportar o operador para um monstro influenced disponivel." })
register("/internalsound", { number("soundId", "Sound ID", 1, 65535), number("secondaryId", "ID secundario", 0, 65535, false) }, { separator = ", ", impact = "Reproduzir o efeito sonoro apenas para o operador." })
register("/ipban", {}, { blockedReason = "Banimento por IP e remocao de sessao nao sao disponibilizados pelo painel beta." })
register("/listraid", {}, { impact = "Consultar os nomes das raids registradas." })
register("/m", { text("monster", "Monstro por nome", 48), number("count", "Quantidade", 1, 3, false), choice("forge", "Forge", { { "", "Normal" }, { "fiendish", "Fiendish" }, { "influenced", "Influenced" } }, false), number("radius", "Raio", 1, 5, false), choice("force", "Forcar criacao", { { "", "Nao" }, { "true", "Sim" } }, false) }, { separator = ", ", confirm = "Criar ate tres monstros ao redor do operador." })
register("/n", { text("npc", "NPC", 48), choice("persistence", "Persistencia", { { "temporary", "Temporario" }, { "permanent", "Permanente" } }) }, { separator = ", ", blockedReason = "Criacao permanente altera arquivos do mundo; esse fluxo aguarda ferramenta propria." })
register("/openforge", {}, { impact = "Abrir a interface de forge para o operador." })
register("/openserver", {}, { blockedReason = "Operacao global de servidor excluida do painel do beta fechado." })
register("/owner", { text("owner", "Personagem online (vazio ou none limpa)", 48, false) }, { separator = " ", confirm = "Alterar ou limpar o proprietario da casa no tile atual." })
register("/playericon", {
    number("iconId", "Icone (19-24)", 19, 24),
    number("count", "Contagem (segundos)", 1, MAX_PLAYER_ICON_COUNTDOWN_SECONDS),
    choice("direction", "Direcao", { { "up", "Aumentar" }, { "down", "Diminuir" } }),
}, {
    separator = ", ",
    confirm = ("Executar a contagem do icone de teste no personagem atual por ate %d segundos. O icone sera removido 10 segundos depois."):format(MAX_PLAYER_ICON_COUNTDOWN_SECONDS),
})
register("/proficiency", { number("experience", "Experiencia", 1, 2147483647) }, { separator = " ", confirm = "Adicionar experiencia a arma equipada." })
register("/protocolprobe|/probeopcode", {}, { blockedReason = "Probes de protocolo arbitrarios nao sao enviados pela UI administrativa." })
register("/r", {}, { blockedReason = "Remocao contextual de criaturas/itens fica bloqueada ate o alvo ser inspecionado e mostrado antes do envio." })
register("/raid", { text("raid", "Raid registrada", 48) }, { separator = " ", confirm = "Iniciar uma raid no mundo." })
register("/reload", {}, { blockedReason = "Reload de subsistemas pode interromper o beta; aguarda uma lista allowlist revisada." })
register("/removeachievement", { text("target", "Personagem online", 48), text("achievement", "Achievement ID", 16) }, { separator = ", ", confirm = "Remover conquista persistente." })
register("/removedusts", { text("target", "Personagem online", 48), number("count", "Dusts", 1, 1000000) }, { separator = ", ", confirm = "Remover dusts do personagem selecionado." })
register("/removeflag", {}, { blockedReason = "O handler altera flags do grupo compartilhado, nao uma permissao individual; bloqueado para evitar efeito amplo." })
register("/removetutor", { text("target", "Personagem tutor online", 48) }, { separator = " ", confirm = "Rebaixar a conta ao nivel normal." })
register("/resetcd", { text("target", "Personagem (vazio = voce)", 48, false) }, { separator = " ", confirm = "Limpar todos os cooldowns de magia do personagem indicado; vazio usa voce." })
register("/resetcharms", { text("target", "Personagem online (vazio = voce)", 48, false) }, { separator = " ", confirm = "Reiniciar charms e bestiary." })
register("/s", { text("monster", "Monstro por nome", 48) }, { separator = " ", confirm = "Invocar o monstro como summon do operador." })
register("/save", { number("minutes", "Minutos (vazio salva agora)", 1, 10080, false) }, { separator = " ", confirm = "Salvar o mundo agora ou agendar o salvamento em minutos." })
register("/removetaint", {}, { blockedReason = "Remove progresso persistente de Soul War de outro personagem; aguarda um fluxo contextual com revisao e restauracao." })
register("/setbestiary", { text("target", "Personagem online", 48), text("monster", "Monstro ou all", 48), number("kills", "Kills", 0, 1000000) }, { separator = ", ", confirm = "Alterar progresso persistente de bestiary." })
register("/setdusts", { text("target", "Personagem online", 48), number("count", "Novo total", 0, 1000000) }, { separator = ", ", confirm = "Definir o total persistente de dusts." })
register("/setfiendish", {}, { confirm = "Executar player:setFiendish() no operador." })
register("/setflag", {}, { blockedReason = "O handler altera flags do grupo compartilhado, nao uma permissao individual; bloqueado para evitar efeito amplo." })
register("/setkv", {}, { blockedReason = "O handler aceita valor Lua. Valores executaveis nunca sao enviados pelo formulario." })
register("/setmonstername", { text("name", "Novo nome", 48) }, { separator = " ", confirm = "Renomear monstros em ate quatro tiles do operador." })
register("/setstorage", { number("storage", "Storage ID", 1, 2147483647), number("value", "Valor", -2147483648, 2147483647), text("target", "Personagem (vazio = voce)", 48, false) }, { separator = ", ", confirm = "Gravar storage persistentemente no personagem." })
register("/settaint", {}, { blockedReason = "Altera progresso persistente de Soul War em outro personagem; aguarda um fluxo contextual com revisao e restauracao." })
register("/settitle", { text("target", "Personagem online", 48), number("title", "Title ID", 1, 65535) }, { separator = ", ", confirm = "Definir titulo ativo do personagem." })
register("/simraid", {}, { blockedReason = "A simulacao pode gerar atividade intensiva e efeitos globais; indisponivel no painel beta." })
register("/soulseals", { text("target", "Personagem online", 48), number("amount", "Quantidade (vazio consulta)", 0, 1000000, false) }, { separator = ", ", confirm = "Com quantidade, altera o saldo persistente de Soul Seals." })
register("/spawn", { text("monster", "Monstro", 48), number("interval", "Respawn em segundos", 1, 86400, false) }, { separator = ", ", confirm = "Criar ponto de spawn em runtime. Ele nao persiste apos reiniciar o servidor." })
register("/taskboarddelivery", { text("target", "Personagem online", 48) }, { separator = " ", confirm = "Preparar entregas semanais e possivelmente adicionar itens ao stash." })
register("/taskpoints", { text("target", "Personagem online", 48), number("amount", "Quantidade (vazio consulta)", 0, 1000000, false) }, { separator = ", ", confirm = "Com quantidade, altera task points persistentes." })
register("/taskslot", { text("target", "Personagem online", 48), number("slot", "Slot", 0, 1) }, { separator = ", ", confirm = "Alterar o slot de task persistente." })
register("/testicon", { text("icons", "IDs de icones permitidos", 48) }, { separator = " ", confirm = "Mostrar os icones de teste no personagem." })
register("/testlog", { choice("level", "Nivel", { { "info", "Info" }, { "warn", "Warn" }, { "error", "Error" }, { "debug", "Debug" } }), text("message", "Mensagem", 180) }, { separator = " ", blockedReason = "Emissao de mensagens arbitrarias no log fica fora da interface beta." })
register("/testmessage", { number("type", "Tipo de mensagem", 0, 255), number("color", "Cor (opcional)", 0, 255, false) }, { separator = ", ", impact = "Enviar uma mensagem de teste apenas ao operador." })
register("/testtaintconditions", {}, { blockedReason = "Diagnostico visual de desenvolvimento; nao faz parte dos testes de moderacao do beta fechado." })
register("/vip", { choice("operation", "Operacao", { { "check", "Consultar" }, { "adddays", "Adicionar dias" }, { "removedays", "Remover dias" }, { "remove", "Remover VIP" } }), text("target", "Personagem online", 48), number("days", "Dias (obrigatorio para adicionar/remover)", 1, 90, false) }, {
    separator = ", ",
    confirm = "Alterar assinatura VIP persistente.",
    actionText = {
        field = "operation",
        values = {
            check = {
                impact = "Consultar os dias VIP do personagem, sem alterar a assinatura.",
                confirm = "Consultar o saldo VIP do personagem selecionado.",
            },
            adddays = {
                impact = "Adicionar dias VIP persistentes ao personagem selecionado.",
                confirm = "Adicionar dias VIP persistentes ao personagem selecionado.",
            },
            removedays = {
                impact = "Remover dias VIP; se a quantidade exceder o saldo, todos os dias restantes serao removidos.",
                confirm = "Remover a quantidade indicada de dias VIP; se exceder o saldo, todos os dias restantes serao removidos.",
            },
            remove = {
                impact = "Remover todos os dias VIP do personagem selecionado.",
                confirm = "Remover todos os dias VIP do personagem selecionado.",
            },
        },
    },
})
schemaByWord["/vip"].fields[3].requiredWhen = { field = "operation", values = { adddays = true, removedays = true } }
register("/zones", {}, { blockedReason = "O handler mistura inspecao, teleporte, remocao de criaturas e expulsao de jogadores. Aguarda fluxos separados e limitados." })

BetaAdminTalkActionSchemas = schemaByWord
