# Notas Fiscais Rudnik

Funcionário externo manda a foto da nota pelo WhatsApp; a IA lê, pergunta só o que
faltar e lança. O financeiro confere num painel online.

Especificação completa: [docs/especificacao.md](docs/especificacao.md).

## Estrutura
- `supabase/migrations/`: schema do banco (Supabase, projeto `notas-fiscais-rudnik`)
- `supabase/tests/`: testes SQL do schema
- `n8n/`: workflows exportados (WhatsApp, IA, regras)
- `painel/`: painel do gestor (Vite + React)

## Decisões que mudaram a especificação
- Limite de gasto é individual por funcionário e serve só ao gestor: não barra o
  lançamento, a IA não avisa o funcionário e não há consulta "limite" pelo WhatsApp.
- Cadastro público desligado no Supabase Auth; gestores são criados à mão.

## Rodar os testes do schema
Num Postgres 15+ vazio:

    psql -f supabase/tests/stub_supabase.sql
    psql -f supabase/migrations/20261111120000_schema_inicial.sql
    psql -f supabase/tests/schema_inicial.sql

Todas as linhas devem sair `t` ou `OK`.

## Andamento
1. [x] Schema + carga inicial
2. [ ] n8n: primeiro acesso
3. [ ] n8n: lançamento + anti-loop
4. [ ] Painel: login, despesas, revisão, resumo
5. [ ] Painel: cadastros
6. [ ] Consultas pelo WhatsApp e lembrete mensal
