-- ============================================================
--  Controle de Produção JR Joias — banco (Supabase ldbeszdlsaubfyjtsosi)
--  Rode este arquivo INTEIRO no SQL Editor. É idempotente e NÃO apaga dados.
--
--  O app original (Lovable) já tem as tabelas pedidos / perfis / user_roles e
--  as RPCs existe_gestor() / has_role(). Este script:
--   • garante que essas tabelas e RLS existam (não mexe se já existirem);
--   • adiciona 3 funções que a réplica usa no lugar das "Cloud Functions" do
--     Lovable: criar_usuario / definir_senha / remover_usuario.
--
--  MODELO DE ACESSO
--   • Login por USUÁRIO (vira e-mail interno usuario@jrjoias.local).
--   • 1º acesso do sistema = GESTOR GERAL (papel 'gestor').
--   • Novos acessos: só o gestor geral cria, na tela "Acessos" do app.
--   • Nenhum cadastro público.
-- ============================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------- Tabelas (só cria se não existirem) ----------
create table if not exists public.pedidos (
  id           uuid primary key default gen_random_uuid(),
  cliente      text not null,
  origem       text not null default 'PEDIDO',
  prioridade   smallint not null default 3 check (prioridade between 1 and 3),
  recebimento  date not null default current_date,
  entrega      date not null default current_date,
  etapa        text not null default 'ESTOQUE',
  data_entrada date not null default current_date,
  valor        numeric,
  observacao   text,
  entregue     boolean not null default false,
  entregue_em  date,
  created_at   timestamptz not null default now()
);
create index if not exists pedidos_entrega_idx on public.pedidos (entregue, entrega);

create table if not exists public.perfis (
  id         uuid primary key references auth.users(id) on delete cascade,
  usuario    text unique not null,
  nome       text,
  created_at timestamptz not null default now()
);

create table if not exists public.user_roles (
  id      uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role    text not null,
  unique (user_id, role)
);

-- ---------- Funções de papel ----------
create or replace function public.has_role(_user_id uuid, _role text)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from public.user_roles where user_id = _user_id and role = _role);
$$;

create or replace function public.existe_gestor()
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from public.user_roles where role = 'gestor');
$$;

grant execute on function public.has_role(uuid, text) to anon, authenticated;
grant execute on function public.existe_gestor() to anon, authenticated;

-- ---------- Criação / manutenção de acessos (substitui as Cloud Functions) ----------
create or replace function public.criar_usuario(p_usuario text, p_senha text, p_nome text default null)
returns uuid
language plpgsql security definer
set search_path = public, extensions, auth
as $$
declare
  v_bootstrap boolean;
  v_user      text;
  v_email     text;
  v_id        uuid := gen_random_uuid();
begin
  select not exists (select 1 from public.user_roles where role = 'gestor') into v_bootstrap;

  if not v_bootstrap and not public.has_role(auth.uid(), 'gestor') then
    raise exception 'Apenas o gestor geral pode criar acessos';
  end if;

  v_user := lower(regexp_replace(trim(coalesce(p_usuario,'')), '[^a-zA-Z0-9._-]', '', 'g'));
  if length(v_user) < 3 then raise exception 'Usuário inválido (mínimo 3 caracteres a-z 0-9 . _ -)'; end if;
  if length(coalesce(p_senha,'')) < 6 then raise exception 'A senha deve ter ao menos 6 caracteres'; end if;

  v_email := v_user || '@jrjoias.local';
  if exists (select 1 from auth.users where email = v_email) then
    raise exception 'Esse usuário já existe';
  end if;

  insert into auth.users
    (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
     raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
     confirmation_token, email_change, email_change_token_new, recovery_token)
  values
    ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
     v_email, crypt(p_senha, gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb,
     jsonb_build_object('usuario', v_user, 'nome', nullif(trim(coalesce(p_nome,'')), '')),
     now(), now(), '', '', '', '');

  insert into auth.identities
    (provider_id, user_id, identity_data, provider, created_at, updated_at, last_sign_in_at)
  values
    (v_id::text, v_id,
     jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true),
     'email', now(), now(), now());

  insert into public.perfis (id, usuario, nome)
  values (v_id, v_user, nullif(trim(coalesce(p_nome,'')), ''));

  if v_bootstrap then
    insert into public.user_roles (user_id, role) values (v_id, 'gestor');
  end if;

  return v_id;
end;
$$;

create or replace function public.definir_senha(p_id uuid, p_senha text)
returns void
language plpgsql security definer
set search_path = public, extensions, auth
as $$
begin
  if not public.has_role(auth.uid(), 'gestor') then
    raise exception 'Apenas o gestor geral pode alterar senhas';
  end if;
  if length(coalesce(p_senha,'')) < 6 then raise exception 'A senha deve ter ao menos 6 caracteres'; end if;
  update auth.users set encrypted_password = crypt(p_senha, gen_salt('bf')), updated_at = now()
  where id = p_id;
  if not found then raise exception 'Usuário não encontrado'; end if;
end;
$$;

create or replace function public.remover_usuario(p_id uuid)
returns void
language plpgsql security definer
set search_path = public, auth
as $$
begin
  if not public.has_role(auth.uid(), 'gestor') then
    raise exception 'Apenas o gestor geral pode remover acessos';
  end if;
  if p_id = auth.uid() then raise exception 'Você não pode remover o seu próprio acesso'; end if;
  delete from auth.users where id = p_id;   -- cascata: identities, perfis, user_roles
end;
$$;

revoke all on function public.criar_usuario(text, text, text) from public;
revoke all on function public.definir_senha(uuid, text)      from public;
revoke all on function public.remover_usuario(uuid)          from public;
grant execute on function public.criar_usuario(text, text, text) to anon, authenticated; -- anon só passa no 1º acesso
grant execute on function public.definir_senha(uuid, text)      to authenticated;
grant execute on function public.remover_usuario(uuid)          to authenticated;

-- ---------- RLS ----------
alter table public.pedidos     enable row level security;
alter table public.perfis      enable row level security;
alter table public.user_roles  enable row level security;

-- pedidos: toda a equipe logada LÊ; só o gestor geral cria / edita / apaga
drop policy if exists "pedidos equipe"   on public.pedidos;
drop policy if exists "pedidos leitura"  on public.pedidos;
drop policy if exists "pedidos gestor insere" on public.pedidos;
drop policy if exists "pedidos gestor edita"  on public.pedidos;
drop policy if exists "pedidos gestor apaga"  on public.pedidos;

create policy "pedidos leitura" on public.pedidos
  for select to authenticated using (true);
create policy "pedidos gestor insere" on public.pedidos
  for insert to authenticated with check (public.has_role(auth.uid(), 'gestor'));
create policy "pedidos gestor edita" on public.pedidos
  for update to authenticated using (public.has_role(auth.uid(), 'gestor')) with check (public.has_role(auth.uid(), 'gestor'));
create policy "pedidos gestor apaga" on public.pedidos
  for delete to authenticated using (public.has_role(auth.uid(), 'gestor'));

-- perfis / user_roles: logado lê; escrita só pelas funções acima (security definer)
drop policy if exists "perfis leitura" on public.perfis;
create policy "perfis leitura" on public.perfis
  for select to authenticated using (true);

drop policy if exists "roles leitura" on public.user_roles;
create policy "roles leitura" on public.user_roles
  for select to authenticated using (true);

-- ============================================================
--  DEPOIS DE RODAR: abra a réplica, tela "Entrar" mostrará
--  "Primeiro acesso: crie o acesso do gestor geral".
--  Crie o usuário do gestor. Os demais acessos saem da tela "Acessos".
-- ============================================================
