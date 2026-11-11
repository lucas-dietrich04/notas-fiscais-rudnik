# Notas Fiscais Rudnik

Funcionário externo manda a foto da nota pelo WhatsApp; a IA lê, pergunta só o que
faltar e lança. O financeiro confere num painel online.

Especificação: [docs/especificacao.md](docs/especificacao.md). **Para continuar o projeto, comece por [docs/HANDOFF.md](docs/HANDOFF.md).**

## Estrutura
- `supabase/migrations/`: schema do banco (Supabase, projeto `notas-fiscais-rudnik`)
- `supabase/tests/`: testes SQL do schema
- `docs/n8n-fluxos.md` e `docs/prompts/`: como montar os workflows e prompts da IA
- `n8n/`: workflows exportados (WhatsApp, IA, regras)
- `painel/`: painel do gestor (Vite + React)

## Decisões que mudaram a especificação
- Limite de gasto é individual por funcionário e serve só ao gestor: não barra o
  lançamento, a IA não avisa o funcionário e não há consulta "limite" pelo WhatsApp.
- WhatsApp por API não oficial (WAHA ou uazapi, a definir): a oficial bloqueou o número de teste (erro 130497).
- Cadastro público desligado no Supabase Auth; gestores são criados à mão.

## Rodar os testes do schema
Num Postgres 15+ vazio:

    psql -f supabase/tests/stub_supabase.sql
    psql -f supabase/migrations/20261111120000_schema_inicial.sql
    psql -f supabase/migrations/20261111150000_funcoes_acesso_rateio.sql
    psql -f supabase/tests/schema_inicial.sql   # banco limpo para cada arquivo de teste
    psql -f supabase/tests/funcoes_acesso_rateio.sql

Todas as linhas devem sair `t` ou `OK`.

## Andamento
1. [x] Schema + carga inicial
2. [ ] n8n: primeiro acesso
3. [ ] n8n: lançamento + anti-loop
4. [ ] Painel: login, despesas, revisão, resumo
5. [ ] Painel: cadastros
6. [ ] Consultas pelo WhatsApp e lembrete mensal
