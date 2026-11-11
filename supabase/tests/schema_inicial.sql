\set ON_ERROR_STOP on
-- helper: espera que o comando falhe
create function deve_falhar(sql text, nome text) returns void language plpgsql as $$
begin
  begin execute sql; exception when others then raise notice 'OK  % (%)', nome, sqlerrm; return; end;
  raise exception 'FALHOU: % deveria ter sido rejeitado', nome;
end $$;

insert into funcionarios (nome, cpf, data_nascimento) values
 ('Lucas','11111111111','1990-01-02'),('João','22222222222','1991-01-02'),('José','33333333333','1992-01-02');
select count(*) = 7 as carga_7_tipos from tipos_despesa;

select deve_falhar($$insert into funcionarios (nome,cpf,data_nascimento) values ('X','123','2000-01-01')$$, 'cpf invalido');
select deve_falhar($$insert into funcionarios (nome,cpf,data_nascimento) values ('X','11111111111','2000-01-01')$$, 'cpf duplicado');
select deve_falhar($$update funcionarios set telefone='+55 47 9999' where nome='Lucas'$$, 'telefone com mascara');
update funcionarios set telefone='5547999990001' where nome='Lucas';
select deve_falhar($$update funcionarios set telefone='5547999990001' where nome='João'$$, 'telefone em 2 funcionarios');

-- limites: 1 global por combinação, inclusive com nulls
insert into limites (funcionario_id, valor_mensal) select id, 1000 from funcionarios where nome='Lucas';
select deve_falhar($$insert into limites (funcionario_id, valor_mensal) select id, 2000 from funcionarios where nome='Lucas'$$, 'limite total duplicado');
select deve_falhar($$insert into limites (valor_mensal) values (500)$$, 'limite sem funcionario');

-- hotel R$ 300 com 2 colegas = 3 partes de R$ 100
with d as (
  insert into despesas (lancado_por, status, data, valor_total, emitente_nome, tipo_despesa_id, wa_message_id, sinalizacoes)
  select f.id, 'lancada', '2026-11-10', 300, 'Hotel X', t.id, 'wamid.1', '{}'
  from funcionarios f, tipos_despesa t where f.nome='Lucas' and t.nome='Hospedagem' returning id)
insert into despesa_partes select d.id, f.id, 100 from d, funcionarios f;
select bool_and(total = 100) and count(*) = 3 as rateio_3x100 from gasto_mensal where mes='2026-11-01';

select deve_falhar($$insert into despesas (lancado_por, wa_message_id) select id,'wamid.1' from funcionarios limit 1$$, 'webhook reenviado');
select deve_falhar($$update despesas set status='aprovada'$$, 'status invalido');
select deve_falhar($$update despesas set sinalizacoes='{qualquer}'$$, 'sinalizacao invalida');
select deve_falhar($$update despesas set cartao_final='12'$$, 'cartao_final invalido');
select deve_falhar($$insert into despesa_partes select despesa_id, funcionario_id, 1 from despesa_partes limit 1$$, 'parte duplicada');

-- recibo manual incompleto é aceito (regras 3 e 9)
insert into despesas (lancado_por, status, documento_fiscal, sinalizacoes)
select id, 'lancada', false, '{nao_fiscal,dados_incompletos}' from funcionarios where nome='Lucas';

-- cancelada sai do gasto; atualizado_em muda
select pg_sleep(0.01);
update despesas set status='cancelada' where wa_message_id='wamid.1';
select count(*) = 0 as cancelada_fora_do_gasto from gasto_mensal;
select atualizado_em > criado_em as trigger_atualizado_em from despesas where wa_message_id='wamid.1';

-- RLS: anon não vê nada, gestor vê
grant usage on schema public to anon, authenticated;
grant all on all tables in schema public to anon, authenticated;
set role anon;          select count(*) = 0 as anon_nao_ve from funcionarios;
reset role; set role authenticated; select count(*) = 3 as gestor_ve from funcionarios; select count(*) >= 0 as gestor_ve_view from gasto_mensal;
reset role;
select count(*) = 9 as rls_em_9_tabelas from pg_tables where schemaname='public' and rowsecurity;
