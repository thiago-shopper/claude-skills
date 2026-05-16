# Examples

Two worked examples for `create-pr`. The first matches the inline example in `SKILL.md` (single-commit bugfix, default body). The second is a multi-commit feature branch in a repo with a Portuguese `pull_request_template.md` at a non-default path.

---

## Example 1 — Single-commit bugfix, no template

**Input:**

- Head branch: `fix/null-check-on-empty-cart`
- Target: `main` (passed as `/create-pr main`)
- Commits ahead:
  - `a1b2c3d Fix NPE when cart is empty during checkout`
- Diff stat:
  ```
  src/checkout/cart.ts            | 4 ++++
  tests/checkout/cart.test.ts     | 15 +++++++++++++++
  2 files changed, 19 insertions(+)
  ```
- No PR template detected.
- Repo title style sample (last 10 merged PRs): plain imperative, no emoji, no Conventional Commits prefix.

**Emitted title:**

```
Fix NPE on empty cart during checkout
```

**Emitted body:**

```markdown
## Purpose
Checkout crashed with a null pointer when the cart was emptied right before submit. This restores the guard so empty-cart submissions return the expected "cart is empty" message instead of a 500.

## Summary
- Add empty-array guard at the top of `submitCheckout` in `src/checkout/cart.ts`.
- Add a regression test covering the empty-cart path.

## Test plan
- `npm test -- cart.test.ts` passes the new case.
- Manual: emptied the cart in staging and confirmed the "cart is empty" message renders instead of a 500.
```

Word count: ~75. Passes all 10 checklist items.

---

## Example 2 — Multi-commit feature, Portuguese template at a non-default path

**Input:**

- Repo: monorepo with `kdb-retail/retail_api/pull_request_template.md`.
- Head branch: `feature/supplier-credit-limit`
- Target: `develop` (passed as `/create-pr develop`)
- Commits ahead:
  - `b3c4d5e Add credit_limit column to suppliers table`
  - `c4d5e6f Wire credit_limit through the supplier API`
  - `d5e6f7a Block order creation when supplier credit_limit is exceeded`
  - `e6f7a8b Add tests for credit-limit enforcement`
- Diff stat: 6 files changed across migrations, API handlers, order service, and tests.
- Repo title style: plain imperative in Portuguese.
- Template detected at `kdb-retail/retail_api/pull_request_template.md` (Portuguese, **bold** section labels + instructional HTML comments).

**Step 5 (classification):** all four commits cluster around one purpose — adding credit-limit enforcement. No ambiguity to surface.

**Emitted title:**

```
Adicionar limite de crédito por fornecedor e bloquear pedidos que excedam
```

**Emitted body (preserves the template's bold labels and HTML comments verbatim, fills each section in Portuguese):**

```markdown
**O que foi alterado nesse PR?**
<!-- Explique as alterações feitas no código, de forma clara e objetiva como uma lista. -->
- Adicionada coluna `credit_limit` na tabela `suppliers` (migration nova).
- Exposto `credit_limit` na API de fornecedores (leitura e atualização).
- `OrderService.create` agora valida o saldo de crédito do fornecedor antes de criar o pedido e bloqueia com erro 422 quando o limite seria excedido.
- Adicionados testes cobrindo o caminho de bloqueio e o caminho permitido.

**Porque foi necessária a alteração?**
<!-- Explique o motivo das alterações, quais os impactos no negócio? Use exemplos caso necessário. -->
O time de Compras precisa de um teto operacional por fornecedor para evitar pedidos que ultrapassem o crédito acordado e gerem inadimplência. Sem esse limite, o controle ficava manual e propenso a erro.

**Como testar a alteração?**
<!-- Explique o passo a passo de como reproduzir o comportamento esperado da alteração. -->
1. Rodar a migration: `make migrate`.
2. Definir `credit_limit = 1000` em um fornecedor de teste via API.
3. Criar um pedido somando R$ 1200 desse fornecedor — deve retornar 422 com a mensagem de limite excedido.
4. Criar um pedido somando R$ 800 — deve ser aceito normalmente.
5. Rodar a suíte: `pytest tests/orders/test_credit_limit.py`.

**Relacionado com:**
<!-- Caso esse PR esteja relacionado com outros PRs de outros projetos, liste-os abaixo. -->
N/A

**Link para o ClickUp:**
<!-- Caso o PR tenha uma tarefa relacionada no ClickUp, cole o link dela aqui. -->
<!-- O usuário deve preencher antes de revisar. -->
```

Word count: ~190. Passes all 10 checklist items. Note that:

- The template's instructional HTML comments are preserved verbatim — they help the next contributor.
- The "Link para o ClickUp" section is left as a comment placeholder because the diff doesn't contain a ClickUp URL; the skill should not invent one.
- Body is in Portuguese to match the template's language.
- The "Relacionado com" section is filled honestly ("N/A") rather than fabricating cross-project links.

---

## What both examples have in common

- Title is short, imperative, no marketing words.
- Purpose / first section is 1–3 sentences answering *why*.
- Summary bullets are grouped by purpose, not by file.
- Test plan is concrete (commands the reviewer can run, or honest manual steps).
- Nothing in the body is invented — every claim is traceable to the commits or diff.
