# Controle de Produção JR Joias — réplica

Réplica funcional do app **https://controle-produ.lovable.app**, em **arquivo único**
`index.html` (sem build, sem Node), no mesmo padrão do *Gestão KPI* / *Pesquisa JR*.

Usa **o mesmo back-end do app original**: projeto Supabase `ldbeszdlsaubfyjtsosi`,
tabelas `pedidos` / `perfis` / `user_roles`. Lê e grava os mesmos dados.

---

## Arquivos

| Arquivo | Função |
|---|---|
| `index.html` | O app inteiro: login, resumo, histórico, acessos. |
| `assets/favicon.ico` | Ícone do app original. |
| `serve.ps1` | Servidor estático local (PowerShell puro, para testar no Windows). |
| `supabase.sql` | Garante tabelas/RLS e adiciona 3 funções de gestão de acesso. Rodar 1×. |

---

## Telas (iguais ao original)

| Rota | Tela |
|---|---|
| `#/auth` | Login por **usuário + senha**. No 1º acesso do sistema: "crie o gestor geral". |
| `#/` | **Resumo** — pedidos em aberto: cards, busca, filtro de etapa, tabela. **Gestor geral:** troca de etapa em linha, confirmar entrega, editar, excluir, novo pedido. **Demais:** só visualizam. |
| `#/historico` | **Histórico** — filtro por período e situação, tabela e **Gerar PDF**. **Gestor geral:** botão de excluir lançamento em cada linha (inclusive já entregues). |
| `#/usuarios` | **Acessos** — só o gestor geral cria/edita senha/remove. Lista quem tem acesso. |

### Quem pode o quê

| | Gestor geral | Demais acessos |
|---|---|---|
| Ver resumo e histórico | ✅ | ✅ |
| Gerar relatório PDF | ✅ | ✅ |
| Criar / editar / excluir pedido, trocar etapa, confirmar entrega | ✅ | ❌ (nem aparecem os botões) |
| Excluir lançamento pelo histórico | ✅ | ❌ |
| Criar / remover acessos | ✅ | ❌ |

Isso é travado **no banco** (RLS: `pedidos` só aceita `insert/update/delete` de quem
tem papel `gestor`) — esconder os botões é só a camada visual.

Constantes preservadas: origens (PRESTAÇÃO, PEDIDO, VENDAS (JR/BG/BG PROMO.)),
etapas (ESTOQUE → ALMOXARIFADO → OFICINA → GALVÂNICA → BANHO → CATAFORÉTICO →
PADRONIZAÇÃO → FINALIZADO), prioridades (1 Alta / 2 Média / 3 Baixa).
"Confirmar entrega" marca `entregue`, grava `entregue_em` e move para `FINALIZADO`.

---

## Rodar localmente (Windows, sem instalar nada)

```powershell
powershell -ExecutionPolicy Bypass -File .\serve.ps1 -Port 8778
```
Abra `http://localhost:8778/`. Rotas com hash (`#/`, `#/historico`, `#/usuarios`).

## Publicar

Host estático (Netlify, GitHub Pages…). Suba `index.html` + `assets/`. Sem variáveis
de ambiente — a URL e a *publishable key* do Supabase são públicas (já estão no
bundle do app original).

---

## Configuração do back-end

Dentro do `index.html`:
```js
const SUPABASE_URL = 'https://ldbeszdlsaubfyjtsosi.supabase.co';
const SUPABASE_KEY  = 'sb_publishable_brZmQrqMgBc-66bVfxAu4w_pgihloO-';
const EMAIL_DOMAIN  = 'jrjoias.local';   // usuário "maria" -> login maria@jrjoias.local
```

### Rode o `supabase.sql` (uma vez, no SQL Editor)

O app original cria usuários por **Cloud Functions do Lovable**, que a réplica não
consegue chamar. O `supabase.sql` põe no lugar 3 funções SQL equivalentes:

| Função | Quem chama | O que faz |
|---|---|---|
| `criar_usuario(usuario, senha, nome)` | 1º acesso (anônimo) **ou** gestor logado | cria o login (usuário + senha), o perfil e — no 1º de todos — o papel `gestor` |
| `definir_senha(id, senha)` | gestor | troca a senha de alguém |
| `remover_usuario(id)` | gestor | apaga o login |

> Essas funções gravam direto em `auth.users` / `auth.identities` (padrão conhecido
> para "login por usuário, sem e-mail, criado pelo admin"). Se a sua versão do
> Supabase recusar algum campo, me avise que eu troco por **Edge Functions**.

### Primeiro uso

1. Rode o `supabase.sql`.
2. **Se ainda não existe gestor:** abra a réplica → a tela de login mostra
   "Primeiro acesso: crie o acesso do gestor geral". Cadastre usuário + nome + senha.
3. **Se o app original já tem um gestor:** entre com esse usuário/senha. Os logins
   criados pela réplica e pelo app original são intercambiáveis (mesmo banco, mesmo
   domínio `@jrjoias.local`).
4. Na tela **Acessos**, o gestor cria os demais usuários.

---

## Diferenças / mudanças em relação ao original

| Item | Original | Réplica |
|---|---|---|
| Marca **JR JOIAS** | no topo de todas as telas e no PDF | **removida** (título só "Controle de Produção") |
| Editar / apagar pedidos | qualquer usuário logado | **só o gestor geral**; os demais visualizam e geram PDF |
| Excluir do histórico | não tinha | **gestor geral** exclui lançamentos (inclusive entregues) direto no histórico |
| PDF do histórico | tabela | tabela **+ linha de total no fim**: nº de pedidos e soma dos valores |
| Renderização | React SSR (Lovable) | 100% client-side, arquivo único |
| Rotas | `/auth`, `/`, `/historico`, `/usuarios` | as mesmas com `#` (funciona em qualquer host) |
| Gestão de usuários | Cloud Functions do Lovable | funções SQL (`supabase.sql`) |
| Componentes | Radix (select, dialog) | `<select>` e `<dialog>` nativos |

> O domínio interno de login continua `usuario@jrjoias.local` (é infraestrutura, não
> aparece na tela) — mudá-lo quebraria os logins já existentes no banco.

Resto igual: colunas de `pedidos`, cálculo de "dias restantes" (`Date.UTC`), filtros
do histórico, cores do PDF (`[45,41,34]` / `[226,183,90]`), nome do arquivo
`historico-pedidos-<de>-a-<até>.pdf`.
