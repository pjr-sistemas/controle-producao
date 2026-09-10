-- ============================================================
--  Vários gestores gerais — promover / rebaixar acessos.
--  Rode este trecho no Editor SQL do Lovable. Não apaga nada.
--  (Já está incluído no supabase.sql completo — este é só o atalho.)
--
--  Depois disso, na tela "Acessos":
--   • ao criar um acesso, dá pra marcar "Este acesso é gestor geral";
--   • em cada pessoa aparece "Tornar gestor" / "Tirar gestor".
--  Todo gestor geral edita a planilha; os demais só visualizam.
-- ============================================================

create or replace function public.definir_gestor(p_id uuid, p_gestor boolean)
returns void
language plpgsql security definer
set search_path = public, auth
as $$
begin
  if not public.has_role(auth.uid(), 'gestor') then
    raise exception 'Apenas o gestor geral pode definir gestores';
  end if;

  if p_gestor then
    if not exists (select 1 from public.user_roles where user_id = p_id and role::text = 'gestor') then
      insert into public.user_roles (user_id, role) values (p_id, 'gestor');
    end if;
  else
    if p_id = auth.uid() then
      raise exception 'Você não pode tirar o seu próprio acesso de gestor';
    end if;
    if (select count(*) from public.user_roles where role::text = 'gestor') <= 1 then
      raise exception 'Precisa existir pelo menos um gestor geral';
    end if;
    delete from public.user_roles where user_id = p_id and role::text = 'gestor';
  end if;
end;
$$;

revoke all on function public.definir_gestor(uuid, boolean) from public;
grant execute on function public.definir_gestor(uuid, boolean) to authenticated;
