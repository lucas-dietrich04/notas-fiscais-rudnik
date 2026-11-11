-- Notas Fiscais Rudnik: schema inicial + carga inicial
-- Acesso: painel (gestores logados no Supabase Auth) e n8n (service role, ignora RLS).
-- Funcionários nunca acessam o banco direto, só pelo WhatsApp.

-- ---------------------------------------------------------------------------
-- Cadastros (editados pelo gestor no painel)
-- ---------------------------------------------------------------------------

create table funcionarios (
  id              uuid primary key default gen_random_uuid(),
  nome            text not null,
  cpf             text not null unique check (cpf ~ '^\d{11}$'),
  data_nascimento date not null,            -- senha inicial = ddmmaaaa
  telefone        text unique check (telefone ~ '^\d{10,15}$'), -- só dígitos, como o WhatsApp envia (wa_id); null = sem vínculo
  ativo           boolean not null default true,
  bloqueado       boolean not null default false,
  criado_em       timestamptz not null default now()
);

create table tipos_despesa (
  id            uuid primary key default gen_random_uuid(),
  nome          text not null unique,
  ativo         boolean not null default true,
  -- Lista de campos que a IA deve pedir para este tipo:
  -- [{ "chave": "km", "rotulo": "Km do odômetro", "tipo": "numero", "obrigatorio": true }]
  -- tipo: texto | numero | veiculo (grava em despesas.veiculo_id)
  --       | obra (grava em despesas.obra_id) | colegas (gera rateio em despesa_partes)
  campos_extras jsonb not null default '[]'::jsonb check (jsonb_typeof(campos_extras) = 'array')
);

create table obras (
  id    uuid primary key default gen_random_uuid(),
  nome  text not null unique,
  ativo boolean not null default true
);

create table veiculos (
  id    uuid primary key default gen_random_uuid(),
  nome  text not null,                      -- como o pessoal chama: "carro do Aelcio"
  placa text not null unique,
  ativo boolean not null default true
);

-- Limite é só controle do gestor: não barra lançamento nem avisa o funcionário.
create table limites (
  id              uuid primary key default gen_random_uuid(),
  funcionario_id  uuid not null references funcionarios (id) on delete cascade,
  tipo_despesa_id uuid references tipos_despesa (id) on delete cascade, -- null = total do funcionário no mês
  valor_mensal    numeric(12,2) not null check (valor_mensal > 0),
  unique nulls not distinct (funcionario_id, tipo_despesa_id)
);

-- ---------------------------------------------------------------------------
-- Despesas
-- ---------------------------------------------------------------------------

create table despesas (
  id                 uuid primary key default gen_random_uuid(),
  lancado_por        uuid not null references funcionarios (id),
  status             text not null default 'rascunho'
                     check (status in ('rascunho', 'aguardando_dados', 'lancada', 'cancelada', 'descartada')),
  -- Campos abaixo aceitam null: a regra 9 manda lançar com o que tem e sinalizar.
  data               date,
  valor_total        numeric(12,2) check (valor_total >= 0),
  emitente_nome      text,
  emitente_doc       text,                  -- CNPJ ou CPF, só dígitos
  tipo_despesa_id    uuid references tipos_despesa (id), -- null = tipo não cadastrado (sinalizado)
  tipo_servico       text,
  obra_id            uuid references obras (id),
  veiculo_id         uuid references veiculos (id),
  extras             jsonb not null default '{}'::jsonb,
  documento_fiscal   boolean,
  forma_pagamento    text,
  cartao_final       text check (cartao_final ~ '^\d{4}$'),
  chave_acesso       text,                  -- não é unique: duplicata confirmada é lançada e sinalizada
  arquivo_path       text,                  -- caminho no bucket privado "comprovantes"
  extracao_ia        jsonb,                 -- resposta crua da IA, para auditoria
  sinalizacoes       text[] not null default '{}'
                     check (sinalizacoes <@ array['nao_fiscal', 'acima_limite', 'tipo_nao_cadastrado',
                                                  'duplicidade', 'dados_incompletos']),
  wa_message_id      text unique,           -- id da mensagem do WhatsApp: a Meta reenvia webhooks, isso evita lançar 2x
  revisado_em        timestamptz,
  revisado_por       uuid references auth.users (id),
  observacao_revisao text,
  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now()
);

-- Sempre 1 linha ou mais por despesa. Totais e limites saem daqui.
create table despesa_partes (
  despesa_id     uuid not null references despesas (id) on delete cascade,
  funcionario_id uuid not null references funcionarios (id),
  valor          numeric(12,2) not null check (valor >= 0),
  primary key (despesa_id, funcionario_id)
);

-- ---------------------------------------------------------------------------
-- Estado do WhatsApp (uma linha por telefone)
-- ---------------------------------------------------------------------------

create table conversas (
  telefone           text primary key check (telefone ~ '^\d{10,15}$'),
  funcionario_id     uuid references funcionarios (id) on delete set null,
  despesa_id         uuid references despesas (id) on delete set null, -- despesa em andamento
  pergunta_pendente  text,
  perguntado_em      timestamptz,           -- base para repetir a pergunta após 2 h
  tentativas         int not null default 0, -- repetições da pergunta pendente
  tentativas_acesso  int not null default 0, -- erros seguidos de CPF/senha
  bloqueado          boolean not null default false, -- 3 erros de acesso; o painel lista para o gestor
  atualizado_em      timestamptz not null default now()
);

-- Falhas de IA/banco depois das tentativas (regra 15). A foto fica guardada em arquivo_path.
create table erros (
  id           uuid primary key default gen_random_uuid(),
  telefone     text,
  despesa_id   uuid references despesas (id) on delete set null,
  arquivo_path text,
  etapa        text not null,
  detalhe      jsonb,
  resolvido    boolean not null default false,
  criado_em    timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- atualizado_em automático
-- ---------------------------------------------------------------------------

create function tocar_atualizado_em() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.atualizado_em = now();
  return new;
end $$;

create trigger despesas_atualizado_em before update on despesas
  for each row execute function tocar_atualizado_em();
create trigger conversas_atualizado_em before update on conversas
  for each row execute function tocar_atualizado_em();

-- ---------------------------------------------------------------------------
-- Gasto do mês: fonte única para o n8n (limite) e para o painel (resumo)
-- ---------------------------------------------------------------------------

create view gasto_mensal with (security_invoker = true) as
select p.funcionario_id,
       d.tipo_despesa_id,
       date_trunc('month', d.data)::date as mes,
       sum(p.valor) as total
from despesa_partes p
join despesas d on d.id = p.despesa_id
where d.status = 'lancada' and d.data is not null
group by 1, 2, 3;

-- ---------------------------------------------------------------------------
-- Segurança: só gestor logado enxerga; anônimo não vê nada
-- ---------------------------------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array['funcionarios', 'tipos_despesa', 'obras', 'veiculos', 'limites',
                           'despesas', 'despesa_partes', 'conversas', 'erros']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy gestores_tudo on %I for all to authenticated using (true) with check (true)', t);
  end loop;
end $$;

insert into storage.buckets (id, name, public) values ('comprovantes', 'comprovantes', false);

create policy gestores_leem_comprovantes on storage.objects
  for select to authenticated using (bucket_id = 'comprovantes');

-- ---------------------------------------------------------------------------
-- Carga inicial: tipos de despesa e campos extras (o gestor edita no painel)
-- ---------------------------------------------------------------------------

insert into tipos_despesa (nome, campos_extras) values
('Combustível', '[
  {"chave": "veiculo", "rotulo": "Veículo (placa)",  "tipo": "veiculo", "obrigatorio": true},
  {"chave": "km",      "rotulo": "Km do odômetro",   "tipo": "numero",  "obrigatorio": true},
  {"chave": "litros",  "rotulo": "Litros",           "tipo": "numero",  "obrigatorio": true}
]'),
('Hospedagem', '[
  {"chave": "cidade",  "rotulo": "Cidade",           "tipo": "texto",   "obrigatorio": true},
  {"chave": "diarias", "rotulo": "Nº de diárias",    "tipo": "numero",  "obrigatorio": true},
  {"chave": "colegas", "rotulo": "Quem estava junto","tipo": "colegas", "obrigatorio": true}
]'),
('Alimentação', '[
  {"chave": "pessoas", "rotulo": "Nº de pessoas",    "tipo": "numero",  "obrigatorio": true},
  {"chave": "colegas", "rotulo": "Quem estava junto","tipo": "colegas", "obrigatorio": true}
]'),
('Pedágio/estacionamento', '[
  {"chave": "veiculo", "rotulo": "Veículo (placa)",  "tipo": "veiculo", "obrigatorio": true}
]'),
('Material/ferramenta', '[
  {"chave": "obra",    "rotulo": "Obra",             "tipo": "obra",    "obrigatorio": true},
  {"chave": "itens",   "rotulo": "O que foi comprado","tipo": "texto",  "obrigatorio": true}
]'),
('Manutenção de veículo', '[
  {"chave": "veiculo", "rotulo": "Veículo (placa)",  "tipo": "veiculo", "obrigatorio": true},
  {"chave": "servico", "rotulo": "Serviço feito",    "tipo": "texto",   "obrigatorio": true}
]'),
('Outros', '[
  {"chave": "descricao", "rotulo": "Descrição",      "tipo": "texto",   "obrigatorio": true}
]');
