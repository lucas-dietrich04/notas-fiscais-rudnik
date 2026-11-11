# Notas Fiscais Rudnik: despesas pelo WhatsApp + painel do gestor

## Objetivo
Hoje o funcionário externo lança cada despesa à mão num app (nota,
descrição, valor). Aqui ele só manda a foto pelo WhatsApp: a IA lê,
pergunta só o que faltar, lança e confirma. O financeiro confere tudo
num painel online. Meta: facilitar a vida do funcionário e a
conferência.

## Princípios
- Projeto simples, ~20 usuários. Sem overengineering: a solução mais
  simples que funciona.
- Nunca travar a operação: a IA não recusa nota. O que foge do padrão
  é lançado e sinalizado para o financeiro.
- Funciona 24 h, todos os dias, sem horário comercial.
- A IA fala o mínimo: não puxa conversa e não responde ruído.
- Segurança proporcional: painel com login e fotos em bucket privado.

## Stack
- WhatsApp Cloud API (oficial), um número da empresa só para isso →
  webhook do n8n
- n8n sempre ligado (workflow ativo em produção, [n8n Cloud ou VPS]):
  conversa, extração, regras, lembretes
- IA: modelo com visão e áudio [Gemini], saída em JSON
- Supabase: Postgres, Storage, Auth (só gestores)
- Painel: [Vite + React] direto no Supabase, publicado com link [Vercel]
- Sem backend próprio: painel fala com o Supabase; n8n usa service role

## Quem configura o quê
- Gestor (painel): funcionários, tipos de despesa, campos extras,
  obras, veículos, limites.
- Nós (n8n): tom da conversa, prompts, lembretes, regras do fluxo.
- A cada mensagem o n8n lê os cadastros do painel e monta o contexto
  da IA. Mudou no painel, mudou na IA, sem deploy.

## Primeiro acesso
1. Gestor cadastra o funcionário no painel: nome, CPF, data de
   nascimento (é a senha inicial, ddmmaaaa).
2. Funcionário manda mensagem para o número. Telefone desconhecido: a
   IA pede CPF e senha.
3. O n8n confere no banco (a IA nunca decide se a senha está certa).
   Certo: vincula o telefone ao funcionário e libera o chat.
4. 3 erros seguidos: bloqueia o telefone e avisa no painel.
5. Trocou de número: gestor desvincula no painel e ele refaz o acesso.

## Fluxo de lançamento
1. Funcionário manda foto ou PDF (com ou sem texto/áudio junto).
2. IA extrai os dados e classifica: tipo de despesa e se o documento
   é fiscal ou não.
3. Tudo certo: lança direto e confirma em uma frase.
   Ex.: "R$ 53,00 de combustível no carro do Aelcio lançado."
4. Falta dado obrigatório, campo extra ou a leitura é duvidosa:
   pergunta antes, tudo em uma mensagem só. Com a resposta, lança e
   confirma.
5. Colegas citados: aplica o rateio e mostra a divisão na confirmação.
   Ex.: "R$ 300,00 de hotel lançado, dividido em 3: você, João e José
   (R$ 100,00 cada)."
6. Depois da confirmação a IA não espera resposta. O funcionário só
   volta a falar se algo estiver errado.

## Quando a IA responde (anti-loop)
Toda mensagem recebida é classificada antes de qualquer resposta:
- Comprovante (foto/PDF) → fluxo de lançamento
- Resposta a uma pergunta pendente → continua o lançamento
- Ajuste ("era 35", "foi no carro do João", "cancela") → corrige a
  última despesa, ou a que ele indicar, e confirma em uma frase
- Pergunta ou consulta ("minhas despesas", "total", "limite") → responde
- Ruído ("ok", "beleza", "valeu", emoji, figurinha) → não responde nada
Regras:
- Áudio é transcrito e tratado como texto.
- No máximo 1 resposta por mensagem recebida.
- A IA nunca responde às próprias mensagens.
- Dúvida se é ajuste: pergunta uma única vez; sem resposta clara, não
  insiste.

## Regras do produto
1. Nunca inventar dado. Ilegível ou ausente = perguntar.
2. Nota boa é lançada direto, sem pedir aprovação. A IA sempre
   confirma o que lançou: valor, tipo e o principal extra.
3. Recibo manual (caneta, sem CNPJ, chave de acesso ou dados fiscais)
   é aceito normalmente: lança com documento_fiscal = false e sinaliza.
4. Não existe aprovação do gestor. Sinalização nunca gera pendência
   para o funcionário.
5. Sinalizações para revisão do financeiro: não fiscal, acima do
   limite, tipo de despesa não cadastrado, possível duplicidade,
   dados incompletos.
6. Limite estourado: lança, avisa na própria confirmação e sinaliza.
7. Duplicidade (mesma chave de acesso, ou mesmo emitente + data +
   valor): pergunta antes de lançar; se ele confirmar, lança sinalizada.
8. Rateio: divide em partes iguais entre quem lançou e os colegas
   citados; centavos de sobra ficam com quem lançou. Colega é
   identificado pelo nome no cadastro; nome ambíguo ou não encontrado
   = perguntar. Cada parte entra no perfil e no limite de cada um,
   com o nome de quem lançou.
9. Pergunta sem resposta: repete 1 vez após [2 h]. Continua sem
   resposta: lança com o que tem e sinaliza "dados incompletos".
10. Uma foto = uma despesa. Várias fotos: uma por vez.
11. Imagem que não é comprovante: avisa uma vez e não lança.
12. Cancelamento não apaga: vira status "cancelada".
13. Mensagens em pt-BR, curtas, uma resposta completa em vez de
    várias (a Meta cobra por mensagem). R$, dd/mm/aaaa,
    America/Sao_Paulo.
14. Mensagem iniciada pela empresa fora da janela de 24 h (lembrete)
    usa template aprovado na Meta.
15. Falha na IA ou no banco: tenta de novo [3 vezes]. Não deu: guarda
    a foto, avisa o funcionário uma vez e registra o erro para nós.
    Nenhuma nota recebida pode se perder.

## Campos
- Obrigatórios: data, valor total, emitente, tipo de despesa
- Se existir no documento: CNPJ/CPF do emitente, número, chave de
  acesso, forma de pagamento, 4 últimos dígitos do cartão
- Gerais: tipo de serviço (instalação, assistência técnica), obra/cliente
- Extras por tipo (carga inicial; o gestor edita no painel):
  - Combustível: veículo (placa), km do odômetro, litros
  - Hospedagem: cidade, nº de diárias, quem estava junto
  - Alimentação: nº de pessoas, quem estava junto
  - Pedágio/estacionamento: veículo
  - Material/ferramenta: obra, o que foi comprado
  - Manutenção de veículo: veículo, serviço feito
  - Outros: descrição

## Painel do gestor
- Login por e-mail e senha (Supabase Auth), só gestores/financeiro
- Despesas: lista com filtros (mês, funcionário, tipo, obra, veículo,
  sinalização), foto da nota, totais, exportar CSV
- Revisão: fila das sinalizadas; financeiro corrige campos, marca
  como revisada e anota
- Resumo do mês: total por funcionário, tipo e obra; gasto x limite
- Cadastros: funcionários, tipos de despesa + campos extras, obras,
  veículos, limites mensais (por funcionário e/ou tipo)

## Dados (proposta inicial)
- funcionarios: nome, cpf, data_nascimento, telefone, ativo, bloqueado
- tipos_despesa: nome, ativo, campos_extras (jsonb)
- obras, veiculos: nome/placa, ativo
- limites: funcionario_id (opcional), tipo_despesa_id (opcional),
  valor_mensal
- despesas: lancado_por, status, data, valor_total, emitente_nome,
  emitente_doc, tipo_despesa_id, tipo_servico, obra_id, veiculo_id,
  extras (jsonb), documento_fiscal, forma_pagamento, cartao_final,
  chave_acesso, arquivo_path, extracao_ia (jsonb), sinalizacoes
  (text[]), revisado_em, revisado_por, observacao_revisao,
  atualizado_em
- despesa_partes: despesa_id, funcionario_id, valor (sempre 1 linha
  ou mais; totais e limites saem daqui)
- conversas: telefone, funcionario_id, despesa_id, pergunta_pendente,
  tentativas, atualizado_em
- Status: rascunho → aguardando_dados → lancada | cancelada |
  descartada

## Escopo
v1 (esta versão):
- Primeiro acesso por CPF + senha
- Lançamento por foto: lança direto, pergunta só o que falta, confirma
- Ajustes e cancelamento pelo WhatsApp (texto ou áudio)
- Rateio, sinalizações e limites
- Consultas pelo WhatsApp: "minhas despesas", "total", "limite"
- Lembrete mensal de fechamento (resumo + "falta alguma nota?")
- Painel completo (despesas, revisão, resumo, cadastros)

v2 (não fazer agora):
- Conciliação com a fatura do cartão de crédito Sicoob (importar a
  fatura ou usar agregador Open Finance) e cobrança da nota que falta
- Integração com ERP/contabilidade, consulta à SEFAZ

## Critérios de pronto
- Telefone novo só lança depois de CPF + senha corretos
- Cupom legível é lançado direto e a IA confirma em uma frase
- "Beleza", emoji ou figurinha depois da confirmação: IA em silêncio
- "Era 35, não 53": IA corrige a última despesa e confirma
- Recibo à mão é lançado e aparece na revisão como "não fiscal"
- Hotel de R$ 300 com 2 colegas vira 3 partes de R$ 100
- Limite estourado avisa o funcionário e aparece na revisão
- Tipo de despesa criado no painel já vale na próxima mensagem
- Foto enviada de madrugada é processada na hora
- Gestor filtra, vê a foto e exporta o mês

## Ordem de entrega
1. Schema + carga inicial (migration)
2. n8n: primeiro acesso
3. n8n: lançamento (extração, perguntas, rateio, confirmação,
   sinalizações) + classificação de mensagens (anti-loop)
4. Painel: login, despesas, revisão, resumo
5. Painel: cadastros
6. Consultas pelo WhatsApp e lembrete mensal
Em cada etapa: diga o que vai fazer, entregue e pare para eu revisar.
Dúvida que afete regra de negócio ou banco: pergunte.