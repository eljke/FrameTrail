create or replace function frametrail_private.put_library_item(
    p_media_id text, p_payload jsonb, p_expected_revision bigint, p_deleted boolean
)
returns table (media_id text, payload jsonb, revision bigint, deleted boolean)
language plpgsql security definer set search_path = '' as $$
declare
    owner_id uuid := auth.uid();
begin
    if owner_id is null or not exists (
        select 1 from auth.users u where u.id = owner_id and u.email_confirmed_at is not null
    ) then
        raise exception 'An authenticated verified account is required' using errcode = '42501';
    end if;
    if p_expected_revision is null or p_expected_revision < 0 or p_expected_revision = 9223372036854775807
        or p_media_id is null or length(btrim(p_media_id)) not between 1 and 256
        or p_media_id ~ '[[:cntrl:]]' or p_deleted is null then
        raise exception 'Invalid record identity or revision' using errcode = '22023';
    end if;
    if p_deleted then
        if p_payload is not null then
            raise exception 'Deleted records must not contain a payload' using errcode = '22023';
        end if;
    elsif p_payload is null or jsonb_typeof(p_payload) is distinct from 'object'
        or octet_length(p_payload::text) > 131072
        or p_payload -> 'title' ->> 'id' is distinct from p_media_id
        or jsonb_typeof(p_payload -> 'title') is distinct from 'object'
        or jsonb_typeof(p_payload -> 'progress') is distinct from 'object'
        or jsonb_typeof(p_payload -> 'reflections') is distinct from 'array'
        or (select count(*) from jsonb_object_keys(p_payload)) <> 3 then
        raise exception 'Invalid library payload' using errcode = '22023';
    end if;

    if p_expected_revision = 0 then
        if (select count(*) from public.library_items i where i.user_id = owner_id) >= 10000 then
            raise exception 'Cloud library limit reached' using errcode = '54000';
        end if;
        return query insert into public.library_items as i (user_id, media_id, payload, revision, deleted)
        values (owner_id, p_media_id, p_payload, 1, p_deleted)
        on conflict on constraint library_items_pkey do nothing
        returning i.media_id, i.payload, i.revision, i.deleted;
    else
        return query update public.library_items as i
        set payload = p_payload, deleted = p_deleted, revision = i.revision + 1, updated_at = now()
        where i.user_id = owner_id and i.media_id = p_media_id and i.revision = p_expected_revision
        returning i.media_id, i.payload, i.revision, i.deleted;
    end if;
end;
$$;
