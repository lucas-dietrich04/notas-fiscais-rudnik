# Prompt de extração (IA com visão)

Entrada: imagem/PDF do comprovante + texto/áudio transcrito que veio junto +
contexto montado do banco a cada mensagem.

## Prompt de sistema

```
Você lê comprovantes de despesa de funcionários externos da Rudnik.
Responda SOMENTE com JSON no formato pedido. Nunca invente dado: se não
conseguir ler com segurança, deixe null e liste o campo em "duvidas".

Tipos de despesa cadastrados e campos extras de cada um:
{{tipos_despesa_json}}

Obras: {{obras}}
Veículos (nome → placa): {{veiculos}}
Funcionários (para identificar colegas citados): {{funcionarios}}

Regras:
- Classifique o tipo de despesa pelo conteúdo. Se nenhum servir, tipo = null.
- documento_fiscal = true só se houver CNPJ do emitente E (chave de acesso,
  QR code da NFC-e ou número de nota/cupom fiscal). Recibo à mão = false.
- Valor total é o valor pago, não subtotal.
- Datas em AAAA-MM-DD. Valores com ponto decimal.
- Use o texto que o funcionário mandou junto para preencher extras
  (ex.: "carro do Aelcio, 45.300 km").
- Colegas: só nomes que o funcionário citou; não deduza.
- Se a imagem não for um comprovante de despesa, nao_comprovante = true.
```

## Saída (JSON Schema)

```json
{
  "type": "object",
  "required": ["nao_comprovante", "data", "valor_total", "emitente_nome", "tipo_despesa", "documento_fiscal", "extras", "colegas", "duvidas"],
  "properties": {
    "nao_comprovante": { "type": "boolean" },
    "data":            { "type": ["string", "null"], "description": "AAAA-MM-DD" },
    "valor_total":     { "type": ["number", "null"] },
    "emitente_nome":   { "type": ["string", "null"] },
    "emitente_doc":    { "type": ["string", "null"], "description": "CNPJ/CPF só dígitos" },
    "numero":          { "type": ["string", "null"] },
    "chave_acesso":    { "type": ["string", "null"], "description": "44 dígitos" },
    "forma_pagamento": { "type": ["string", "null"] },
    "cartao_final":    { "type": ["string", "null"], "description": "4 dígitos" },
    "tipo_despesa":    { "type": ["string", "null"], "description": "nome exato de um tipo cadastrado" },
    "tipo_servico":    { "type": ["string", "null"], "enum": ["instalacao", "assistencia_tecnica", null] },
    "obra":            { "type": ["string", "null"] },
    "veiculo_placa":   { "type": ["string", "null"] },
    "documento_fiscal":{ "type": "boolean" },
    "extras":          { "type": "object", "description": "chave do campo extra → valor" },
    "colegas":         { "type": "array", "items": { "type": "string" } },
    "duvidas":         { "type": "array", "items": { "type": "string" }, "description": "campos obrigatórios ou extras que faltam ou ficaram duvidosos" }
  }
}
```

O n8n decide o que perguntar a partir de `duvidas` + campos obrigatórios null
+ campos extras obrigatórios do tipo que ficaram vazios. A IA não decide se
lança.
