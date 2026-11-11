# Fluxos do n8n

Especificação para montar os workflows. Regras de negócio: `docs/especificacao.md`.
Tudo que é regra fixa (senha, rateio, duplicidade) está em funções do banco;
o n8n só chama via RPC com a credencial **service_role**.

## Camada de WhatsApp (isolada)

O provedor ainda não está fechado (WAHA ou uazapi; a Cloud API oficial travou
no erro 130497 com número de teste dos EUA). Por isso o resto do fluxo **não
conhece o provedor**:

```
[Webhook do provedor] → [Normalizar entrada] → (fluxo principal) → [Enviar resposta] → [Adaptador do provedor]
```

Formato normalizado de entrada (o único que o fluxo principal lê):

```json
{
  "message_id": "id único da mensagem no provedor",
  "telefone": "5547999990001",
  "de_mim": false,
  "tipo": "texto | imagem | documento | audio | figurinha | outro",
  "texto": "legenda ou corpo, se houver",
  "midia_url": "url temporária para baixar, se houver",
  "midia_mime": "image/jpeg",
  "recebido_em": "2026-11-11T14:35:12-03:00"
}
```

Descartar logo no início: `de_mim = true` (a IA nunca responde a si mesma),
mensagens de grupo e status/recibos de entrega.

Envio: um subworkflow `enviar_whatsapp(telefone, texto)`. Trocar de provedor =
trocar só esse subworkflow e o "Normalizar entrada".

## Fluxo principal

```
entrada normalizada
  │
  ├─ wa message_id já processado? (despesas.wa_message_id) → parar   (webhook reenviado)
  │
  ├─ conversa = select conversas where telefone
  │     ├─ bloqueado → parar em silêncio
  │     └─ sem funcionario_id → PRIMEIRO ACESSO
  │
  └─ CLASSIFICAR (IA, prompt docs/prompts/classificar.md)
        ├─ comprovante  → LANÇAMENTO
        ├─ resposta     → continua a despesa em conversas.despesa_id
        ├─ ajuste       → AJUSTE
        ├─ consulta     → CONSULTA (etapa 6)
        └─ ruido        → parar, sem resposta
```

Máximo 1 resposta por mensagem recebida.

## Primeiro acesso

1. Telefone sem vínculo manda qualquer coisa.
2. IA extrai CPF e senha do texto (podem vir na mesma mensagem ou separados;
   guardar o que já veio em `conversas.pergunta_pendente`).
3. Faltando algum: pedir "Para começar, me envie seu CPF e sua senha (data de nascimento, ddmmaaaa)."
4. Com os dois: `rpc verificar_acesso(telefone, cpf, senha)`:
   - `ok` → "Pronto, {nome}! Agora é só mandar a foto das notas."
   - `invalido` → "CPF ou senha não conferem. Restam {tentativas_restantes} tentativas."
   - `bloqueado` → "Acesso bloqueado. Fale com o financeiro." (só na 1ª vez; depois silêncio)
   - `inativo` → "Seu cadastro está inativo. Fale com o financeiro."

## Lançamento

1. Baixar a mídia, salvar no bucket `comprovantes` em `{funcionario_id}/{aaaa-mm}/{message_id}.{ext}`
   **antes** de qualquer IA (regra 15: nenhuma nota se perde).
2. Montar contexto da IA lendo, a cada mensagem: `tipos_despesa` ativos com
   `campos_extras`, `obras` ativas, `veiculos` ativos, nomes dos `funcionarios` ativos.
3. IA de extração (`docs/prompts/extracao.md`) → JSON.
4. `nao_comprovante = true` → avisar uma vez e não lançar (regra 11).
5. Criar `despesas` com `wa_message_id`, `arquivo_path`, `extracao_ia`, status `rascunho`.
6. `rpc buscar_duplicada(...)` → achou: perguntar "Parece que essa nota já foi lançada
   em {data}. Lanço mesmo assim?" Sim → lançar com sinalização `duplicidade`.
7. Faltou obrigatório ou campo extra obrigatório, ou leitura duvidosa:
   status `aguardando_dados`, gravar pergunta em `conversas` e perguntar
   **tudo numa mensagem só**.
8. Colegas citados: casar nome com `funcionarios`. Ambíguo ou não achado → perguntar.
9. Lançar: status `lancada`, `rpc definir_rateio(despesa_id, colegas[])`, calcular sinalizações:
   - `nao_fiscal` se `documento_fiscal = false`
   - `tipo_nao_cadastrado` se não casou com `tipos_despesa`
   - `acima_limite` se `limites_estourados` tem linha do funcionário no mês
     (**não avisar o funcionário**: limite é só para o gestor)
   - `dados_incompletos` se lançou por timeout (passo 11)
10. Confirmar em uma frase: valor, tipo, principal extra, rateio se houver.
    Ex.: "R$ 300,00 de hotel lançado, dividido em 3: você, João e José (R$ 100,00 cada)."
11. Pergunta sem resposta: workflow agendado a cada 15 min procura
    `conversas.perguntado_em < now() - 2h`: `tentativas = 0` → repete 1 vez;
    `tentativas = 1` → lança com o que tem e sinaliza `dados_incompletos`.

## Ajuste

"era 35", "foi no carro do João", "cancela": aplica na última despesa lançada
do funcionário (ou na que ele indicar), refaz `definir_rateio` se o valor ou os
colegas mudaram, confirma em uma frase. Cancelar = status `cancelada`, nunca apagar.
Dúvida se é ajuste: pergunta uma vez; sem resposta clara, não insiste.

## Erros (regra 15)

Cada chamada de IA e de banco: 3 tentativas. Falhou: inserir em `erros`
(telefone, arquivo_path, etapa, detalhe), avisar o funcionário uma vez
("Recebi sua nota, mas tive um problema para lançar. O financeiro vai conferir."),
e notificar a equipe.

## Formatos

pt-BR, `R$ 1.234,56`, `dd/mm/aaaa`, fuso America/Sao_Paulo.
