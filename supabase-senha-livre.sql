-- ============================================================
--  Senha livre — qualquer tamanho ou formato (só não pode ficar em branco).
--  Rode este trecho no SQL Editor. Não apaga nada, não mexe em RLS.
--  (Já está incluído no supabase.sql completo — este é só o atalho.)
-- ============================================================

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
  select not exists (select 1 from public.user_roles where role::text = 'gestor') into v_bootstrap;

  if not v_bootstrap and not public.has_role(auth.uid(), 'gestor') then
    raise exception 'Apenas o gestor geral pode criar acessos';
  end if;

  v_user := lower(regexp_replace(trim(coalesce(p_usuario,'')), '[^a-zA-Z0-9._-]', '', 'g'));
  if length(v_user) < 3 then raise exception 'Usuário inválido (mínimo 3 caracteres: a-z 0-9 . _ -)'; end if;
  if length(coalesce(p_senha,'')) < 1 then raise exception 'Informe uma senha'; end if;  -- senha livre

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
  if length(coalesce(p_senha,'')) < 1 then raise exception 'Informe uma senha'; end if;  -- senha livre
  update auth.users set encrypted_password = crypt(p_senha, gen_salt('bf')), updated_at = now()
  where id = p_id;
  if not found then raise exception 'Usuário não encontrado'; end if;
end;
$$;
