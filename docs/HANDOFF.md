# Passagem para continuar o projeto

Estado em 11/11/2026. Leia nesta ordem: `docs/especificacao.md` → este arquivo
→ `docs/n8n-fluxos.md` → `docs/prompts/`.

## Pronto

- **Supabase** projeto `notas-fiscais-rudnik` (ref `balpzdhwzzehdelxxfip`,
  região São Paulo, plano free, organização "Rudnik" na conta GitHub do Lucas).
- Migrations aplicadas e testadas (`supabase/migrations/`):
  - `schema_inicial`: tabelas, RLS (só usuário logado = gestor), bucket privado
    `comprovantes`, view `gasto_mensal`, carga dos 7 tipos de despesa.
  - `funcoes_acesso_rateio`: RPCs `verificar_acesso`, `definir_rateio`,
    `buscar_duplicada` (só service_role) e view `limites_estourados`.
- Testes SQL em `supabase/tests/` (34 checagens passando).

## Decisões tomadas depois da especificação

- Limite de gasto é **individual por funcionário** (total do mês ou por tipo) e
  **só informa o gestor**: não barra, não avisa o funcionário, sem consulta
  "limite" pelo WhatsApp. Painel usa a view `limites_estourados`.
- Signup público do Supabase Auth **desligado**; gestores criados à mão.
- Supabase free para começar; ir para o Pro (backup diário) ao entrar em produção.
- WhatsApp: a Cloud API oficial com número de teste da Meta (+1 555) falha com
  **erro 130497** (Meta bloqueia número estrangeiro novo para usuários BR).
  Lucas decidiu usar **API não oficial: WAHA ou uazapi** (a definir). Fluxos
  foram desenhados com o provedor isolado para trocar depois.

## Pendente (na ordem da especificação)

1. [x] Schema + carga inicial
2. [ ] Escolher provedor (WAHA se o n8n estiver em VPS própria; uazapi se n8n Cloud)
       e montar "Normalizar entrada" + `enviar_whatsapp`
3. [ ] n8n: primeiro acesso (RPC pronta)
4. [ ] n8n: lançamento + classificação (prompts prontos)
5. [ ] Painel Vite + React (pasta `painel/` vazia): login, despesas, revisão,
       resumo, cadastros. Ler direto do Supabase com a chave publishable.
6. [ ] Lembrete mensal (resumo + "falta alguma nota?") e consultas

## Pendências do Lucas

- Desligar "Allow new users to sign up" em Supabase → Authentication.
- n8n versão 2.45.7: confirmar se é Cloud ou VPS.
- App na Meta criado (`Notas Rudnik`) fica sem uso se for API não oficial.
  O token temporário da Meta foi colado no chat em 11/11: expira sozinho,
  mas gere um novo se for reaproveitar o app.

## Credenciais (nunca no repo)

- Supabase: URL do projeto + service_role key (n8n) / publishable key (painel).
- Provedor WhatsApp: URL + API key da instância.
- IA (Gemini): API key.
