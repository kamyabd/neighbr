-- =====================================================================
--  Neighbr – Datenbank einrichten (Supabase)
--  Einmal komplett in Supabase › SQL Editor einfügen und auf „Run“ klicken.
--  Man kann das Skript gefahrlos mehrmals ausführen.
-- =====================================================================

-- Eine Tabelle für alles: Profile, Inserate, Chats, Aufträge, Meldungen,
-- Notfälle, Feedback und Anfragen zur Identitätsprüfung. Jede Zeile ist ein Dokument (JSON).
create table if not exists public.docs (
  col          text        not null,
  id           text        not null,
  data         jsonb       not null default '{}'::jsonb,
  owner        uuid,
  participants uuid[]      not null default '{}',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  primary key (col, id)
);
create index if not exists docs_participants_idx on public.docs using gin (participants);
create index if not exists docs_owner_idx on public.docs (owner);

-- Wer die Betreiber-Ansicht sehen darf.
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);

alter table public.docs   enable row level security;
alter table public.admins enable row level security;

-- ---------------------------------------------------------------------
-- Hilfsfunktionen
-- ---------------------------------------------------------------------
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

create or replace function public.admin_exists() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins);
$$;

-- Die erste Person, die das aufruft, wird Betreiber:in. Danach niemand mehr.
create or replace function public.claim_admin() returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return false; end if;
  lock table public.admins in exclusive mode;
  if exists (select 1 from public.admins) then
    return public.is_admin();
  end if;
  insert into public.admins (user_id) values (auth.uid());
  return true;
end $$;

-- Verschachtelte JSON-Objekte zusammenführen (für gleichzeitige Änderungen).
create or replace function public.jsonb_merge_deep(a jsonb, b jsonb) returns jsonb
language plpgsql immutable as $$
declare k text; v jsonb; res jsonb;
begin
  if b is null then return a; end if;
  if a is null or jsonb_typeof(a) <> 'object' or jsonb_typeof(b) <> 'object' then return b; end if;
  res := a;
  for k, v in select * from jsonb_each(b) loop
    if jsonb_typeof(v) = 'object' and jsonb_typeof(res -> k) = 'object' then
      res := res || jsonb_build_object(k, public.jsonb_merge_deep(res -> k, v));
    else
      res := res || jsonb_build_object(k, v);
    end if;
  end loop;
  return res;
end $$;

-- Nur bestimmte Schlüssel eines Objekts behalten.
create or replace function public.jsonb_pick(obj jsonb, keys text[]) returns jsonb
language sql immutable as $$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
  from jsonb_each(coalesce(obj, '{}'::jsonb)) where key = any(keys);
$$;

-- ---------------------------------------------------------------------
-- Lesen: Wer darf was sehen?
-- ---------------------------------------------------------------------
drop policy if exists docs_read on public.docs;
create policy docs_read on public.docs for select to authenticated using (
  case col
    when 'profiles' then true
    when 'listings' then true
    when 'threads'  then auth.uid() = any(participants) or public.is_admin()
    when 'orders'   then auth.uid() = any(participants) or public.is_admin()
    when 'reports'  then owner = auth.uid() or public.is_admin()
    else public.is_admin()            -- alerts, feedback, idreqs (Anfragen zur Identitätsprüfung)
  end
);
drop policy if exists admins_read on public.admins;
create policy admins_read on public.admins for select to authenticated using (user_id = auth.uid());

-- Direkt schreiben darf niemand. Alles läuft über doc_write (unten), das die Regeln prüft.
revoke insert, update, delete on public.docs   from anon, authenticated;
revoke insert, update, delete on public.admins from anon, authenticated;
revoke select on public.docs, public.admins from anon;

-- ---------------------------------------------------------------------
-- Schreiben: alle Regeln an einer Stelle
-- p_kind: 'set' (anlegen/ersetzen), 'update' (zusammenführen), 'delete'
-- ---------------------------------------------------------------------
create or replace function public.doc_write(p_col text, p_id text, p_kind text, p_data jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  me    uuid    := auth.uid();
  adm   boolean := public.is_admin();
  cur   public.docs%rowtype;
  has   boolean;
  nd    jsonb;
  patch jsonb;
  own   uuid;
  parts uuid[] := '{}';
  st    text;
  n     int;
begin
  if me is null then raise exception 'not_signed_in' using errcode = '42501'; end if;
  if p_col not in ('profiles','listings','threads','orders','reports','alerts','feedback','idreqs') then
    raise exception 'bad_collection' using errcode = '22023'; end if;
  if p_kind not in ('set','update','delete') then raise exception 'bad_kind' using errcode = '22023'; end if;
  if p_id is null or length(p_id) = 0 or length(p_id) > 80 then raise exception 'bad_id' using errcode = '22023'; end if;
  if p_data is not null and (jsonb_typeof(p_data) <> 'object' or octet_length(p_data::text) > 700000) then
    raise exception 'too_large' using errcode = '22023'; end if;

  select * into cur from public.docs where col = p_col and id = p_id for update;
  has := found;

  -- Löschen ---------------------------------------------------------
  if p_kind = 'delete' then
    if not has then return; end if;
    if adm or cur.owner = me then
      delete from public.docs where col = p_col and id = p_id;
      return;
    end if;
    raise exception 'not_granted' using errcode = '42501';
  end if;

  if p_kind = 'update' and not has then raise exception 'missing' using errcode = 'P0002'; end if;
  patch := coalesce(p_data, '{}'::jsonb);

  -- Profile ---------------------------------------------------------
  if p_col = 'profiles' then
    if not adm and p_id <> me::text then raise exception 'not_granted' using errcode = '42501'; end if;
    nd := case when has and p_kind = 'update' then public.jsonb_merge_deep(cur.data, patch) else patch end;
    if not adm then
      -- „Identität geprüft“ setzt nur das Team. Das Geschlecht ist nach der Prüfung fest.
      nd := nd || jsonb_build_object('idv', coalesce(cur.data -> 'idv', 'false'::jsonb));
      if has and coalesce((cur.data ->> 'idv')::boolean, false) then
        nd := nd || jsonb_build_object('gender', cur.data -> 'gender');
      end if;
    end if;
    own := case when has then cur.owner else (case when adm and p_id <> me::text then null else me end) end;
    if own is null and p_id ~ '^[0-9a-f-]{36}$' then own := p_id::uuid; end if;

  -- Inserate --------------------------------------------------------
  elsif p_col = 'listings' then
    if not has then
      if not adm and coalesce(patch ->> 'ownerId', '') <> me::text then raise exception 'not_granted' using errcode = '42501'; end if;
      nd := patch;
      if not adm and coalesce(nd ->> 'status', '') not in ('review','live') then
        nd := nd || '{"status":"review"}'::jsonb;
      end if;
      own := coalesce((nd ->> 'ownerId')::uuid, me);
    elsif adm or cur.owner = me then
      nd := case when p_kind = 'update' then public.jsonb_merge_deep(cur.data, patch) else patch end;
      if not adm then
        nd := nd || jsonb_build_object('ownerId', cur.data -> 'ownerId');
        st := nd ->> 'status';
        -- Was das Team (oder die automatische Prüfung) zurückhält, kann man nicht selbst freischalten.
        if st = 'live' and cur.data ->> 'status' in ('review','rejected') and coalesce(cur.data ->> 'flag', '') <> '' then
          nd := nd || jsonb_build_object('status', cur.data -> 'status');
        elsif st = 'live' and cur.data ->> 'status' = 'rejected' then
          nd := nd || '{"status":"review"}'::jsonb;
        elsif st is not null and st not in ('review','live','paused','rejected') then
          nd := nd || jsonb_build_object('status', cur.data -> 'status');
        end if;
      end if;
      own := cur.owner;
    else
      -- Andere dürfen nur: ansehen (Aufrufe), merken, Termine buchen, bewerten.
      if p_kind = 'set' then raise exception 'not_granted' using errcode = '42501'; end if;
      patch := public.jsonb_pick(patch, array['views','favs','bookedMap','reviewMap']);
      if patch ? 'views' then patch := patch || jsonb_build_object('views', public.jsonb_pick(patch -> 'views', array[me::text])); end if;
      if patch ? 'favs'  then patch := patch || jsonb_build_object('favs',  public.jsonb_pick(patch -> 'favs',  array[me::text])); end if;
      nd := public.jsonb_merge_deep(cur.data, patch);
      own := cur.owner;
    end if;

  -- Chats und Aufträge ----------------------------------------------
  elsif p_col in ('threads','orders') then
    if not has then
      begin
        select array_agg(x::uuid) into parts from jsonb_array_elements_text(coalesce(patch -> 'participants', '[]'::jsonb)) x;
      exception when others then
        raise exception 'bad_participants' using errcode = '22023';
      end;
      parts := coalesce(parts, '{}');
      if cardinality(parts) <> 2 or parts[1] = parts[2] or not (me = any(parts) or adm) then
        raise exception 'not_granted' using errcode = '42501'; end if;
      if p_col = 'threads' and not adm and coalesce(patch ->> 'buyerId', '') <> me::text then
        raise exception 'not_granted' using errcode = '42501'; end if;
      nd := patch;
      own := me;
    else
      if not (adm or me = any(cur.participants)) then raise exception 'not_granted' using errcode = '42501'; end if;
      nd := case when p_kind = 'update' then public.jsonb_merge_deep(cur.data, patch) else patch end;
      -- Wer beteiligt ist, bleibt fest.
      nd := nd || public.jsonb_pick(cur.data, array['participants','buyerId','providerId']);
      parts := cur.participants;
      own := cur.owner;
    end if;

  -- Meldungen, Notfälle, Feedback, Anfragen zur Identitätsprüfung -------------------------------------
  else
    if has and not adm then raise exception 'not_granted' using errcode = '42501'; end if;
    if has then
      nd := case when p_kind = 'update' then public.jsonb_merge_deep(cur.data, patch) else patch end;
      own := cur.owner;
    else
      nd := patch || jsonb_build_object('byId', me::text);
      if not adm then nd := nd || '{"status":"open"}'::jsonb; end if;
      own := me;
    end if;
  end if;

  insert into public.docs as d (col, id, data, owner, participants, updated_at)
  values (p_col, p_id, nd, own, parts, now())
  on conflict (col, id) do update set data = excluded.data, participants = excluded.participants, updated_at = now();

  -- Nach drei Meldungen von verschiedenen Personen wird ein Inserat automatisch pausiert.
  if p_col = 'reports' and not has and coalesce(nd ->> 'listingId', '') <> '' then
    select count(distinct owner) into n from public.docs
      where col = 'reports' and data ->> 'listingId' = nd ->> 'listingId' and data ->> 'status' = 'open';
    if n >= 3 then
      update public.docs
        set data = data || jsonb_build_object('status', 'review', 'flag', 'Automatisch pausiert: ' || n || ' Meldungen'), updated_at = now()
        where col = 'listings' and id = nd ->> 'listingId' and data ->> 'status' = 'live';
    end if;
  end if;
end $$;

-- Konto löschen: Profil, eigene Inserate, Meldungen und Feedback weg, dann das Login.
-- Chats und Aufträge bleiben für die andere Person erhalten, dein Name wird dort zu „Jemand“.
create or replace function public.delete_me() returns void
language plpgsql security definer set search_path = public, auth as $$
declare me uuid := auth.uid();
begin
  if me is null then return; end if;
  delete from public.docs where owner = me and col in ('profiles','listings','reports','feedback','idreqs');
  delete from public.docs where col = 'profiles' and id = me::text;
  delete from auth.users where id = me;
end $$;

-- Nur angemeldete Personen dürfen diese Funktionen aufrufen.
revoke execute on function public.doc_write(text,text,text,jsonb) from public, anon;
revoke execute on function public.delete_me()   from public, anon;
revoke execute on function public.claim_admin() from public, anon;
revoke execute on function public.admin_exists() from public, anon;
revoke execute on function public.is_admin()     from public, anon;
grant  execute on function public.doc_write(text,text,text,jsonb) to authenticated;
grant  execute on function public.delete_me()    to authenticated;
grant  execute on function public.claim_admin()  to authenticated;
grant  execute on function public.admin_exists() to authenticated;
grant  execute on function public.is_admin()     to authenticated;
grant  select on public.docs, public.admins to authenticated;

-- Live-Updates einschalten.
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'docs') then
    alter publication supabase_realtime add table public.docs;
  end if;
end $$;

select 'Neighbr-Datenbank ist eingerichtet ✔' as ergebnis;
