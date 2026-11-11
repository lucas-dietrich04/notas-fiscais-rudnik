-- Regras que o n8n chama via RPC. Ficam no banco para a IA nunca decidir
-- senha nem fazer conta de rateio (regra 1 e "o n8n confere no banco").
-- Só o service_role (n8n) executa.

-- ---------------------------------------------------------------------------
-- Primeiro acesso: confere CPF + senha (data de nascimento ddmmaaaa)
-- Retorno: ok | invalido | bloqueado | inativo
-- ---------------------------------------------------------------------------
create function verificar_acesso(p_telefone text, p_cpf text, p_senha text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_conversa public.conversas;
  v_func     public.funcionarios;
  v_cpf      text := regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
  v_senha    text := regexp_replace(coalesce(p_senha, ''), '\D', '', 'g');
begin
  insert into public.conversas (telefone) values (p_telefone)
  on conflict (telefone) do nothing;

  select * into v_conversa from public.conversas where telefone = p_telefone for update;
  if v_conversa.bloqueado then
    return jsonb_build_object('status', 'bloqueado');
  end if;

  select * into v_func from public.funcionarios
  where cpf = v_cpf and to_char(data_nascimento, 'DDMMYYYY') = v_senha;

  if v_func.id is null then
    update public.conversas
       set tentativas_acesso = tentativas_acesso + 1,
           bloqueado = tentativas_acesso + 1 >= 3
     where telefone = p_telefone
    returning * into v_conversa;
    return jsonb_build_object('status', case when v_conversa.bloqueado then 'bloqueado' else 'invalido' end,
                              'tentativas_restantes', greatest(0, 3 - v_conversa.tentativas_acesso));
  end if;

  if not v_func.ativo or v_func.bloqueado then
    return jsonb_build_object('status', 'inativo');
  end if;

  -- Telefone novo substitui o antigo: o gestor desvincula pelo painel, mas se
  -- ele esquecer, quem provou CPF + senha leva o vínculo.
  update public.conversas set funcionario_id = null where funcionario_id = v_func.id and telefone <> p_telefone;
  update public.funcionarios set telefone = null where telefone = p_telefone and id <> v_func.id;
  update public.funcionarios set telefone = p_telefone where id = v_func.id;
  update public.conversas set funcionario_id = v_func.id, tentativas_acesso = 0 where telefone = p_telefone;

  return jsonb_build_object('status', 'ok', 'funcionario_id', v_func.id, 'nome', v_func.nome);
end $$;

-- ---------------------------------------------------------------------------
-- Rateio: partes iguais; centavos de sobra ficam com quem lançou (regra 8).
-- Substitui as partes existentes, então também serve para ajustes.
-- ---------------------------------------------------------------------------
create function definir_rateio(p_despesa_id uuid, p_colegas uuid[] default '{}')
returns setof public.despesa_partes
language plpgsql security definer set search_path = '' as $$
declare
  v_desp     public.despesas;
  v_pessoas  uuid[];
  v_n        int;
  v_base     numeric(12,2);
  v_sobra    numeric(12,2);
begin
  select * into v_desp from public.despesas where id = p_despesa_id;
  if v_desp.id is null then raise exception 'despesa % não existe', p_despesa_id; end if;

  select array_agg(distinct c) into v_pessoas
  from unnest(coalesce(p_colegas, '{}')) c where c <> v_desp.lancado_por;
  v_pessoas := array[v_desp.lancado_por] || coalesce(v_pessoas, '{}');
  v_n := array_length(v_pessoas, 1);

  v_base  := trunc(coalesce(v_desp.valor_total, 0) / v_n, 2);
  v_sobra := coalesce(v_desp.valor_total, 0) - v_base * v_n;

  delete from public.despesa_partes where despesa_id = p_despesa_id;
  insert into public.despesa_partes (despesa_id, funcionario_id, valor)
  select p_despesa_id, p, v_base + case when p = v_desp.lancado_por then v_sobra else 0 end
  from unnest(v_pessoas) p;

  return query select * from public.despesa_partes where despesa_id = p_despesa_id;
end $$;

-- ---------------------------------------------------------------------------
-- Possível duplicidade (regra 7): mesma chave, ou mesmo emitente + data + valor
-- ---------------------------------------------------------------------------
create function buscar_duplicada(p_chave text, p_emitente_doc text, p_data date, p_valor numeric,
                                 p_ignorar uuid default null)
returns uuid
language sql stable security definer set search_path = '' as $$
  select id from public.despesas
  where status = 'lancada'
    and id is distinct from p_ignorar
    and ((p_chave is not null and chave_acesso = p_chave)
      or (p_emitente_doc is not null and emitente_doc = p_emitente_doc
          and data = p_data and valor_total = p_valor))
  order by criado_em desc
  limit 1
$$;

-- ---------------------------------------------------------------------------
-- Painel: quem passou do limite no mês (limite só informa o gestor)
-- ---------------------------------------------------------------------------
create view limites_estourados with (security_invoker = true) as
select l.funcionario_id, l.tipo_despesa_id, g.mes, l.valor_mensal,
       sum(g.total) as gasto
from public.limites l
join public.gasto_mensal g
  on g.funcionario_id = l.funcionario_id
 and (l.tipo_despesa_id is null or g.tipo_despesa_id = l.tipo_despesa_id)
group by 1, 2, 3, 4
having sum(g.total) > l.valor_mensal;

revoke all on function verificar_acesso(text, text, text) from public, anon, authenticated;
revoke all on function definir_rateio(uuid, uuid[]) from public, anon, authenticated;
revoke all on function buscar_duplicada(text, text, date, numeric, uuid) from public, anon, authenticated;
grant execute on function verificar_acesso(text, text, text) to service_role;
grant execute on function definir_rateio(uuid, uuid[]) to service_role;
grant execute on function buscar_duplicada(text, text, date, numeric, uuid) to service_role;
