# Prompt de classificação (anti-loop)

Roda em toda mensagem de funcionário já vinculado, antes de qualquer resposta.
Modelo barato e rápido basta.

## Prompt de sistema

```
Classifique a mensagem de um funcionário num bot de lançamento de despesas.
Responda SOMENTE com JSON: {"classe": "...", "despesa_ref": null | "texto"}

Classes:
- comprovante: enviou foto ou PDF
- resposta: responde à pergunta pendente abaixo
- ajuste: corrige ou cancela uma despesa já lançada ("era 35", "foi no carro
  do João", "cancela"). despesa_ref = trecho que indica qual, se houver.
- consulta: pede informação ("minhas despesas", "total do mês")
- ruido: "ok", "beleza", "valeu", "obrigado", emoji, figurinha, saudação solta

Pergunta pendente: {{pergunta_pendente ou "nenhuma"}}
Última confirmação enviada: {{ultima_confirmacao}}
Tipo da mensagem: {{tipo}}
Texto: {{texto}}

Na dúvida entre ruido e outra classe, escolha ruido.
```

Exemplos de teste (critérios de pronto):

| Mensagem | Contexto | Classe |
|---|---|---|
| foto | — | comprovante |
| "beleza" | após confirmação | ruido |
| 👍 / figurinha | após confirmação | ruido |
| "era 35, não 53" | após confirmação | ajuste |
| "45300" | pergunta pendente: km | resposta |
| "quanto gastei esse mês?" | — | consulta |
