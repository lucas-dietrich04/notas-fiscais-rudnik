\set ON_ERROR_STOP on
-- Rodar depois das migrations, num banco limpo.
insert into funcionarios (nome, cpf, data_nascimento) values
 ('Lucas','11111111111','1990-01-02'),('João','22222222222','1991-01-02'),('José','33333333333','1992-01-02');

-- Primeiro acesso
select verificar_acesso('5547900000001', '111.111.111-11', '02/01/1990')->>'status' = 'ok' as acesso_ok_com_mascara;
select telefone = '5547900000001' as telefone_vinculado from funcionarios where nome = 'Lucas';
select verificar_acesso('5547900000002', '22222222222', '00000000')->>'status' = 'invalido' as erro_1;
select verificar_acesso('5547900000002', '22222222222', '00000000')->>'status' = 'invalido' as erro_2;
select verificar_acesso('5547900000002', '22222222222', '00000000')->>'status' = 'bloqueado' as erro_3_bloqueia;
select verificar_acesso('5547900000002', '22222222222', '02011991')->>'status' = 'bloqueado' as bloqueado_mesmo_com_senha_certa;
-- Trocou de número: o novo leva o vínculo
select verificar_acesso('5547900000009', '11111111111', '02011990')->>'status' = 'ok' as troca_de_numero;
select telefone = '5547900000009' as telefone_novo from funcionarios where nome = 'Lucas';
select funcionario_id is null as conversa_antiga_desvinculada from conversas where telefone = '5547900000001';

-- Rateio: hotel R$ 300 com 2 colegas = 3 x 100
insert into despesas (lancado_por, status, data, valor_total, emitente_doc)
select id, 'lancada', '2026-11-10', 300, '12345678000199' from funcionarios where nome = 'Lucas';
select count(*) = 3 and bool_and(valor = 100) as rateio_3x100
from definir_rateio((select id from despesas limit 1),
                    array(select id from funcionarios where nome in ('João', 'José', 'Lucas')));

-- R$ 100 em 3: sobra de 1 centavo fica com quem lançou
update despesas set valor_total = 100;
select sum(valor) = 100 and max(valor) = 33.34 as soma_fecha
from definir_rateio((select id from despesas limit 1), array(select id from funcionarios where nome <> 'Lucas'));
select valor = 33.34 as centavo_com_lancador from despesa_partes p join funcionarios f on f.id = p.funcionario_id where f.nome = 'Lucas';

-- Sem colegas = 1 parte
select count(*) = 1 as sem_rateio from definir_rateio((select id from despesas limit 1));

-- Duplicidade
select buscar_duplicada(null, '12345678000199', '2026-11-10', 100) is not null as duplicada_achada;
select buscar_duplicada(null, '12345678000199', '2026-11-10', 99) is null as valor_diferente_nao;

-- Limite estourado
insert into limites (funcionario_id, valor_mensal) select id, 50 from funcionarios where nome = 'Lucas';
select count(*) = 1 as limite_estourado from limites_estourados;
